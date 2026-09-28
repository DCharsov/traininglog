import type { Session } from './domain'

/** Watch contract: fill an untouched draft from an earlier set of the same kind and side. */
export function autofillWatchSet(session: Session, exerciseId: string, setId: string): boolean {
 const exercise=session.exercises.find(e=>e.id===exerciseId)
 if(!exercise)throw new Error('Упражнение не найдено')
 const index=exercise.records.findIndex(r=>r.id===setId),record=exercise.records[index]
 if(!record)throw new Error('Подход не найден')
 if(session.status!=='active'||record.status!=='draft'||record.completedAt!==null)return false
 if([record.weight,record.reps,record.duration,record.rir,record.note].some(value=>!!value))return false
 if([record.loadGrams,record.count,record.durationSeconds].some(value=>value!=null))return false
 const previous=exercise.records.slice(0,index).reverse().find(r=>r.status==='completed'&&r.kind===record.kind&&(r.side??'both')===(record.side??'both'))
 if(!previous)return false
 if(exercise.mode!=='BodyweightOnly')record.weight=previous.weight
 if(exercise.tracking==='duration')record.duration=previous.duration
 else record.reps=previous.reps
 return true
}
