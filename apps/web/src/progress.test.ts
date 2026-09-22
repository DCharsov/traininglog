import 'fake-indexeddb/auto'
import { beforeEach, expect, it } from 'vitest'
import { confirmSet, makeSession, uid, type Program } from './domain'
import { contextKey, results, points, weeklySets, csvCell, sessionsCsv } from './progress'
import { prepareCorrection, saveCorrection } from './historyCorrection'
import { db } from './data'
function fixture() {
 const p:Program={id:uid(),name:'TEST',version:1,days:[{id:uid(),name:'TEST',exercises:[{id:uid(),variantId:uid(),equipmentId:uid(),name:'Press',equipment:'TEST',mode:'MachineStack',sets:3,target:'10',rest:90}]}]}
 const s=makeSession(p,p.days[0]);s.startedAt='2026-09-13T20:00:00.000Z';s.localDate='2026-09-14';s.status='completed';s.completedAt='2026-09-13T21:00:00.000Z';s.restEndsAt=null
 s.exercises[0].records.forEach((r,i)=>{r.weight=String(40+i*10);r.reps=String(12-i*3);confirmSet(s,s.exercises[0].id,r.id)});s.restEndsAt=null
 return s
}
beforeEach(async()=>{await db.sessions.clear();await db.outbox.clear()})
it('excludes cancelled, draft and warmup; keeps exact context and local date',()=>{
 const s=fixture(),cancelled=structuredClone(s);cancelled.id=uid();cancelled.status='cancelled'
 s.exercises[0].records[1].kind='warmup';s.exercises[0].records[2].status='draft'
 const other=fixture();expect(results([s,cancelled,other],{context:contextKey(s.exercises[0]),from:'2026-09-14',to:'2026-09-14'})).toHaveLength(1)
 other.exercises[0].variantId=s.exercises[0].variantId;other.exercises[0].equipmentId=s.exercises[0].equipmentId;other.exercises[0].mode='PerDumbbell'
 expect(results([s,other],{context:contextKey(s.exercises[0])})).toHaveLength(1)
 expect(weeklySets(results([s]))[0]).toMatchObject({date:'2026-09-14',value:1})
})
it('uses rep threshold for load records and exact load for repetition records',()=>{
 const rows=results([fixture()]);expect(points(rows,'load',8)[0].value).toBe(50000)
 expect(points(rows,'reps',1,40000)[0].value).toBe(12);expect(points(rows,'reps',1,41000)).toEqual([])
})
it('handles zero assistance and bodyweight without fake loads',()=>{
 const s=fixture();s.exercises[0].mode='AssistedBodyweight';s.exercises[0].records[0].loadGrams=0
 expect(points(results([s]),'load')[0].value).toBe(0)
 s.exercises[0].mode='BodyweightOnly';s.exercises[0].records.forEach(r=>r.loadGrams=null)
 expect(points(results([s]),'load')).toEqual([]);expect(points(results([s]),'reps')[0].value).toBe(12)
})
it('escapes spreadsheet formulas, quotes and newlines; drafts have no canonical result',()=>{
 expect(csvCell(' =1+1')).toBe('"\' =1+1"');expect(csvCell('a"b\nc')).toBe('"a""b\nc"')
 const s=fixture();s.exercises[0].records=s.exercises[0].records.slice(0,1);s.exercises[0].records[0].status='draft'
 const csv=sessionsCsv([s]);expect(csv.startsWith('\ufeff')).toBe(true);expect(csv).not.toContain('"40000"');expect(csv).toContain('"40";"12";"";""')
})
it('correction preserves dates/context and recomputes confirmed grams',()=>{
 const s=fixture(),edit=structuredClone(s);edit.exercises[0].records[0].weight='72,5';edit.localDate='2000-01-01'
 const result=prepareCorrection(s,edit);expect(result.localDate).toBe(s.localDate);expect(result.completedAt).toBe(s.completedAt)
 expect(result.exercises[0].records[0].completedAt).toBe(s.exercises[0].records[0].completedAt)
 expect(points(results([result]),'load')[0].value).toBe(72500);expect(result.restEndsAt).toBeNull()
})
it('saves correction and outbox atomically; rejects stale snapshot even at same revision',async()=>{
 const s=fixture();await db.sessions.put(s);const edit=structuredClone(s);edit.exercises[0].records[0].weight='80'
 await saveCorrection(s,edit);expect((await db.sessions.get(s.id))?.revision).toBe(2);expect(await db.outbox.count()).toBe(1)
 await expect(saveCorrection(s,edit)).rejects.toThrow()
 const fresh=(await db.sessions.get(s.id))!;const remote=structuredClone(fresh);remote.name='Remote';await db.sessions.put(remote)
 await expect(saveCorrection(fresh,fresh)).rejects.toThrow('другом устройстве');expect((await db.sessions.get(s.id))?.name).toBe('Remote')
})
it('invalid correction leaves stored record and outbox untouched',async()=>{
 const s=fixture();await db.sessions.put(s);const edit=structuredClone(s);edit.exercises[0].records[0].weight='72,'
 await expect(saveCorrection(s,edit)).rejects.toThrow();expect(await db.sessions.get(s.id)).toEqual(s);expect(await db.outbox.count()).toBe(0)
})
