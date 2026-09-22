import 'fake-indexeddb/auto'
import { beforeEach, expect, it } from 'vitest'
import { hypertrophyAB as p, importHypertrophyAB, offerWeeklyOptional } from './hypertrophyAB'
import { db, start, change, exportData } from './data'
import { backupSchema, confirmSet, makeSession, previous } from './domain'
import { nextDay } from './workoutFlow'
import { broSplit } from './broSplit'
import { results } from './progress'
beforeEach(async()=>{for(const table of db.tables)await table.clear()})
it('imports once without overwriting edits, other programs or history',async()=>{
 await db.programs.add(broSplit)
 await Promise.all([importHypertrophyAB(),importHypertrophyAB()])
 const edited=structuredClone(p);edited.name='Моя правка';edited.days[0].exercises[0].sets=1;edited.archivedAt=new Date().toISOString()
 await db.programs.put(edited);await importHypertrophyAB()
 expect(await db.programs.count()).toBe(2);expect(await db.programs.get(p.id)).toEqual(edited)
 expect(await db.programs.get(broSplit.id)).toEqual(broSplit)
 const backup=backupSchema.parse(await exportData());expect(backup.sessions).toEqual([]);expect(results(backup.sessions)).toEqual([])
})
it('has introductory volumes, distinct variants and blank drafts; core includes both sides',()=>{
 expect(p.days.map(d=>makeSession(p,d).exercises.length)).toEqual([7,8])
 expect(p.days.map(d=>makeSession(p,d).exercises.reduce((n,e)=>n+e.records.length,0))).toEqual([14,16])
 for(const d of p.days){const s=makeSession(p,d,true);expect(s.exercises.at(-1)?.records).toHaveLength(2);expect(s.exercises.at(-1)?.target).toContain('на каждую сторону');expect(s.exercises.at(-1)?.rest).toBe(60);expect(s.exercises.flatMap(e=>e.records).every(r=>r.status==='draft'&&r.loadGrams===null&&r.weight==='')).toBe(true)}
 expect(p.days[0].exercises[3].variantId).toBe(p.days[1].exercises[3].variantId)
 expect(p.days[0].exercises[1].variantId).not.toBe(p.days[1].exercises[1].variantId)
 expect(p.days[0].exercises[2].stepGrams).toBeUndefined();expect(p.days[0].exercises[2].availableGrams).toBeUndefined()
 expect(p.days.map(d=>d.exercises.filter(e=>!e.optionalWeekly).reduce((n,e,i)=>n+(i<3?3:e.sets),0))).toEqual([17,19])
})
it('records actual per-dumbbell grams through the journal and keeps snapshots',async()=>{
 await importHypertrophyAB();const s=await start(p,p.days[0]);const e=s.exercises[1]
 await change(s.id,-1,current=>{const r=current.exercises[1].records[0];r.weight='12';r.reps='10';confirmSet(current,e.id,r.id);current.status='completed';current.completedAt=new Date().toISOString()})
 const saved=(await db.sessions.get(s.id))!;expect(saved.exercises[1].records[0].loadGrams).toBe(12000)
 expect(results([saved])).toHaveLength(1)
 const current=makeSession(p,p.days[0]);current.startedAt=new Date(Date.now()+1000).toISOString();expect(previous([saved],current,e)?.session.id).toBe(s.id)
 await importHypertrophyAB();expect(await db.sessions.get(s.id)).toEqual(saved)
 const edited=structuredClone(p);edited.days[0].exercises[1].sets=3;await db.programs.put(edited);expect((await db.sessions.get(s.id))?.exercises[1].sets).toBe(2)
})
it('requires leg press setup and allows bodyweight without external load',()=>{
 const s=makeSession(p,p.days[1],true),e=s.exercises[0],r=e.records[0];r.reps='12';r.weight='0'
 expect(()=>confirmSet(s,e.id,r.id)).toThrow('профиль');expect(r.status).toBe('draft')
 e.mode='MachinePlatesOnly';r.weight='20';confirmSet(s,e.id,r.id);expect(r.loadGrams).toBe(20000)
 const core=s.exercises.at(-1)!;core.records[0].reps='6';confirmSet(s,core.id,core.records[0].id);expect(core.records[0].loadGrams).toBeNull()
})
it('continues AB across Monday and offers optional core only on first day of each type',()=>{
 const s=makeSession(p,p.days[0]);s.status='completed';s.localDate='2026-09-14'
 expect(offerWeeklyOptional(p.id,p.days[0],[s],new Date(2026,8,16))).toBe(false)
 expect(offerWeeklyOptional(p.id,p.days[1],[s],new Date(2026,8,16))).toBe(true)
 expect(offerWeeklyOptional(p.id,p.days[0],[s],new Date(2026,8,21))).toBe(true)
 expect(nextDay(p,[s]).day.id).toBe(p.days[1].id)
 s.status='cancelled';expect(offerWeeklyOptional(p.id,p.days[0],[s],new Date(2026,8,16))).toBe(true)
})
