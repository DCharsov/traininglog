import Dexie, { type Table } from 'dexie'
import { backupSchema, makeSession, uid, type Backup, type Day, type Program, type Session, type Equipment, type CalendarEntry } from './domain'

export type Kind = 'programs'|'sessions'|'equipment'|'calendar'
export type Document = Program|Session|Equipment|CalendarEntry
export type SyncMeta = { key: string; kind: Kind; id: string; version: number; synced: string; remote?: Document; conflict?: boolean }
export type SyncOperation = { key: string; operationId: string; baseVersion: number; generation: string; payload: Document }
export type EditorDraft = { key:string; kind:'program'|'history'; original:Program|Session; value:Program|Session; updatedAt:string }
export const db = new Dexie('traininglog-v1') as Dexie & { editorDrafts:Table<EditorDraft,string>; equipment: Table<Equipment,string>; calendar: Table<CalendarEntry,string>; meta: Table<SyncMeta,string>; operations: Table<SyncOperation,string>; syncState: Table<{key:string;value:string},string>; conflictArchive: Table<{id:string;key:string;local:Document|undefined;remote:Document|undefined},string>; programs: Table<Program, string>; sessions: Table<Session, string>; outbox: Table<{ id: string; sessionId: string; revision: number; payload: Session }, string> }
db.version(1).stores({ programs: 'id', sessions: 'id, status, startedAt', outbox: 'id, sessionId' })
db.version(2).stores({ programs: 'id', sessions: 'id, status, startedAt', outbox: 'id, sessionId', meta: 'key', operations: 'key', syncState: 'key', conflictArchive: 'id, key' })
db.version(3).stores({ equipment: 'id', calendar: 'id, date' })
db.version(4).stores({ editorDrafts:'key, kind, updatedAt' })
async function queue(s: Session) { await db.sessions.put(s); await db.outbox.put({ id: uid(), sessionId: s.id, revision: s.revision, payload: structuredClone(s) }) }
export async function start(program: Program, day: Day, includeOptional = false) {
  return db.transaction('rw', db.sessions, db.outbox, async () => {
    if (await db.sessions.where('status').equals('active').filter(s=>!s.deletedAt).count()) throw new Error('Сначала завершите активную тренировку.')
    const s = makeSession(program, day, includeOptional); await queue(s); return s
  })
}
export async function change(id: string, revision: number, mutate: (session: Session) => boolean | void, enqueue = true) {
  return db.transaction('rw', db.sessions, db.outbox, async () => {
    const s = await db.sessions.get(id)
    if (!s || (revision !== -1 && s.revision !== revision)) throw new Error('Запись изменилась в другой вкладке. Обновите экран и повторите действие.')
    if (mutate(s) === false) return
    s.revision++
    if (enqueue) await queue(s); else await db.sessions.put(s)
  })
}
export async function exportData(): Promise<Backup> {
  return db.transaction('r', [db.programs, db.sessions, db.equipment, db.calendar], async () => ({ equipment: await db.equipment.toArray(), calendar: await db.calendar.toArray(), schemaVersion: 2, exportedAt: new Date().toISOString(), programs: await db.programs.toArray(), sessions: await db.sessions.toArray() }))
}
export function download(data: Backup, name = 'traininglog') {
  const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }))
  const a = document.createElement('a'); a.href = url; a.download = `${name}-${new Date().toISOString().slice(0,10)}.json`; a.click(); setTimeout(() => URL.revokeObjectURL(url), 10000)
}
export async function restore(value: unknown) {
  const data = backupSchema.parse(value)
  await navigator.locks.request('traininglog-sync', async () => db.transaction('rw', [db.programs, db.sessions, db.equipment, db.calendar, db.outbox, db.meta, db.operations, db.syncState, db.editorDrafts], async () => {
    await db.editorDrafts.clear()
    await db.equipment.clear(); await db.calendar.clear(); await db.programs.clear(); await db.sessions.clear(); await db.outbox.clear(); await db.meta.clear(); await db.operations.clear(); await db.syncState.clear()
    await db.equipment.bulkAdd(data.equipment??[]); await db.calendar.bulkAdd(data.calendar??[]); await db.programs.bulkAdd(data.programs); await db.sessions.bulkAdd(data.sessions)
  }))
  // A new-program draft also has a navigation seed outside IndexedDB.
  if(typeof localStorage!=='undefined')localStorage.removeItem('traininglog-new-program')
}

export async function lifecycleChange(kind:Kind,id:string,action:'archive'|'delete'|'restore') {
  await db.transaction('rw',[db[kind]],async()=>{
    const table=db[kind] as Table<Document,string>, doc=await table.get(id)
    if(!doc)throw new Error('Запись не найдена.')
    if('status' in doc && doc.status==='active')throw new Error('Сначала завершите или отмените тренировку.')
    if(action==='restore'){doc.deletedAt=null;doc.archivedAt=null}
    else if(action==='delete')doc.deletedAt=new Date().toISOString()
    else doc.archivedAt=new Date().toISOString()
    if('revision' in doc)doc.revision++
    if('version' in doc)doc.version++
    await table.put(doc)
  })
}
