import { describe, expect, it } from 'vitest'
import { broSplit } from './broSplit'
import { backupSchema, makeSession, confirmSet } from './domain'
describe('screenshot program', () => {
  it('preserves five deduplicated workouts and the source set totals', () => {
    expect(broSplit.days.map(d=>d.exercises.reduce((n,e)=>n+e.sets,0))).toEqual([16,16,26,23,15])
    expect(broSplit.days.flatMap(d=>d.exercises)).toHaveLength(28)
    expect(backupSchema.parse({schemaVersion:1,exportedAt:new Date().toISOString(),programs:[broSplit],sessions:[]}).sessions).toEqual([])
  })
  it('does not turn source weights into logged sets and fills the missing rest by load', () => {
    const chest=makeSession(broSplit,broSplit.days[0])
    expect(chest.exercises.every(e=>e.records.every(r=>r.weight==='' && r.status==='draft'))).toBe(true)
    const back=makeSession(broSplit,broSplit.days[1])
    const e=back.exercises[0], r=e.records[0]
    r.weight='20';r.reps='10'
    confirmSet(back,e.id,r.id)
    expect(back.exercises[0].rest).toBe(150)
    expect(back.restEndsAt).toBeGreaterThan(Date.now())
  })
})
