import { contextKey } from './progress'
import { epleyMax } from './progression'
import type { Session, SetRecord } from './domain'

type SessionExercise=Session['exercises'][number]
/** Вес — тяжелее, чем когда-либо; максимум — выше расчётного; повторения и секунды — для работы без веса. */
export type RecordKind='weight'|'max'|'reps'|'duration'
type Best={load?:number;max?:number;count?:number;duration?:number}

const bestKey=(exercise:SessionExercise,record:SetRecord)=>contextKey(exercise)+(exercise.unilateral?`|${record.side??'both'}`:'')
const working=(record:SetRecord)=>record.kind==='working'&&record.status==='completed'

/** Побит ли рекорд этим подходом. Сравнение только с тем, что было раньше. */
function beats(exercise:SessionExercise,record:SetRecord,best:Best):RecordKind|null {
 const assisted=exercise.mode==='AssistedBodyweight'
 if(exercise.tracking==='duration')return record.durationSeconds!=null&&best.duration!==undefined&&record.durationSeconds>best.duration?'duration':null
 if(exercise.mode==='BodyweightOnly')return record.count!=null&&best.count!==undefined&&record.count>best.count?'reps':null
 if(record.loadGrams==null||record.count==null)return null
 if(best.load!==undefined&&(assisted?record.loadGrams<best.load:record.loadGrams>best.load))return 'weight'
 if(assisted)return null
 return best.max!==undefined&&epleyMax(record.loadGrams,record.count)>best.max?'max':null
}

function absorb(exercise:SessionExercise,record:SetRecord,best:Best):Best {
 const assisted=exercise.mode==='AssistedBodyweight'
 return {
  load:record.loadGrams==null?best.load:best.load===undefined?record.loadGrams:assisted?Math.min(best.load,record.loadGrams):Math.max(best.load,record.loadGrams),
  max:record.loadGrams==null||record.count==null?best.max:Math.max(best.max??0,epleyMax(record.loadGrams,record.count)),
  count:record.count==null?best.count:Math.max(best.count??0,record.count),
  duration:record.durationSeconds==null?best.duration:Math.max(best.duration??0,record.durationSeconds),
 }
}

/** Рекорды этого занятия: подход отмечается, только если до него уже была история упражнения. */
export function sessionRecords(sessions:Session[],session:Session):Map<string,RecordKind> {
 const bests=new Map<string,Best>()
 const earlier=sessions.filter(s=>s.status==='completed'&&!s.deletedAt&&s.id!==session.id&&s.startedAt<session.startedAt).sort((a,b)=>a.startedAt.localeCompare(b.startedAt))
 for(const past of earlier)for(const exercise of past.exercises)for(const record of exercise.records){
  if(!working(record))continue
  const key=bestKey(exercise,record)
  bests.set(key,absorb(exercise,record,bests.get(key)??{}))
 }
 const found=new Map<string,RecordKind>()
 for(const exercise of session.exercises)for(const record of exercise.records){
  if(!working(record))continue
  const key=bestKey(exercise,record),best=bests.get(key)
  if(best){const kind=beats(exercise,record,best);if(kind)found.set(record.id,kind)}
  bests.set(key,absorb(exercise,record,best??{}))
 }
 return found
}
