import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { registerHooks } from 'node:module'
import { addReservations } from '../../../tools/api-contract/add-reservations.mjs'
import { z } from 'zod'
// Node 24 strips TypeScript but does not resolve Vite's extensionless imports.
const sourceRoot=new URL('../src/',import.meta.url).href
const hook=registerHooks({resolve(specifier,context,nextResolve) {
 if(specifier.startsWith('.') && context.parentURL?.startsWith(sourceRoot)) {
  const candidate=new URL(specifier+'.ts',context.parentURL)
  if(existsSync(candidate)) return nextResolve(candidate.href,context)
 }
 return nextResolve(specifier,context)
},load(url,context,nextLoad) {
 return nextLoad(url,url.startsWith(sourceRoot)&&url.endsWith('.json')
  ? {...context,importAttributes:{...context.importAttributes,type:'json'}} : context)
}})
let domain
try { domain=await import('../src/domain.ts') } finally { hook.deregister() }
const { programSchema, sessionSchema, equipmentSchema, calendarSchema, backupSchema }=domain
const ref=name=>({$ref:`#/components/schemas/${name}`})
const object=(properties,required=Object.keys(properties))=>({type:'object',properties,required})
const str={type:'string'},integer={type:'integer',minimum:0},boolean={type:'boolean'}
const document={oneOf:['Program','Session','Equipment','Calendar'].map(ref)}
const schemas=Object.fromEntries(Object.entries({Program:programSchema,Session:sessionSchema,Equipment:equipmentSchema,Calendar:calendarSchema,Backup:backupSchema}).map(([k,v])=>{const schema=z.toJSONSchema(v);delete schema.$schema;return[k,schema]}))
Object.assign(schemas,{
 Kind:{type:'string',enum:['programs','sessions','equipment','calendar']},
 AuthState:object({authenticated:boolean,token:str}),
 Bootstrap:object({contractVersion:{type:'integer',const:2},generation:str}),
 WriteRequest:object({contractVersion:{type:'integer',const:2},operationId:{type:'string',format:'uuid'},baseVersion:integer,generation:str,payload:document}),
 WriteResponse:object({version:integer,generation:str}),
 Error:object({error:str,message:str,version:integer,payload:document,generation:str},[]),
 Resource:object({id:str,version:integer,payload:document}),
 Change:object({sequence:integer,kind:ref('Kind'),id:str,version:integer,payload:document}),
 Changes:object({generation:str,changes:{type:'array',items:ref('Change')},cursor:integer,hasMore:boolean}),
 ResourcePage:object({items:{type:'array',items:ref('Resource')},cursor:integer,hasMore:boolean}),
})
const response=schema=>({description:'Успешный ответ',content:{'application/json':{schema}}})
const errors=Object.fromEntries([400,401,403,404,409,423,426,429,500,503].map(n=>[n,{...response(ref('Error')),description:`Ошибка ${n}`}]))
const op=(id,schema,extra={})=>({operationId:id,responses:{200:response(schema),...errors},...extra})
const body=schema=>({required:true,content:{'application/json':{schema}}})
const param=(name,schema,where='query',required=false)=>({name,in:where,required,schema})
const resourceParams=[param('kind',ref('Kind'),'path',true),param('id',{type:'string',format:'uuid'},'path',true)]
const paths={
 '/health':{get:op('health',object({status:str}),{security:[]})},
 '/auth/state':{get:op('authState',ref('AuthState'),{security:[]})},
 '/auth/login':{post:op('login',{}, {security:[],requestBody:body(object({password:str}))})},
 '/auth/logout':{post:op('logout',{})},
 '/auth/password':{post:op('changePassword',{}, {requestBody:body(object({currentPassword:str,newPassword:str}))})},
 '/bootstrap':{get:op('bootstrap',ref('Bootstrap'))},
 '/changes':{get:op('changes',ref('Changes'),{parameters:[param('after',integer),param('generation',str,'query',true)]})},
 '/export':{get:op('export',ref('Backup'))},
 '/{kind}':{get:op('listResourceChanges',ref('ResourcePage'),{description:'Страницы изменений выбранного каталога по sequence; включает tombstones и предыдущие версии. Последняя версия каждого ID определяет актуальное состояние.',parameters:[resourceParams[0],param('after',integer)]})},
 '/{kind}/{id}':{get:op('readResource',ref('Resource'),{parameters:resourceParams}),put:op('writeResource',ref('WriteResponse'),{parameters:[...resourceParams,param('X-CSRF-TOKEN',str,'header',true)],requestBody:body(ref('WriteRequest'))})}
}
for(const [path,value] of Object.entries(paths))if(path.startsWith('/auth/')&&value.post)value.post.parameters=[param('X-CSRF-TOKEN',str,'header',true)]
// Watch schemas are authored separately; never use generated output as input.
const watch=JSON.parse(readFileSync(new URL('../../../tools/api-contract/watch-contract.json',import.meta.url),'utf8'))
for(const [path,methods] of Object.entries(watch.paths)) for(const [method,operation] of Object.entries(methods)) {
 operation.operationId??=method+path.split(/[^a-zA-Z0-9]+/).filter(Boolean).map(s=>s[0].toUpperCase()+s.slice(1)).join('')
 const owner=(operation.security??[{ownerCookie:[]}]).some(s=>'ownerCookie' in s)
 if(owner&&['post','put','delete'].includes(method)&&!operation.parameters?.some(p=>p.name==='X-CSRF-TOKEN'))
  operation.parameters=[...(operation.parameters??[]),param('X-CSRF-TOKEN',str,'header',true)]
}
for(const name of Object.keys(watch.schemas)) if(schemas[name]) throw new Error(`Duplicate schema: ${name}`)
for(const path of Object.keys(watch.paths)) if(paths[path]) throw new Error(`Duplicate path: ${path}`)
schemas.Bootstrap.properties.watchProtocolVersion={type:'integer',const:1}
Object.assign(schemas,watch.schemas)
Object.assign(paths,watch.paths)
export const contract={openapi:'3.1.0',info:{title:'TrainingLog API',version:'2.0.0'},servers:[{url:'/training/api'}],security:[{ownerCookie:[]}],components:{securitySchemes:{ownerCookie:{type:'apiKey',in:'cookie',name:'TrainingLog.Auth'},...watch.securitySchemes},schemas},paths}
addReservations(contract)
if(import.meta.main) writeFileSync(new URL('../../api/openapi.json',import.meta.url),JSON.stringify(contract,null,2)+'\n')
