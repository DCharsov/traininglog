import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { contract } from '../../apps/web/scripts/build-contract.mjs'
import { addReservations } from './add-reservations.mjs'

test('checked-in contract is reproducible from source, without reading generated output', () => {
 const generated=readFileSync(new URL('../../apps/api/openapi.json',import.meta.url),'utf8')
 assert.equal(generated,JSON.stringify(contract,null,2)+'\n')
 const copy=structuredClone(contract)
 addReservations(copy)
 assert.deepEqual(copy,contract)
})

test('all references resolve and operation IDs are unique', () => {
 const visit=value=>{
  if(!value || typeof value!=='object') return
  if(value.$ref) {
   assert.ok(value.$ref.startsWith('#/'))
   let target=contract
   for(const part of value.$ref.slice(2).split('/')) target=target?.[part.replaceAll('~1','/').replaceAll('~0','~')]
   assert.ok(target,`Unresolved ${value.$ref}`)
  }
  Object.values(value).forEach(visit)
 }
 visit(contract)
 const ids=Object.values(contract.paths).flatMap(path=>Object.values(path).map(op=>op.operationId))
 assert.equal(new Set(ids).size,ids.length)
 assert.ok(ids.every(Boolean))
})

test('watch, automatic linking, recovery and reservation routes survive generation', () => {
 for(const route of ['/watch/link/window','/watch/link/request','/watch/link/status',
  '/watch/devices','/sessions/{id}/watch-control','/sessions/{id}/watch-force-return',
  '/watch/recovery/{id}','/watch/v1/session','/watch/v1/recovery',
  '/watch/reservation','/watch/reservation/force-cancel','/watch/v1/reservation/start'])
  assert.ok(contract.paths[route],route)
 for(const [path,methods] of Object.entries(contract.paths)) {
  for(const [method,op] of Object.entries(methods)) {
   if(path.startsWith('/watch/v1/')) assert.deepEqual(op.security,[{watchBearer:[]}],path)
   const security=op.security??contract.security
   if(['post','put','delete'].includes(method)&&security.some(item=>'ownerCookie' in item))
    assert.ok(op.parameters?.some(p=>p.name==='X-CSRF-TOKEN'&&p.required),`${method} ${path}`)
  }
 }
 assert.ok(contract.paths['/{kind}/{id}'].put.responses[423])
})

test('Day archival is optional and nullable', () => {
 const day=contract.components.schemas.Program.properties.days.items
 assert.ok(day.properties.archivedAt)
 assert.ok(!day.required.includes('archivedAt'))
 assert.ok(day.properties.archivedAt.anyOf.some(s=>s.type==='null'))
})
