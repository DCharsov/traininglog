import { describe, expect, it } from 'vitest'
import fixture from '../../../tests/contracts/watch/session.json'
import expected from '../../../tests/contracts/watch/expectations.json'
import catalog from '../../watch/WorkoutCore/Sources/WorkoutCore/Resources/rest-catalog.json'
import { confirmSet, parseWeight, sessionSchema } from './domain'
import { autofillWatchSet } from './watchAutofill'
import { setSequence } from './workoutFlow'
import { restOf } from './restDefaults'
import { guides } from './exerciseLibrary'
import { musclesFor } from './muscles'

describe('watch shared contract',()=>{
 it('parses weights, orders supersets and computes fallback rest',()=>{
  for(const [input,grams] of expected.weights)expect(parseWeight(String(input))).toBe(grams)
  for(const input of expected.invalidWeights)expect(()=>parseWeight(input)).toThrow()
  const session=sessionSchema.parse(fixture)
  expect(setSequence(session).map(s=>Number(s.record.id.slice(-12)))).toEqual(expected.sequenceSuffixes)
  expect(session.exercises.map(restOf)).toEqual(expected.rests)
 })
 it('keeps the Swift rest catalog aligned with the web catalog',()=>{
  expect(catalog.aliases).toEqual(Object.fromEntries(guides.flatMap(g=>[[g.english.trim().toLocaleLowerCase('en-US'),g.english],[g.ru.trim().toLocaleLowerCase('en-US'),g.english]])))
  for(const [name,groups] of Object.entries(catalog.muscles))expect(musclesFor({name})).toEqual({primary:groups[0],secondary:groups.slice(1)})
 })
 it('copies only effort values into an untouched draft',()=>{
  const s=sessionSchema.parse(fixture),e=s.exercises[0],[a,b]=e.records
  Object.assign(a,{weight:expected.repeatWeight,reps:expected.repeatReps,rir:'2',note:'do not copy'})
  confirmSet(s,e.id,a.id)
  expect(autofillWatchSet(s,e.id,b.id)).toBe(true)
  expect(b).toMatchObject({weight:expected.repeatWeight,reps:expected.repeatReps,rir:'',note:'',status:'draft',completedAt:null,loadGrams:null,count:null})
  expect(b.id).not.toBe(a.id)
 })
 it('does not cross sides, warmup or manual input',()=>{
  const s=sessionSchema.parse(fixture),e=s.exercises[3],[a,b,c]=e.records
  Object.assign(a,{weight:'12',reps:'8'});confirmSet(s,e.id,a.id)
  expect(autofillWatchSet(s,e.id,b.id)).toBe(false)
  expect(autofillWatchSet(s,e.id,c.id)).toBe(true)
  const k=s.exercises[5];Object.assign(k.records[0],{weight:'20',reps:'10'});confirmSet(s,k.id,k.records[0].id)
  expect(autofillWatchSet(s,k.id,k.records[1].id)).toBe(false)
  b.reps='5';expect(autofillWatchSet(s,e.id,b.id)).toBe(false)
 })
 it('repeats duration without fake bodyweight',()=>{
  const s=sessionSchema.parse(fixture),e=s.exercises[4],[a,b]=e.records
  a.duration='45';confirmSet(s,e.id,a.id)
  expect(autofillWatchSet(s,e.id,b.id)).toBe(true)
  expect(b.duration).toBe('45');expect(b.weight).toBe('');expect(b.durationSeconds==null).toBe(true)
 })
})
