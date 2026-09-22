import { expect, it } from 'vitest'
import { emptySet, uid, type Exercise, type Session, type SetRecord } from './domain'
import { musclesFor } from './muscles'
import { muscleVolume, weeklyMuscleVolume, weekStart } from './muscleVolume'

function exercise(name:string,sets:number,extra:Partial<Exercise>={}) {
 const id=uid()
 return {id,variantId:id,equipmentId:id,name,equipment:'TEST ONLY',mode:'PerDumbbell' as const,sets,target:'8–12',rest:90,...extra,
  records:Array.from({length:sets},():SetRecord=>({...emptySet(),status:'completed',loadGrams:20000,count:10}))}
}
function session(date:string,exercises:ReturnType<typeof exercise>[],status:Session['status']='completed'):Session {
 return {id:uid(),programId:uid(),programVersion:1,dayId:uid(),name:'День',status,startedAt:date+'T10:00:00.000Z',completedAt:date+'T11:00:00.000Z',
  localDate:date,timezone:'UTC',revision:1,restEndsAt:null,exercises}
}

it('finds muscles by catalogue name, by its Russian title and by a truncated one',()=>{
 expect(musclesFor({name:'Flat Pronated DB Bench Press'})).toEqual({primary:'chest',secondary:['triceps','shoulders']})
 expect(musclesFor({name:'Жим гантелей лёжа'})?.primary).toBe('chest')
 expect(musclesFor({name:'Lat Pulldown Lean Away Medium …'})?.primary).toBe('back')
 expect(musclesFor({name:'Подъёмы гантелей через стороны'})).toEqual({primary:'shoulders',secondary:[]})
 expect(musclesFor({name:'Моё упражнение'})).toBeNull()
})

it('lets a manual choice win over the catalogue',()=>{
 expect(musclesFor({name:'Flat Pronated DB Bench Press',muscle:'back'})).toEqual({primary:'back',secondary:[]})
})

it('counts a whole set for the main muscle and a half for the helpers',()=>{
 const {sets,unknown}=muscleVolume([session('2026-09-15',[exercise('Flat Pronated DB Bench Press',4)])],'2026-09-14','2026-09-20')
 expect(sets.get('chest')).toBe(4)
 expect(sets.get('triceps')).toBe(2)
 expect(sets.get('shoulders')).toBe(2)
 expect(unknown).toBe(0)
})

it('counts both sides of a one-sided exercise as a single set',()=>{
 const {sets}=muscleVolume([session('2026-09-15',[exercise('Подъёмы гантелей через стороны',6,{unilateral:true})])],'2026-09-14','2026-09-20')
 expect(sets.get('shoulders')).toBe(3)
})

it('skips warm-ups, skipped sets, unfinished and deleted sessions, and other weeks',()=>{
 const withWarmup=exercise('Pec Deck',3)
 withWarmup.records[0].kind='warmup'
 withWarmup.records[1].status='skipped'
 const cancelled=session('2026-09-15',[exercise('Pec Deck',3)],'cancelled')
 const removed=session('2026-09-15',[exercise('Pec Deck',3)])
 removed.deletedAt=new Date().toISOString()
 const other=session('2026-09-07',[exercise('Pec Deck',3)])
 const {sets}=muscleVolume([session('2026-09-15',[withWarmup]),cancelled,removed,other],'2026-09-14','2026-09-20')
 expect(sets.get('chest')).toBe(1)
})

it('keeps unknown exercises in a separate bucket',()=>{
 const {sets,unknown}=muscleVolume([session('2026-09-15',[exercise('Моё упражнение',3)])],'2026-09-14','2026-09-20')
 expect(unknown).toBe(3)
 expect(sets.size).toBe(0)
})

it('splits the current week from the previous one',()=>{
 const today=new Date('2026-09-17T12:00:00')
 expect(weekStart(today).toLocaleDateString('sv-SE')).toBe('2026-09-14')
 const {current,previous}=weeklyMuscleVolume([
  session('2026-09-15',[exercise('Pec Deck',3)]),
  session('2026-09-10',[exercise('Pec Deck',5)]),
  session('2026-09-06',[exercise('Pec Deck',9)]),
 ],today)
 expect(current.sets.get('chest')).toBe(3)
 expect(previous.sets.get('chest')).toBe(5)
})
