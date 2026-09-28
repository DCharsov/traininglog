// Add the versioned reservation extension without dropping existing watch/link contracts.
import {readFileSync, writeFileSync} from 'node:fs'
export function addReservations(api) {
const ref = name => ({$ref:`#/components/schemas/${name}`})
const uuid = {type:'string',format:'uuid'}, str={type:'string'}, integer={type:'integer',format:'int64',minimum:1}
const object = properties => ({type:'object',required:Object.keys(properties),properties})
api.components.schemas.ReservationCreate = object({operationId:uuid,generation:str,deviceId:uuid,payload:ref('Session')})
api.components.schemas.ReservationCommand = object({operationId:uuid,generation:str,reservationId:uuid,version:integer,controlEpoch:integer})
api.components.schemas.ReservationStart = object({...api.components.schemas.ReservationCommand.properties,payload:ref('Session')})
api.components.schemas.ReservationSnapshot = object({reservationId:uuid,deviceId:uuid,generation:str,version:integer,controlEpoch:integer,state:{type:'string',enum:['preparing','ready','started','cancelled','completed']},phoneReady:{type:'boolean'},watchReady:{type:'boolean'},payload:ref('Session'),protocolVersion:{type:'integer',const:1},contractVersion:{type:'integer',const:2}})
api.components.schemas.Bootstrap.properties.watchReservationsVersion={type:'integer',const:1}
const response = schema => ({description:'Successful idempotent receipt or current snapshot',content:{'application/json':{schema}}})
const errors = Object.fromEntries([400,401,403,404,409,423,426,429,503].map(status=>[status,{description:status===409?'Generation/version/epoch changed; preserve local data and reconcile, do not blindly retry with a new operationId':`Error ${status}`,content:{'application/json':{schema:ref('Error')}}}]))
const nullable={oneOf:[ref('ReservationSnapshot'),{type:'null'}]}
const operation = (id, schema, request, bearer, description) => ({operationId:id,description,security:bearer?[{watchBearer:[]}]:[{ownerCookie:[]}],...(request?{requestBody:{required:true,content:{'application/json':{schema:ref(request)}}},...(!bearer?{parameters:[{name:'X-CSRF-TOKEN',in:'header',required:true,schema:str}]}:{})}:{}),responses:{200:response(schema),...errors}})
api.paths['/watch/reservation']={
 get:operation('readReservation',object({enabled:{type:'boolean'},reservation:nullable}),null,false,'One reservation per owner. No expiry. Not a Session until explicitly started.'),
 post:operation('createReservation',ref('ReservationSnapshot'),'ReservationCreate',false,'Requires Watch:ReservationsEnabled. A pristine Session template is reserved, but no Session/history/timer is created. Old clients cannot start a competing workout. All writes use the shared transaction gate.')
}
api.paths['/watch/reservation/phone-ready']={post:operation('confirmPhoneReservation',ref('ReservationSnapshot'),'ReservationCommand',false,'Call only after the snapshot is durably saved on iPhone. Readiness requires both devices.')}
api.paths['/watch/reservation/force-cancel']={post:operation('cancelReservation',ref('ReservationSnapshot'),'ReservationCommand',false,'Explicit warning required: watch may have started offline. Raises controlEpoch. Late results must use /watch/v1/recovery, never overwrite current history.')}
api.paths['/watch/v1/reservation/']={get:operation('readWatchReservation',object({reservation:nullable}),null,true,'Returns only the authenticated device’s assigned reservation.')}
api.paths['/watch/v1/reservation/ready']={post:operation('confirmWatchReservation',ref('ReservationSnapshot'),'ReservationCommand',true,'Call only after atomic local persistence. A ready snapshot permits offline start by the sole watch editor.')}
api.paths['/watch/v1/reservation/start']={post:operation('startReservation',ref('WatchSnapshot'),'ReservationStart',true,'Upload immutable offline start. Actual startedAt/localDate/timezone replace preparation placeholders. Requires ready state, matching generation/version/epoch and assigned device. Replay does not prove current ownership: fetch /watch/v1/session before continuing sync. Completion uses the existing watch write protocol.')}
if (!api.components.schemas.WatchSnapshot) throw new Error('Missing existing WatchSnapshot schema')
return api
}
if (import.meta.main) {
 const file = new URL('../../apps/api/openapi.json', import.meta.url)
 const api = JSON.parse(readFileSync(file, 'utf8'))
 writeFileSync(file, JSON.stringify(addReservations(api),null,2)+'\n')
}
