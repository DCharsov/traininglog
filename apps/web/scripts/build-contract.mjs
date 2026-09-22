import { writeFileSync } from 'node:fs'
import { z } from 'zod'
import { programSchema, sessionSchema, equipmentSchema, calendarSchema, backupSchema } from '../src/domain.ts'
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
const errors=Object.fromEntries([400,401,403,404,409,426,429,500].map(n=>[n,{...response(ref('Error')),description:`Ошибка ${n}`}]))
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
writeFileSync(new URL('../../api/openapi.json',import.meta.url),JSON.stringify({openapi:'3.1.0',info:{title:'TrainingLog API',version:'2.0.0'},servers:[{url:'/training/api'}],security:[{ownerCookie:[]}],components:{securitySchemes:{ownerCookie:{type:'apiKey',in:'cookie',name:'TrainingLog.Auth'}},schemas},paths},null,2)+'\n')
