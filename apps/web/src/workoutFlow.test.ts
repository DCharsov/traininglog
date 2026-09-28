import { expect,it } from 'vitest'
import { broSplit } from './broSplit'
import { makeSession,uid } from './domain'
import { nextDay,nextSet,setSequence } from './workoutFlow'
it('skips archived days without changing historical snapshots',()=>{
 const p=structuredClone(broSplit),s=makeSession(p,p.days[0]),snapshot=structuredClone(s)
 p.days[0].archivedAt='2026-09-28T10:00:00Z'
 expect(nextDay(p,[]).day.id).toBe(p.days[1].id)
 expect(()=>makeSession(p,p.days[0])).toThrow()
 expect(s).toEqual(snapshot)
 for(const day of p.days)day.archivedAt='2026-09-28T10:00:00Z'
 expect(()=>nextDay(p,[])).toThrow()
 p.days[0].archivedAt=null
 expect(nextDay(p,[]).day.id).toBe(p.days[0].id)
})
it('suggests next day from completed records only and cycles without using calendar gaps',()=>{
 const p=structuredClone(broSplit),s=makeSession(p,p.days[1]);s.status='completed';s.startedAt='2020-01-01T00:00:00.000Z'
 const cancel=makeSession(p,p.days[4]);cancel.status='cancelled'
 expect(nextDay(p,[s,cancel]).day.id).toBe(p.days[2].id)
 s.dayId=p.days[4].id;expect(nextDay(p,[s]).day.id).toBe(p.days[0].id)
 s.dayId=uid();expect(nextDay(p,[s]).previous).toBeUndefined()
})
it('interleaves matching superset pairs and resumes from persisted statuses',()=>{
 const s=makeSession(broSplit,broSplit.days[3]),seq=setSequence(s)
 expect(seq.slice(0,4).map(p=>[p.exercise.id,p.index])).toEqual([[s.exercises[0].id,0],[s.exercises[1].id,0],[s.exercises[0].id,1],[s.exercises[1].id,1]])
 seq[0].record.status='completed';seq[1].record.status='skipped'
 expect(nextSet(structuredClone(s))?.record.id).toBe(seq[2].record.id)
 s.exercises.forEach(e=>e.records.forEach(r=>r.status='skipped'));expect(nextSet(s)).toBeUndefined()
})
it('does not guess ambiguous or missing supersets and includes unequal set counts once',()=>{
 const s=makeSession(broSplit,broSplit.days[3]);s.exercises[1].records.pop()
 expect(setSequence(s)).toHaveLength(s.exercises.reduce((n,e)=>n+e.records.length,0))
 s.exercises.push({...structuredClone(s.exercises[0]),id:uid()})
 expect(setSequence(s)[0].superset).toBe(false)
 s.exercises[0].sourceNote='A1 · Суперсет с отсутствующим'
 expect(setSequence(s)[0].superset).toBe(false)
})
