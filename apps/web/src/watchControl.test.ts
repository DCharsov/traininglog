import 'fake-indexeddb/auto'
import { beforeEach, afterEach, expect, it, vi } from 'vitest'
import { db, change, restore, exportData, lifecycleChange, watchControls } from './data'
import { sessionSchema } from './domain'
import fixture from '../../../tests/contracts/watch/session.json'
import { applyWatchSnapshot, canonical, resolveConflict, syncOnce } from './sync'
import { handoffToWatch, retryWatchCommand } from './watchControl'
import type { WatchSnapshot } from './watchApi'

beforeEach(async()=>{for(const table of db.tables)await table.clear()})
afterEach(()=>vi.unstubAllGlobals())
const snapshot=(state:'phone'|'watch'|'offered'='watch'):WatchSnapshot=>({protocolVersion:1,contractVersion:2,sessionId:fixture.id,version:2,generation:'g',control:{state,controlEpoch:1,deviceId:'watch',handoffId:'handoff'},payload:sessionSchema.parse(fixture)})
it('blocks all existing data writes, import and conflict resolution while watch-owned',async()=>{
 const remote=snapshot();await applyWatchSnapshot(remote)
 await expect(change(fixture.id,-1,s=>{s.name='bad'})).rejects.toThrow('часам')
 await expect(lifecycleChange('sessions',fixture.id,'delete')).rejects.toThrow('часам')
 await expect(restore(await exportData())).rejects.toThrow('часов')
 const meta={key:`sessions:${fixture.id}`,kind:'sessions' as const,id:fixture.id,version:2,synced:'',remote:remote.payload,conflict:true}
 await db.meta.put(meta)
 await expect(resolveConflict(meta,'local')).rejects.toThrow('часам')
 expect((await db.sessions.get(fixture.id))?.name).toBe(fixture.name)
})
it('archives a stale local copy and keeps reading the current watch snapshot',async()=>{
 const local=sessionSchema.parse(fixture);local.exercises[0].records[0].weight='99'
 await db.sessions.put(local)
 await applyWatchSnapshot(snapshot())
 expect(await db.conflictArchive.count()).toBe(1)
 expect((await db.sessions.get(local.id))?.exercises[0].records[0].weight).toBe('')
 const returned=snapshot('phone');returned.version=3
 await applyWatchSnapshot(returned)
 await expect(change(local.id,-1,s=>{s.exercises[0].records[0].weight='10'})).resolves.toBeUndefined()
})
it('preserves another offline active workout instead of installing two active sessions',async()=>{
 const local=sessionSchema.parse(fixture);local.id=crypto.randomUUID();local.name='Offline workout'
 await db.sessions.put(local)
 await applyWatchSnapshot(snapshot())
 expect(await db.sessions.count()).toBe(1)
 expect((await db.sessions.get(local.id))?.name).toBe('Offline workout')
 expect((await db.meta.get(`sessions:${fixture.id}`))?.conflict).toBe(true)
 expect((await watchControls.get(fixture.id))?.state).toBe('watch')
})
it('handoff syncs dirty values first and retries a lost response with the same operation',async()=>{
 const local=sessionSchema.parse(fixture);local.exercises[0].records[0].weight='12,5'
 await db.sessions.put(local);await db.syncState.put({key:'generation',value:'g'})
 let server=snapshot('phone');server.version=1;server.control.controlEpoch=0
 await db.meta.put({key:`sessions:${local.id}`,kind:'sessions',id:local.id,version:1,synced:canonical(server.payload)})
 let lost=true;const requests:unknown[]=[]
 const response=(value:unknown)=>new Response(JSON.stringify(value),{status:200})
 vi.stubGlobal('fetch',vi.fn(async(path:string,init?:RequestInit)=>{
  if(path.endsWith('/auth/state'))return response({authenticated:true,token:'t'})
  if(path.endsWith('/bootstrap'))return response({contractVersion:2,watchProtocolVersion:1,generation:'g'})
  if(path.includes('/changes'))return response({changes:[],cursor:0,hasMore:false})
  if(path.endsWith('/watch-control'))return response(server)
  const body=JSON.parse(String(init?.body))
  if(path.endsWith('/watch-handoff')){
   requests.push(body)
   if(lost){lost=false;server={...server,version:3,control:{state:'offered',controlEpoch:1,deviceId:'watch',handoffId:'handoff'}};throw new Error('response lost')}
   return response(server)
  }
  expect(body.payload.exercises[0].records[0].weight).toBe('12,5')
  server={...server,version:2,payload:body.payload};return response({version:2,generation:'g'})
 }))
 await expect(handoffToWatch(local.id,'watch')).rejects.toThrow('response lost')
 expect((await watchControls.get(local.id))?.state).toBe('preparing')
 await syncOnce() // Polling after the lost response must not discard the pending handoff.
 await retryWatchCommand(local.id)
 expect(requests).toHaveLength(2);expect(requests[1]).toEqual(requests[0])
 expect((await watchControls.get(local.id))?.state).toBe('offered')
 expect((await db.sessions.get(local.id))?.exercises[0].records[0].weight).toBe('12,5')
})
