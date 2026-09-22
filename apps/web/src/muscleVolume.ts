import { dateKey } from './calendarMonth'
import { musclesFor } from './muscles'
import type { MuscleId, Session } from './domain'

/** Понедельник недели, в которую попадает дата. */
export function weekStart(date:Date) {
 const start=new Date(date.getFullYear(),date.getMonth(),date.getDate())
 start.setDate(start.getDate()-((start.getDay()+6)%7))
 return start
}
export const shiftDays=(date:Date,days:number)=>{const next=new Date(date);next.setDate(next.getDate()+days);return next}

export type Volume={sets:Map<MuscleId,number>;unknown:number}
/**
 * Рабочие подходы по группам мышц за период.
 * Основная мышца получает подход целиком, вспомогательные — половину;
 * односторонние упражнения считают левую и правую за один подход.
 */
export function muscleVolume(sessions:Session[],from:string,to:string):Volume {
 const sets=new Map<MuscleId,number>()
 let unknown=0
 const add=(id:MuscleId,amount:number)=>sets.set(id,(sets.get(id)??0)+amount)
 for(const session of sessions){
  if(session.status!=='completed'||session.deletedAt||session.localDate<from||session.localDate>to)continue
  for(const exercise of session.exercises){
   const done=exercise.records.filter(record=>record.kind==='working'&&record.status==='completed').length
   if(!done)continue
   const counted=done*(exercise.unilateral?0.5:1)
   const muscles=musclesFor(exercise)
   if(!muscles){unknown+=counted;continue}
   add(muscles.primary,counted)
   for(const id of muscles.secondary)add(id,counted/2)
  }
 }
 return {sets,unknown}
}
/** Объём текущей недели и предыдущей для сравнения. */
export function weeklyMuscleVolume(sessions:Session[],today=new Date()) {
 const start=weekStart(today),previous=shiftDays(start,-7)
 return {
  current:muscleVolume(sessions,dateKey(start),dateKey(today)),
  previous:muscleVolume(sessions,dateKey(previous),dateKey(shiftDays(start,-1))),
 }
}
