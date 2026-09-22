import { expect,it } from 'vitest'
import { broSplit } from './broSplit'
import { emptySet,makeSession,snapWeight,type SetRecord } from './domain'
import { copiedSetValues,keypadValue,matchingPreviousSet,precedingCompletedSet,resolveWorkoutSelection } from './workoutUx'

const record=(fields:Partial<SetRecord>={})=>({...emptySet(),...fields})

it('matches historical sets by kind and side without shifting skipped positions',()=>{
 const exercise=makeSession(broSplit,broSplit.days[0]).exercises[0]
 exercise.unilateral=true
 exercise.records=[record({kind:'warmup',side:'left'}),record({side:'left'}),record({side:'right'}),record({side:'left'}),record({side:'right'})]
 const previous=structuredClone(exercise)
 previous.records=[record({kind:'warmup',side:'left',status:'completed',loadGrams:10000}),record({side:'left',status:'skipped'}),record({side:'right',status:'completed',loadGrams:20000}),record({side:'left',status:'completed',loadGrams:30000}),record({side:'right',status:'completed',loadGrams:40000})]
 expect(matchingPreviousSet(exercise,exercise.records[0],previous)?.loadGrams).toBe(10000)
 expect(matchingPreviousSet(exercise,exercise.records[1],previous)).toBeUndefined()
 expect(matchingPreviousSet(exercise,exercise.records[2],previous)?.loadGrams).toBe(20000)
 expect(matchingPreviousSet(exercise,exercise.records[3],previous)?.loadGrams).toBe(30000)
 expect(matchingPreviousSet(exercise,exercise.records[4],previous)?.loadGrams).toBe(40000)
})

it('retains selection by IDs after exercise reorder and falls back after removal',()=>{
 const session=makeSession(broSplit,broSplit.days[0]),exercise=session.exercises[1],set=exercise.records[1]
 const selection={exerciseId:exercise.id,setId:set.id}
 session.exercises.reverse()
 expect(resolveWorkoutSelection(session,selection)?.record.id).toBe(set.id)
 session.exercises=session.exercises.filter(e=>e.id!==exercise.id)
 expect(resolveWorkoutSelection(session,selection)?.record.id).toBe(session.exercises[0].records[0].id)
})

it('repeats only a preceding completed set of matching kind and side',()=>{
 const exercise=makeSession(broSplit,broSplit.days[0]).exercises[0]
 exercise.unilateral=true
 const left=record({side:'left',status:'completed',loadGrams:42500,count:8})
 exercise.records=[left,record({side:'right',status:'completed',loadGrams:45000,count:10}),record({side:'left',kind:'warmup',status:'completed'}),record({side:'left'})]
 expect(precedingCompletedSet(exercise,exercise.records[3])).toBe(left)
 expect(copiedSetValues(left,exercise)).toEqual({weight:'42,5',reps:'8',duration:''})
 expect(exercise.records[3].status).toBe('draft')
 expect(precedingCompletedSet(exercise,exercise.records[0])).toBeUndefined()
})

it('numeric panel replaces selected input, clears and accepts one decimal separator',()=>{
 expect(keypadValue('72,5','8',true,true)).toBe('8')
 expect(keypadValue('8','0',true,false)).toBe('80')
 expect(keypadValue('80',',',true,false)).toBe('80,')
 expect(keypadValue('80.5',',',true,false)).toBe('80.5')
 expect(keypadValue('72,5','clear',true,false)).toBe('')
 expect(keypadValue('72,5','erase',true,true)).toBe('')
 expect(keypadValue('72,5','erase',true,false)).toBe('72,')
 expect(keypadValue('8',',',false,false)).toBe('8')
})

it('rounds a copied weight to the nearest available one and keeps it when equipment is free-form',()=>{
 const exercise=makeSession(broSplit,broSplit.days[0]).exercises[0]
 exercise.availableGrams=[20000,15000,12500,10000]
 expect(snapWeight(exercise,13000)).toBe(12500)
 expect(snapWeight(exercise,11250)).toBe(10000)
 expect(snapWeight(exercise,99000)).toBe(20000)
 expect(copiedSetValues(record({status:'completed',loadGrams:13000,count:8}),exercise)).toEqual({weight:'12,5',reps:'8',duration:''})
 expect(snapWeight({},13000)).toBe(13000)
 expect(copiedSetValues(record({status:'completed',loadGrams:13000,count:8}),{mode:'BarbellTotal',tracking:'reps'})).toEqual({weight:'13',reps:'8',duration:''})
})
