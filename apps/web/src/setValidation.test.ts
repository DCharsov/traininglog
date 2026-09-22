import { describe, expect, it } from 'vitest'
import { broSplit } from './broSplit'
import { makeSession } from './domain'
import { validateSet } from './setValidation'
describe('confirmation errors keep inputs unchanged and identify the field',()=>{
 it('distinguishes missing weight, repetitions and RIR',()=>{
  const session=makeSession(broSplit,broSplit.days[0]),exercise=session.exercises[0],set=exercise.records[0]
  expect(validateSet(session,exercise.id,set.id)).toMatchObject({ok:false,field:'weight'})
  set.weight='72,5';expect(validateSet(session,exercise.id,set.id)).toMatchObject({ok:false,field:'reps'})
  set.reps='8';set.rir='11';expect(validateSet(session,exercise.id,set.id)).toMatchObject({ok:false,field:'rir'})
  set.rir='2';const before=structuredClone(session);expect(validateSet(session,exercise.id,set.id)).toEqual({ok:true});expect(session).toEqual(before)
 })
 it('handles seconds, sides, equipment, and bodyweight independently',()=>{
  const session=makeSession(broSplit,broSplit.days[0]),exercise=session.exercises[0],set=exercise.records[0]
  exercise.requiresEquipment=true;exercise.mode='Unspecified'
  expect(validateSet(session,exercise.id,set.id)).toMatchObject({ok:false,field:'equipment'})
  exercise.mode='BodyweightOnly';exercise.tracking='duration';exercise.unilateral=true
  expect(validateSet(session,exercise.id,set.id)).toMatchObject({ok:false,field:'duration'})
  set.duration='45';expect(validateSet(session,exercise.id,set.id)).toMatchObject({ok:false,field:'side'})
  set.side='left';expect(validateSet(session,exercise.id,set.id)).toEqual({ok:true})
 })
})
