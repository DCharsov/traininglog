import 'fake-indexeddb/auto'
import { beforeEach, afterEach, expect, it, vi } from 'vitest'
import { db, change } from './data'
import { broSplit } from './broSplit'
import { makeSession } from './domain'
import { applyRemote, canonical, resolveConflict, syncOnce } from './sync'
beforeEach(async()=>{for(const t of db.tables)await t.clear()})
afterEach(()=>vi.unstubAllGlobals())
it('remote updates never overwrite dirty local data and resolution archives both versions',async()=>{
 const local=structuredClone(broSplit),remote={...broSplit,name:'Changed elsewhere'}
 await db.programs.put(local)
 await applyRemote('programs',local.id,2,remote)
 expect((await db.programs.get(local.id))?.name).toBe(local.name)
 const m=(await db.meta.get(`programs:${local.id}`))!
 expect(m.conflict).toBe(true)
 await resolveConflict(m,'remote')
 expect((await db.programs.get(local.id))?.name).toBe(remote.name)
 expect(await db.conflictArchive.count()).toBe(1)
})
it('two active sessions remain separate; remote activation waits for user resolution',async()=>{
 const a=makeSession(broSplit,broSplit.days[0]),b=makeSession(broSplit,broSplit.days[1]);await db.sessions.put(a)
 await applyRemote('sessions',b.id,1,b)
 expect(await db.sessions.count()).toBe(1)
 await expect(resolveConflict((await db.meta.get(`sessions:${b.id}`))!,'remote')).rejects.toThrow('Сначала')
})
it('lost response retries immutable operation; newer local revision survives and follows acknowledged base',async()=>{
 const s=makeSession(broSplit,broSplit.days[0]);await db.sessions.put(s)
 await db.syncState.put({key:'generation',value:'g'})
 const requests: Record<string,unknown>[]=[];let lost=true
 vi.stubGlobal('fetch',vi.fn(async(path:string,init?:RequestInit)=>{
  const response=(data:unknown)=>new Response(JSON.stringify(data),{status:200})
  if(path.endsWith('/auth/state'))return response({authenticated:true,token:'t'})
  if(path.endsWith('/bootstrap'))return response({contractVersion:2,generation:'g'})
  if(path.includes('/changes'))return response({changes:[],cursor:0,hasMore:false})
  const body=JSON.parse(String(init?.body));requests.push(body)
  if(lost){lost=false;await change(s.id,-1,s=>{s.exercises[0].records[0].weight='42'},false);throw new Error('lost response')}
  return response({version:body.baseVersion+1,generation:'g'})
 }))
 await expect(syncOnce()).rejects.toThrow('lost response')
 expect(await db.operations.count()).toBe(1)
 await syncOnce()
 expect(requests[1]).toEqual(requests[0])
 expect(requests[2].baseVersion).toBe(1)
 expect((await db.sessions.get(s.id))?.exercises[0].records[0].weight).toBe('42')
 expect((await db.meta.get(`sessions:${s.id}`))?.synced).toBe(canonical(await db.sessions.get(s.id)))
 expect(await db.operations.count()).toBe(0)
})
