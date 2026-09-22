import type { components } from './api.generated'
type Contract = components['schemas']
import type { Table } from 'dexie'
import { db, type SyncMeta, type SyncOperation, type Kind, type Document } from './data'
import { programSchema, sessionSchema, equipmentSchema, calendarSchema, uid, type Session } from './domain'
export type { Kind } from './data'
const kinds:Kind[]=['programs','sessions','equipment','calendar']
export const canonical = (value: unknown): string => JSON.stringify(value, (_key,v) => v && typeof v==='object' && !Array.isArray(v) ? Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])) : v)
export function decode(kind: Kind, value: unknown) { return {programs:programSchema,sessions:sessionSchema,equipment:equipmentSchema,calendar:calendarSchema}[kind].parse(value) }
const keyOf=(kind: Kind,id:string)=>`${kind}:${id}`
export class ApiError extends Error { status: number; data: Record<string,unknown>; constructor(status:number,data: Record<string,unknown>) { super(String(data.message ?? (status===401?'Нужен вход':status===429?'Слишком много попыток. Подождите минуту.':'Сервер временно недоступен')));this.status=status;this.data=data } }
let csrf=''
export async function api<T=unknown>(path:string,method='GET',body?:unknown):Promise<T> {
  const response=await fetch(`/training/api${path}`,{method,credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json',...(method!=='GET'?{'X-CSRF-TOKEN':csrf}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)})
  const data=await response.json().catch(()=>({}))
  if(!response.ok) throw new ApiError(response.status,data)
  return data
}
export async function authState():Promise<boolean> { const state=await api<Contract['AuthState']>('/auth/state');csrf=state.token;return state.authenticated===true }
export async function login(password:string) {await authState();await api('/auth/login','POST',{password});await authState()}
export async function logout() {await api('/auth/logout','POST');csrf=''}
const tables=[db.programs,db.sessions,db.equipment,db.calendar,db.meta,db.operations,db.syncState,db.outbox,db.conflictArchive]
async function put(kind:Kind,p:Document) {await (db[kind] as Table<Document,string>).put(p)}
async function get(kind:Kind,id:string):Promise<Document|undefined> {return db[kind].get(id)}
async function activeClash(kind:Kind,p:Document) {return kind==='sessions' && !p.deletedAt && (p as Session).status==='active' && (await db.sessions.where('status').equals('active').toArray()).some(s=>!s.deletedAt&&s.id!==p.id)}
export async function applyRemote(kind:Kind,id:string,version:number,payload:unknown) {
  const remote=decode(kind,payload), key=keyOf(kind,id)
  if(remote.id!==id)throw new Error('ID ответа сервера не совпадает.')
  await db.transaction('rw',tables,async()=>{
    const meta=await db.meta.get(key),local=await get(kind,id)
    if(meta && version<=meta.version)return
    const dirty=local && canonical(local)!==meta?.synced
    if((dirty && canonical(local)!==canonical(remote)) || await activeClash(kind,remote)) {
      await db.meta.put({key,kind,id,version,synced:meta?.synced??'',remote,conflict:true});return
    }
    await put(kind,remote)
    await db.meta.put({key,kind,id,version,synced:canonical(remote)})
  })
}
export async function pendingCount() {
  let count=0
  for(const kind of kinds)for(const doc of await db[kind].toArray()) {
    const meta=await db.meta.get(keyOf(kind,doc.id));if(canonical(doc)!==meta?.synced)count++
  }
  return count
}
async function send(op:SyncOperation,kind:Kind,id:string) {
  try {
    const request:Contract['WriteRequest']={contractVersion:2,operationId:op.operationId,baseVersion:op.baseVersion,generation:op.generation,payload:op.payload}
    const result=await api<Contract['WriteResponse']>(`/${kind}/${id}`,'PUT',request)
    await db.transaction('rw',tables,async()=>{
      // Acknowledges only the immutable sent snapshot, never replaces a newer local draft.
      await db.meta.put({key:op.key,kind,id,version:result.version,synced:canonical(op.payload)})
      await db.operations.delete(op.key)
      if(kind==='sessions') await db.outbox.where('sessionId').equals(id).filter(o=>o.revision<=(op.payload as Session).revision).delete()
    })
  } catch(e) {
    if(e instanceof ApiError && e.status===409 && e.data.error==='conflict') {
      const remote=decode(kind,e.data.payload)
      await db.transaction('rw',db.meta,db.operations,async()=>{
        const meta=await db.meta.get(op.key)
        await db.meta.put({key:op.key,kind,id,version:Number(e.data.version),synced:meta?.synced??'',remote,conflict:true})
        await db.operations.delete(op.key)
      })
    } else throw e
  }
}
export async function syncOnce() {
  return navigator.locks.request('traininglog-sync',async()=>{
    if(!await authState())throw new ApiError(401,{})
    const boot=await api<Contract['Bootstrap']>('/bootstrap'),generation=String(boot.generation)
    if(boot.contractVersion!==2)throw new Error('Сервер обновляется. Данные сохранены локально, повторите синхронизацию позже.')
    const old=await db.syncState.get('generation')
    if(old?.value!==generation)await db.transaction('rw',tables,async()=>{
      // A restored database has a new generation. Keep all local data for reconciliation.
      for(const m of await db.meta.toArray())if(m.conflict)await db.conflictArchive.add({id:uid(),key:m.key,local:await get(m.kind,m.id),remote:m.remote});
      await db.meta.clear();await db.operations.clear();await db.syncState.put({key:'cursor',value:'0'});await db.syncState.put({key:'generation',value:generation})
    })
    // Retry already-attempted operations before fetching changes (lost response case).
    for(const op of await db.operations.toArray()) {
      const [kind,id]=op.key.split(':') as [Kind,string]
      if(!(await db.meta.get(op.key))?.conflict)await send(op,kind,id)
    }
    let more=true
    while(more) {
      const cursor=(await db.syncState.get('cursor'))?.value??'0'
      const page=await api<Contract['Changes']>(`/changes?after=${cursor}&generation=${encodeURIComponent(generation)}`)
      for(const row of page.changes) {
        if(!kinds.includes(row.kind))throw new Error('Неизвестный тип данных сервера.')
        await applyRemote(row.kind,row.id,row.version,row.payload)
      }
      await db.syncState.put({key:'cursor',value:String(page.cursor)});more=page.hasMore===true
    }
    for(const kind of kinds)for(const doc of await db[kind].toArray()) {
      const key=keyOf(kind,doc.id),meta=await db.meta.get(key)
      if(meta?.conflict || canonical(doc)===meta?.synced)continue
      const op:SyncOperation={key,operationId:uid(),baseVersion:meta?.version??0,generation,payload:structuredClone(doc)}
      await db.operations.put(op);await send(op,kind,doc.id)
    }
    return pendingCount()
  })
}
export async function resolveConflict(meta:SyncMeta,choice:'local'|'remote') {
  await navigator.locks.request('traininglog-sync',async()=>db.transaction('rw',tables,async()=>{
    const current=await db.meta.get(meta.key)
    if(!current?.conflict || !current.remote || current.version!==meta.version)throw new Error('Конфликт изменился. Проверьте версии ещё раз.')
    const local=await get(meta.kind,meta.id)
    if(choice==='remote' && await activeClash(meta.kind,current.remote))throw new Error('Сначала завершите или отмените текущую активную тренировку.')
    if(choice==='local' && !local)throw new Error('На устройстве нет этой записи. Завершите текущую тренировку и выберите серверную версию.')
    await db.conflictArchive.add({id:uid(),key:meta.key,local,remote:current.remote})
    if(choice==='remote')await put(meta.kind,current.remote)
    await db.operations.delete(meta.key)
    await db.meta.put({...current,synced:canonical(current.remote),remote:undefined,conflict:false})
  }))
}
export function saveFile(data:unknown,name:string) {
  const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'})),a=document.createElement('a')
  a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),10000)
}
