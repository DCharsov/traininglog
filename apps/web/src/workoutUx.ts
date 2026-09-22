import { formatWeight, snapWeight, type Session, type SetRecord } from './domain'
import { nextSet } from './workoutFlow'

type SessionExercise=Session['exercises'][number]
export type WorkoutSelection={exerciseId:string;setId:string}

export function resolveWorkoutSelection(session:Session,selection:WorkoutSelection|null) {
 const exercise=session.exercises.find(e=>e.id===selection?.exerciseId)
 const record=exercise?.records.find(r=>r.id===selection?.setId)
 if(exercise&&record)return {exercise,record,index:exercise.records.indexOf(record)}
 const next=nextSet(session)
 if(next)return next
 const first=session.exercises.find(e=>e.records.length)
 return first?{exercise:first,record:first.records[0],index:0}:undefined
}

/** Ordinals include skipped drafts so a missing historical set never shifts later matches. */
export function matchingPreviousSet(exercise:SessionExercise,record:SetRecord,previousExercise?:SessionExercise) {
 if(!previousExercise)return undefined
 const matches=(candidate:SetRecord)=>candidate.kind===record.kind&&(!exercise.unilateral||candidate.side===record.side)
 const ordinal=exercise.records.filter(matches).findIndex(r=>r.id===record.id)
 const previous=previousExercise.records.filter(matches)[ordinal]
 return previous?.status==='completed'?previous:undefined
}

export function precedingCompletedSet(exercise:SessionExercise,record:SetRecord) {
 return exercise.records.slice(0,exercise.records.findIndex(r=>r.id===record.id)).filter(r=>r.status==='completed'&&r.kind===record.kind&&(!exercise.unilateral||r.side===record.side)).at(-1)
}

export function copiedSetValues(record:SetRecord,exercise:SessionExercise|Pick<SessionExercise,'mode'|'tracking'|'availableGrams'>) {
 const grams=record.loadGrams==null?null:snapWeight(exercise,record.loadGrams)
 return {
  weight:exercise.mode==='BodyweightOnly'||grams==null?'':formatWeight(grams),
  reps:exercise.tracking==='duration'||record.count==null?'':String(record.count),
  duration:exercise.tracking==='duration'&&record.durationSeconds!=null?String(record.durationSeconds):'',
 }
}

export function keypadValue(value:string,key:string,decimal:boolean,replace:boolean) {
 if(key==='clear')return ''
 if(key==='erase')return replace?'':value.slice(0,-1)
 const current=replace?'':value
 if(key===',')return !decimal||/[.,]/.test(current)?current:(current||'0')+','
 return current.replace(/\D/g,'').length>=7?current:current+key
}
