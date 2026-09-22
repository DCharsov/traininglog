import 'fake-indexeddb/auto'
import Dexie from 'dexie'
import { afterEach, expect, it } from 'vitest'
import { db, exportData, restore, start } from './data'
import { broSplit } from './broSplit'

afterEach(async()=>{db.close();await Dexie.delete(db.name)})
it('upgrades a v3 journal without dropping sessions or its sync queue',async()=>{
 db.close();await Dexie.delete(db.name)
 const old=new Dexie(db.name)
 old.version(3).stores({programs:'id',sessions:'id, status, startedAt',outbox:'id, sessionId',meta:'key',operations:'key',syncState:'key',conflictArchive:'id, key',equipment:'id',calendar:'id, date'})
 await old.table('programs').put(structuredClone(broSplit));await old.table('operations').put({key:'pending',operationId:'unchanged'})
 old.close();await db.open()
 expect((await db.programs.get(broSplit.id))?.name).toBe(broSplit.name)
 expect((await db.operations.get('pending'))?.operationId).toBe('unchanged')
 expect(await db.editorDrafts.count()).toBe(0)
})
it('editor copies stay local and survive reopening with their original version',async()=>{
 await db.open();const original=structuredClone(broSplit),value={...original,name:'Несохранённое название'}
 await db.programs.put(original);await db.editorDrafts.put({key:`program:${original.id}`,kind:'program',original,value,updatedAt:new Date().toISOString()})
 db.close();await db.open()
 expect((await db.editorDrafts.get(`program:${original.id}`))?.value.name).toBe(value.name)
 const backup=await exportData();expect(backup.programs[0].name).toBe(original.name);expect(backup).not.toHaveProperty('editorDrafts')
 expect(await db.operations.count()).toBe(0)
})
it('restore clears old editor copies atomically and rejects invalid imports before clearing',async()=>{
 await db.open();const original=structuredClone(broSplit);await db.programs.put(original);await start(original,original.days[0])
 const backup=await exportData(),entry={key:`program:${original.id}`,kind:'program' as const,original,value:original,updatedAt:new Date().toISOString()}
 await db.editorDrafts.put(entry)
 await expect(restore({schemaVersion:999})).rejects.toThrow();expect(await db.editorDrafts.count()).toBe(1)
 const fail=()=>{throw new Error('disk full')};db.programs.hook('creating',fail)
 try{await expect(restore(backup)).rejects.toThrow('disk full');expect(await db.editorDrafts.count()).toBe(1)}finally{db.programs.hook('creating').unsubscribe(fail)}
 await restore(backup);expect(await db.editorDrafts.count()).toBe(0);expect(await db.sessions.count()).toBe(1)
})
