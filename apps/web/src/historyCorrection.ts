import { confirmSet, sessionSchema, type Session } from './domain'
import { change } from './data'
import { canonical } from './sync'
export function prepareCorrection(original:Session,edited:Session):Session {
 if(original.status==='active')throw new Error('Для активной тренировки используйте обычную запись подходов.')
 const result=structuredClone(original)
 if(edited.id!==original.id || edited.exercises.length!==original.exercises.length)throw new Error('Структура тренировки изменилась.')
 result.exercises.forEach((e,ei)=>{
  const incoming=edited.exercises[ei]
  if(e.id!==incoming.id || e.records.length!==incoming.records.length)throw new Error('Структура упражнения изменилась.')
  e.records.forEach((r,ri)=>{
   const input=incoming.records[ri],completedAt=r.completedAt
   if(r.id!==input.id)throw new Error('Подход изменился.')
   Object.assign(r,{duration:input.duration,side:input.side,weight:input.weight,reps:input.reps,rir:input.rir,note:input.note,kind:input.kind,status:input.status})
   if(r.status==='completed'){
    r.status='draft';confirmSet(result,e.id,r.id)
    if(completedAt)r.completedAt=completedAt
   }else{r.loadGrams=null;r.count=null;r.durationSeconds=null}
  })
 })
 result.restEndsAt=null
 return sessionSchema.parse(result)
}
export async function saveCorrection(original:Session,edited:Session) {
 const result=prepareCorrection(original,edited)
 await change(original.id,original.revision,current=>{
  if(canonical(current)!==canonical(original))throw new Error('Запись обновилась на другом устройстве. Закройте редактор и проверьте новую версию.')
  Object.assign(current,result)
 })
}
