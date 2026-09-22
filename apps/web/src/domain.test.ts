import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it } from 'vitest'
import { confirmSet, makeSession, parseWeight, previous, uid, type Program } from './domain'
import { change, db, exportData, restore, start } from './data'

function fixture(): Program { return { id: uid(), name: 'TEST ONLY', version: 1, days: [{ id: uid(), name: 'Тестовый день', exercises: [{ id: uid(), variantId: uid(), equipmentId: uid(), name: 'Тестовое упражнение', equipment: 'TEST ONLY', mode: 'SmithPlatesOnly', sets: 3, target: '8–12', rest: 90 }] }] } }
beforeEach(async () => { await db.programs.clear(); await db.sessions.clear(); await db.outbox.clear() })
describe('canonical weight', () => {
  it.each(['72,5','72.5'])('%s is 72500 grams', v => expect(parseWeight(v)).toBe(72500))
  it.each(['72,','-1','1e3','','0.0001','2001'])('rejects %s', v => expect(() => parseWeight(v)).toThrow())
  it('preserves zero and exact thousandths', () => { expect(parseWeight('0')).toBe(0); expect(parseWeight('1.001')).toBe(1001) })
})
it('does not count drafts; confirmation is idempotent and edits do not restart rest', () => {
  const p=fixture(); const s=makeSession(p,p.days[0]); const e=s.exercises[0]; const r=e.records[0]
  r.weight='72,5';r.reps='8'; expect(r.status).toBe('draft')
  expect(confirmSet(s,e.id,r.id)).toBe(true); const end=s.restEndsAt
  expect(confirmSet(s,e.id,r.id)).toBe(false); expect(s.restEndsAt).toBe(end)
  r.status='draft';r.weight='70'; confirmSet(s,e.id,r.id); expect(s.restEndsAt).toBe(end); expect(r.loadGrams).toBe(70000)
})
it('snapshots remain independent of program edits', () => {
  const p=fixture();const s=makeSession(p,p.days[0]);p.days[0].exercises[0].name='Changed'
  expect(s.exercises[0].name).toBe('Тестовое упражнение')
})
it('previous results require the same equipment and load mode', () => {
  const p=fixture();const old=makeSession(p,p.days[0]);old.startedAt='2020-01-01T00:00:00.000Z';old.status='completed'
  const r=old.exercises[0].records[0];r.weight='40';r.reps='10';confirmSet(old,old.exercises[0].id,r.id)
  const current=makeSession(p,p.days[0]);expect(previous([old],current,current.exercises[0])?.session.id).toBe(old.id)
  current.exercises[0].equipmentId=uid();expect(previous([old],current,current.exercises[0])).toBeUndefined()
})
it('bodyweight requires repetitions but no external load', () => {
  const p=fixture();p.days[0].exercises[0].mode='BodyweightOnly';const s=makeSession(p,p.days[0]);const e=s.exercises[0];e.records[0].reps='12';confirmSet(s,e.id,e.records[0].id);expect(e.records[0].loadGrams).toBeNull()
})
it('persists three sets and outbox atomically across a database reopen', async () => {
  const p=fixture();const s=await start(p,p.days[0])
  for(let i=0;i<3;i++) await change(s.id,-1,s=>{const e=s.exercises[0];e.records[i].weight='72,5';e.records[i].reps='8';confirmSet(s,e.id,e.records[i].id)})
  db.close(); await db.open()
  expect((await db.sessions.get(s.id))!.exercises[0].records.map(r=>r.loadGrams)).toEqual([72500,72500,72500]);expect(await db.outbox.count()).toBe(4)
})
it('rolls back session write when outbox write fails', async () => {
  const p=fixture();const s=await start(p,p.days[0]);const hook=()=>{throw new Error('disk full')};db.outbox.hook('creating',hook)
  try { await expect(change(s.id,1,s=>{s.name='lost'})).rejects.toThrow('disk full');expect((await db.sessions.get(s.id))!.name).toBe(s.name) }
  finally { db.outbox.hook('creating').unsubscribe(hook) }
})
it('allows only one active session and rejects stale revisions', async () => {
  const p=fixture();const s=await start(p,p.days[0]);await expect(start(p,p.days[0])).rejects.toThrow();await change(s.id,1,s=>{s.name='new'});await expect(change(s.id,1,s=>{s.name='stale'})).rejects.toThrow()
})
it('restores complete export without replaying old outbox operations', async () => {
  const p=fixture();await db.programs.add(p);await start(p,p.days[0]);const backup=await exportData();await restore(backup)
  const restored=await exportData();expect(restored.programs).toEqual(backup.programs);expect(restored.sessions).toEqual(backup.sessions);expect(await db.outbox.count()).toBe(0)
})
it('rejects invalid restore before changing existing data', async () => {
  const p=fixture();await db.programs.add(p);await expect(restore({schemaVersion:999})).rejects.toThrow();expect(await db.programs.count()).toBe(1)
})
