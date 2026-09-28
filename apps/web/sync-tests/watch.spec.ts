import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
const fixture=JSON.parse(readFileSync(new URL('../../../tests/contracts/watch/session.json',import.meta.url),'utf8'))

test('phone handoff → offline repeated sets → idempotent upload → phone return',async({page,playwright})=>{
 test.setTimeout(90000)
 await page.goto('/training/')
 await page.evaluate(async payload=>{
  const dataPath='/training/src/data.ts',syncPath='/training/src/sync.ts'
  const {db}=await import(dataPath),sync=await import(syncPath)
  await sync.login('Test-only-password!123')
  await db.sessions.put(payload)
  await db.syncState.put({key:'enabled',value:'yes'})
  await sync.syncOnce()
 },fixture)
 const code=await page.evaluate(async()=>{const path='/training/src/sync.ts',{api}=await import(path);return (await api('/watch/pairing','POST',{})).code})
 const anonymous=await playwright.request.newContext({baseURL:'http://127.0.0.1:5181'})
 const redeem=await anonymous.post('/training/api/watch/pairing/redeem',{data:{code,name:'E2E Watch'}})
 expect(redeem.ok()).toBeTruthy()
 const credentials=await redeem.json()
 const watch=await playwright.request.newContext({baseURL:'http://127.0.0.1:5181',extraHTTPHeaders:{Authorization:`Bearer ${credentials.token}`}})
 try{
  await page.getByRole('button',{name:'Выбрать часы',exact:true}).click()
  await page.getByLabel('Часы для тренировки').selectOption(credentials.deviceId)
  await page.getByRole('button',{name:'Продолжить на часах',exact:true}).click()
  await expect(page.getByText('Ожидаем приёма на часах',{exact:false})).toBeVisible()
  const offered=(await (await watch.get('/training/api/watch/v1/session')).json()).session
  const command={operationId:crypto.randomUUID(),sessionId:offered.sessionId,generation:offered.generation,baseVersion:offered.version,controlEpoch:offered.control.controlEpoch,handoffId:offered.control.handoffId}
  const acceptedResponse=await watch.post('/training/api/watch/v1/handoff/accept',{data:command})
  expect(acceptedResponse.ok()).toBeTruthy()
  const accepted=await acceptedResponse.json()
  await expect(page.getByText('Управление на часах',{exact:false})).toBeVisible({timeout:15000})
  expect(await page.locator('fieldset[disabled]').count()).toBeGreaterThan(0)
  const local=await page.evaluate(async payload=>{
   const domainPath='/training/src/domain.ts',fillPath='/training/src/watchAutofill.ts'
   const {sessionSchema,confirmSet}=await import(domainPath),{autofillWatchSet}=await import(fillPath)
   sessionSchema.parse(payload)
   const local=structuredClone(payload),exercise=local.exercises[0]
   Object.assign(exercise.records[0],{weight:'12,5',reps:'10'})
   confirmSet(local,exercise.id,exercise.records[0].id)
   if(!autofillWatchSet(local,exercise.id,exercise.records[1].id))throw new Error('Autofill failed')
   confirmSet(local,exercise.id,exercise.records[1].id)
   local.revision+=3
   return local
  },accepted.payload)
  // Both sets exist only on the simulated offline watch until this PUT.
  const before=await page.evaluate(async id=>{const path='/training/src/sync.ts',{api}=await import(path);return api(`/sessions/${id}`)},local.id)
  expect(before.payload.exercises[0].records[0].status).toBe('draft')
  const write={operationId:crypto.randomUUID(),protocolVersion:1,contractVersion:2,generation:accepted.generation,baseVersion:accepted.version,controlEpoch:accepted.control.controlEpoch,payload:local}
  const first=await watch.put(`/training/api/watch/v1/sessions/${local.id}`,{data:write})
  expect(first.ok(),await first.text()).toBeTruthy();const saved=await first.json()
  const repeated=await watch.put(`/training/api/watch/v1/sessions/${local.id}`,{data:write})
  expect(await repeated.json()).toEqual(saved)
  const release=await watch.post('/training/api/watch/v1/control/release',{data:{operationId:crypto.randomUUID(),sessionId:local.id,generation:saved.generation,baseVersion:saved.version,controlEpoch:saved.control.controlEpoch}})
  expect(release.ok()).toBeTruthy()
  await expect(page.getByText('Управление на телефоне',{exact:false})).toBeVisible({timeout:15000})
  const final=await page.evaluate(async id=>{const path='/training/src/data.ts',{db}=await import(path);return db.sessions.get(id)},local.id)
  expect(final.exercises[0].records.slice(0,2).map((r:{weight:string;reps:string;status:string})=>[r.weight,r.reps,r.status])).toEqual([['12,5','10','completed'],['12,5','10','completed']])
 }finally{await watch.dispose();await anonymous.dispose()}
})
