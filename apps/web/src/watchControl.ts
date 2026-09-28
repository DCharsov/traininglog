import { db, watchControls, type WatchCommand } from './data'
import { uid } from './domain'
import { ApiError, api, applyWatchSnapshot, canonical, syncOnce } from './sync'
import { getWatchControl, type WatchSnapshot } from './watchApi'

export async function refreshWatchControl(id:string) {
 return navigator.locks.request('traininglog-sync',async()=>applyWatchSnapshot(await getWatchControl(id)))
}
export async function retryWatchCommand(id:string) {
 return navigator.locks.request('traininglog-sync',async()=>{
  const control=await watchControls.get(id)
  if(!control?.pending)throw new Error('Нет ожидающего запроса')
  try {
   await api<WatchSnapshot>(control.pending.path,'POST',control.pending.body)
   // A replay receipt proves the command committed, not that ownership stayed unchanged.
   await applyWatchSnapshot(await getWatchControl(id),true)
  }catch(e){
   if(e instanceof ApiError&&[400,409,503].includes(e.status))await applyWatchSnapshot(await getWatchControl(id),true)
   throw e
  }
 })
}
export async function handoffToWatch(id:string,deviceId:string) {
 // Caller has drained the editor queue. This DB gate prevents subsequent writes in any tab.
 await db.transaction('rw',watchControls,async()=>{
  const current=await watchControls.get(id)
  if(current&&current.state!=='phone')throw new Error('Передача уже идёт')
  await watchControls.put({id,state:'preparing',controlEpoch:current?.controlEpoch??0,checkedAt:Date.now()})
 })
 try {
  await syncOnce() // Never hold traininglog-sync while acquiring it recursively.
  await navigator.locks.request('traininglog-sync',async()=>{
   const snapshot=await getWatchControl(id),local=await db.sessions.get(id),meta=await db.meta.get(`sessions:${id}`)
   if(!local||meta?.conflict||canonical(local)!==meta?.synced||meta.version!==snapshot.version)throw new Error('Сначала устраните конфликт или дождитесь синхронизации')
   if(snapshot.control.state!=='phone')throw new Error('Тренировка уже передана')
   const body:WatchCommand={operationId:uid(),sessionId:id,deviceId,generation:snapshot.generation,baseVersion:snapshot.version,controlEpoch:snapshot.control.controlEpoch}
   const path=`/sessions/${id}/watch-handoff`
   await watchControls.put({id,...snapshot.control,state:'preparing',checkedAt:Date.now(),pending:{path,body}})
  })
  await retryWatchCommand(id)
 } catch(e) {
  const control=await watchControls.get(id)
  // If a request might have reached the server keep its immutable body and the lock.
  if(!control?.pending)await navigator.locks.request('traininglog-sync',async()=>applyWatchSnapshot(await getWatchControl(id),true)).catch(()=>{})
  throw e
 }
}
export async function returnWatchControl(id:string,force:boolean) {
 await navigator.locks.request('traininglog-sync',async()=>{
  const current=await watchControls.get(id)
  if(current?.pending)throw new Error('Сначала подтвердите предыдущий запрос')
  const snapshot=await getWatchControl(id)
  const body:WatchCommand={operationId:uid(),sessionId:id,generation:snapshot.generation,baseVersion:snapshot.version,controlEpoch:snapshot.control.controlEpoch,handoffId:snapshot.control.handoffId}
  const path=`/sessions/${id}/${force?'watch-force-return':'watch-handoff/cancel'}`
  await watchControls.put({id,...snapshot.control,state:'preparing',checkedAt:Date.now(),pending:{path,body}})
 })
 await retryWatchCommand(id)
}
