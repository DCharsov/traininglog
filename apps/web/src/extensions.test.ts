import 'fake-indexeddb/auto'
import Dexie from 'dexie'
import { beforeEach, expect, it } from 'vitest'
import { broSplit } from './broSplit'
import { adjustedWeight, backupSchema, confirmSet, makeSession, previous, uid } from './domain'
import { db, exportData, lifecycleChange, restore } from './data'
import { applyRemote, canonical, resolveConflict } from './sync'
import { contextKey, points, results, sessionsCsv } from './progress'
import { nextDay, setSequence } from './workoutFlow'
import { hasEntries, swapExercise } from './workoutEditing'
import { prepareCorrection } from './historyCorrection'
beforeEach(async()=>{for(const t of db.tables)await t.clear()})
function durationSession() {
 const p=structuredClone(broSplit);p.days[0].exercises=[{...p.days[0].exercises[0],name:'Планка',mode:'BodyweightOnly',tracking:'duration',unilateral:true,sets:1}]
 return makeSession(p,p.days[0])
}
it('records seconds and each side independently; neither blank nor zero is completed',()=>{
 const s=durationSession(),e=s.exercises[0],[left,right]=e.records
 expect(e.records.map(r=>r.side)).toEqual(['left','right'])
 expect(()=>confirmSet(s,e.id,left.id)).toThrow('Длительность')
 left.duration='0';expect(()=>confirmSet(s,e.id,left.id)).toThrow()
 left.duration='45';confirmSet(s,e.id,left.id);right.duration='30';confirmSet(s,e.id,right.id)
 expect(left.count).toBeNull();expect(left.durationSeconds).toBe(45)
 s.status='completed'
 expect(points(results([s],{side:'left'}),'duration').map(p=>p.value)).toEqual([45])
 expect(points(results([s],{side:'right'}),'duration').map(p=>p.value)).toEqual([30])
 expect(points(results([s]),'reps')).toEqual([])
 const edited=structuredClone(s);edited.exercises[0].records[0].duration='60'
 expect(prepareCorrection(s,edited).exercises[0].records[0].durationSeconds).toBe(60)
 expect(sessionsCsv([s])).toContain('"left";"45";"45"')
})
it('duration drafts are kept during replacement and incompatible profiles never compare',()=>{
 const s=durationSession(),ex=s.exercises[0];ex.records[0].duration='15'
 expect(hasEntries(ex)).toBe(true);swapExercise(s,ex.id,broSplit.days[0].exercises[0]);expect(s.exercises).toHaveLength(2)
 const old=durationSession();old.startedAt='2020-01-01T00:00:00.000Z';old.status='completed';old.exercises[0].records[0].duration='30';confirmSet(old,old.exercises[0].id,old.exercises[0].records[0].id)
 const current=durationSession();current.exercises[0].tracking='reps'
 expect(contextKey(old.exercises[0])).not.toBe(contextKey(current.exercises[0]))
 expect(previous([old],current,current.exercises[0])).toBeUndefined()
})
it('irregular equipment list takes precedence; steps use exact grams and unknown steps stay unknown',()=>{
 expect(adjustedWeight({stepGrams:5000,availableGrams:[40000,47000,54000]},'40',1)).toBe('47')
 expect(adjustedWeight({stepGrams:125},'1,001',1)).toBe('1,126')
 expect(()=>adjustedWeight({},'40',1)).toThrow()
 expect(()=>adjustedWeight({availableGrams:[40000,47000]},'47',1)).toThrow()
 expect(()=>adjustedWeight({stepGrams:2500},'0',-1)).toThrow()
})
it('arbitrary three-exercise supersets interleave; explicit null disables source grouping',()=>{
 const s=makeSession(broSplit,broSplit.days[0]);s.exercises.forEach(e=>e.supersetGroup=null)
 s.exercises.slice(0,3).forEach(e=>e.supersetGroup='Мой круг')
 expect(setSequence(s).slice(0,6).map(x=>x.exercise.id)).toEqual([...s.exercises.slice(0,3),...s.exercises.slice(0,3)].map(e=>e.id))
 const all=setSequence(s);expect(new Set(all.map(x=>x.record.id)).size).toBe(all.length)
 expect(all.filter(x=>x.exercise.id===s.exercises[3].id).every(x=>!x.superset)).toBe(true)
})
it('tombstones synchronize, dirty edits conflict, restore retains results, active deletion is blocked',async()=>{
 const s=durationSession();await db.sessions.put(s);await expect(lifecycleChange('sessions',s.id,'delete')).rejects.toThrow('Сначала')
 s.status='completed';s.exercises[0].records[0].duration='30';confirmSet(s,s.exercises[0].id,s.exercises[0].records[0].id);await db.sessions.put(s)
 await db.meta.put({key:`sessions:${s.id}`,id:s.id,kind:'sessions',version:1,synced:canonical(s)})
 await applyRemote('sessions',s.id,2,{...s,deletedAt:new Date().toISOString()})
 const deleted=(await db.sessions.get(s.id))!;expect(results([deleted])).toEqual([])
 expect(nextDay(broSplit,[deleted]).previous).toBeUndefined()
 await lifecycleChange('sessions',s.id,'restore');expect(results([(await db.sessions.get(s.id))!])).toHaveLength(1)
 await applyRemote('sessions',s.id,3,{...s,deletedAt:new Date().toISOString()})
 const conflict=(await db.meta.get(`sessions:${s.id}`))!;expect(conflict.conflict).toBe(true)
 await resolveConflict(conflict,'local');expect((await db.sessions.get(s.id))?.deletedAt).toBeNull()
})
it('version 2 backup round-trips catalogs and rest days; legacy 1 restores without them',async()=>{
 const e={id:uid(),name:'Стек 1',mode:'MachineStack' as const,stepGrams:7000,availableGrams:[40000,47000]}
 const day={id:uid(),name:'Отдых',date:'2026-09-14',status:'completed' as const}
 await db.equipment.put(e);await db.calendar.put(day)
 await restore(await exportData());expect(await db.equipment.get(e.id)).toEqual(e);expect(await db.calendar.get(day.id)).toEqual(day)
 await restore({schemaVersion:1,exportedAt:new Date().toISOString(),programs:[broSplit],sessions:[]});expect(await db.equipment.count()).toBe(0)
 expect(backupSchema.safeParse({schemaVersion:2,exportedAt:'',programs:[],sessions:[],calendar:[{...day,date:'2026-02-30'}]}).success).toBe(false)
})
it('equipment and calendar use conflict protection too',async()=>{
 const item={id:uid(),name:'Блок',mode:'MachineStack' as const,stepGrams:7000}
 await db.equipment.put(item);await applyRemote('equipment',item.id,1,{...item,name:'Другой блок'})
 const m=(await db.meta.get(`equipment:${item.id}`))!;expect(m.conflict).toBe(true)
 await resolveConflict(m,'remote');expect((await db.equipment.get(item.id))?.name).toBe('Другой блок')
 const day={id:uid(),name:'Отдых',date:'2026-09-14',status:'planned'};await applyRemote('calendar',day.id,1,day)
 expect(await db.calendar.get(day.id)).toEqual(day)
})
it('IndexedDB v2 upgrade preserves draft, pending operation and sync metadata',async()=>{
 db.close();await Dexie.delete('traininglog-v1')
 const legacy=new Dexie('traininglog-v1');legacy.version(2).stores({programs:'id',sessions:'id, status, startedAt',outbox:'id, sessionId',meta:'key',operations:'key',syncState:'key',conflictArchive:'id, key'})
 const s=makeSession(broSplit,broSplit.days[0]);s.exercises[0].records[0].weight='72,'
 await legacy.table('sessions').put(s);await legacy.table('operations').put({key:`sessions:${s.id}`,operationId:uid(),baseVersion:0,generation:'old',payload:s});legacy.close()
 await db.open();expect((await db.sessions.get(s.id))?.exercises[0].records[0].weight).toBe('72,');expect(await db.operations.count()).toBe(1);expect(await db.calendar.count()).toBe(0)
})
