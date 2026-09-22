import { expect, it } from 'vitest'
import { makeSession, uid, type Exercise, type Program, type Session } from './domain'
import { epleyReps, exerciseHistory, nextWeight, suggestSet, targetRange } from './progression'

const today=new Date('2026-09-17T12:00:00Z')
function program(target:string,extra:Partial<Exercise>={},sets=3):Program {
 const id=uid()
 return {id:uid(),name:'TEST ONLY',version:1,days:[{id:uid(),name:'Тестовый день',
  exercises:[{id,variantId:id,equipmentId:id,name:'Тестовое упражнение',equipment:'TEST ONLY',mode:'PerDumbbell',sets,target,rest:90,...extra}]}]}
}
/** Прошедшее занятие с заданными результатами по подходам. */
function past(p:Program,date:string,results:{grams:number;value:number}[]):Session {
 const session=makeSession(p,p.days[0]),exercise=session.exercises[0]
 session.status='completed';session.localDate=date;session.startedAt=new Date(date+'T10:00:00Z').toISOString();session.completedAt=session.startedAt
 exercise.records.forEach((record,index)=>{
  const result=results[Math.min(index,results.length-1)]
  record.status='completed';record.completedAt=session.startedAt
  record.loadGrams=exercise.mode==='BodyweightOnly'?null:result.grams
  record.weight=String(result.grams/1000);record.rir=''
  if(exercise.tracking==='duration'){record.durationSeconds=result.value;record.duration=String(result.value)}
  else{record.count=result.value;record.reps=String(result.value)}
 })
 return session
}
function suggest(p:Program,sessions:Session[],index=0) {
 const current=makeSession(p,p.days[0])
 current.startedAt=today.toISOString()
 const exercise=current.exercises[0]
 return suggestSet(exercise,exercise.records[index],exerciseHistory(sessions,current,exercise),today)
}
const set=(grams:number,value:number)=>[{grams,value}]
const dumbbells={availableGrams:[10000,12500,15000,20000,25000,30000,32500,35000]}
const barbell={stepGrams:2500}

it('reads a per-set scheme, a range and an unlimited target',()=>{
 expect(targetRange('10 / 8 / 6 / 12',1)).toEqual([8,11])
 expect(targetRange('10 / 8 / 6 / 12',3)).toEqual([12,15])
 expect(targetRange('10 / 8 / 6 / 12',9)).toEqual([12,15])
 expect(targetRange('8–12',0)).toEqual([8,12])
 expect(targetRange('6–8 на каждую сторону',0)).toEqual([6,8])
 expect(targetRange('∞ / ∞ / ∞',0)).toBeNull()
 expect(targetRange('20',0)).toEqual([20,25])
})

it('adds one repetition while the set is below its target',()=>{
 const p=program('8–12',dumbbells)
 expect(suggest(p,[past(p,'2026-09-10',set(30000,10))])).toEqual({weight:'30',reps:'11',duration:'',note:undefined})
})

it('holds the weight the first time the top is reached and raises it after a second confirmation',()=>{
 const p=program('8–12',barbell)
 const first=past(p,'2026-09-03',set(100000,12))
 expect(suggest(p,[first])).toMatchObject({weight:'100',reps:'12'})
 const second=past(p,'2026-09-10',set(100000,12))
 expect(suggest(p,[second,first])).toEqual({weight:'102,5',reps:'11',duration:'',note:undefined})
 expect(epleyReps(100000,12,102500)).toBe(11)
})

it('keeps growing repetitions when the next dumbbell is too big a jump, then takes it with realistic reps',()=>{
 const p=program('15',dumbbells)
 const confirmed=[past(p,'2026-09-10',set(10000,20)),past(p,'2026-09-03',set(10000,20))]
 expect(suggest(p,confirmed)).toMatchObject({weight:'10',reps:'21'})
 const ceiling=[past(p,'2026-09-10',set(10000,25)),past(p,'2026-09-03',set(10000,24))]
 expect(suggest(p,ceiling)).toMatchObject({weight:'12,5',reps:'14'})
})

it('does not raise the weight when a set of the confirming session was skipped',()=>{
 const p=program('8–12',barbell)
 const last=past(p,'2026-09-10',set(100000,12))
 last.exercises[0].records[2].status='skipped';last.exercises[0].records[2].count=null
 expect(suggest(p,[last,past(p,'2026-09-03',set(100000,12))])).toMatchObject({weight:'100',reps:'12'})
})

it('holds after one session without progress and steps down after two',()=>{
 const p=program('8–12',dumbbells)
 const stalled=[past(p,'2026-09-10',set(30000,10)),past(p,'2026-09-03',set(30000,10))]
 expect(suggest(p,stalled)).toMatchObject({weight:'30',reps:'10',note:'Тот же вес — в прошлый раз без прогресса'})
 expect(suggest(p,[...stalled,past(p,'2026-08-27',set(30000,10))])).toMatchObject({weight:'25',reps:'12',note:'Шаг вниз — прогресса не было'})
})

it('repeats the last result after a long break',()=>{
 const p=program('8–12',dumbbells)
 expect(suggest(p,[past(p,'2026-07-01',set(30000,12))])).toMatchObject({weight:'30',reps:'12',note:'После перерыва — как в прошлый раз'})
})

it('grows only repetitions for bodyweight work and only the target for an unknown step',()=>{
 const body=program('∞ / ∞ / ∞',{mode:'BodyweightOnly'})
 expect(suggest(body,[past(body,'2026-09-10',set(0,22))])).toEqual({weight:'',reps:'23',duration:'',note:undefined})
 const unknown=program('8–12')
 expect(suggest(unknown,[past(unknown,'2026-09-10',set(40000,12)),past(unknown,'2026-09-03',set(40000,12))])).toMatchObject({weight:'40',reps:'13'})
})

it('reduces machine assistance instead of adding weight',()=>{
 const p=program('8–12',{mode:'AssistedBodyweight',availableGrams:[20000,25000,30000]})
 const history=[past(p,'2026-09-10',set(30000,12)),past(p,'2026-09-03',set(30000,12))]
 expect(suggest(p,history)).toMatchObject({weight:'25',reps:'8'})
 expect(nextWeight({mode:'AssistedBodyweight',availableGrams:[20000,25000,30000]},30000,1)).toBe(25000)
})

it('counts seconds for duration work',()=>{
 const p=program('30–45',{tracking:'duration',mode:'BodyweightOnly'})
 expect(suggest(p,[past(p,'2026-09-10',set(0,35))])).toEqual({weight:'',reps:'',duration:'40',note:undefined})
})

it('repeats a warm-up set without progression',()=>{
 const p=program('8–12',dumbbells)
 const current=makeSession(p,p.days[0]);current.startedAt=today.toISOString()
 const exercise=current.exercises[0];exercise.records[0].kind='warmup'
 const history=past(p,'2026-09-10',set(30000,12));history.exercises[0].records[0].kind='warmup'
 expect(suggestSet(exercise,exercise.records[0],exerciseHistory([history],current,exercise),today)).toEqual({weight:'30',reps:'12',duration:'',note:undefined})
})

it('repeats the last result when the exercise has no repetition goal',()=>{
 const p=program('',dumbbells)
 expect(suggest(p,[past(p,'2026-09-10',set(30000,8))])).toEqual({weight:'30',reps:'8',duration:'',note:undefined})
})
