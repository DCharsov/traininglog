import type { Exercise, Session, SetRecord } from './domain'
export const contextKey=(e:Exercise)=>JSON.stringify([e.variantId,e.equipmentId,e.mode,e.tracking??'reps',!!e.unilateral])
export type ResultRow={session:Session;exercise:Session['exercises'][number];record:SetRecord;index:number}
export type Filter={from?:string;to?:string;context?:string;side?:SetRecord['side']}
export function results(sessions:Session[],filter:Filter={}):ResultRow[] {
 return sessions.filter(s=>s.status==='completed' && !s.deletedAt && (!filter.from||s.localDate>=filter.from) && (!filter.to||s.localDate<=filter.to))
  .sort((a,b)=>a.startedAt.localeCompare(b.startedAt)||a.id.localeCompare(b.id))
  .flatMap(session=>session.exercises.filter(e=>!filter.context||contextKey(e)===filter.context).flatMap(exercise=>exercise.records.flatMap((record,index)=>record.status==='completed'&&record.kind==='working'&&(exercise.tracking==='duration'?record.durationSeconds!=null:record.count!==null)&&(!filter.side||(record.side??'both')===filter.side)&&(exercise.mode==='BodyweightOnly'||record.loadGrams!==null)?[{session,exercise,record,index}]:[])))
}
export function contexts(sessions:Session[]) {
 const map=new Map<string,Exercise>()
 for(const r of results(sessions))map.set(contextKey(r.exercise),r.exercise)
 return [...map].map(([key,exercise])=>({key,exercise})).sort((a,b)=>a.exercise.name.localeCompare(b.exercise.name))
}
export type Point={id:string;date:string;name:string;value:number}
export function points(rows:ResultRow[],metric:'load'|'reps'|'duration',minReps=1,weight:number|null=null):Point[] {
 const grouped=new Map<string,Point>()
 for(const {session,exercise,record:r} of rows) {
  if((metric!=='duration'&&(r.count??0)<minReps) || ((metric==='reps'||metric==='duration') && exercise.mode!=='BodyweightOnly' && r.loadGrams!==weight))continue
  const value=metric==='duration'?r.durationSeconds??null:metric==='load'?r.loadGrams:r.count
  if(value===null)continue
  const old=grouped.get(session.id)
  const selectMin=metric==='load'&&exercise.mode==='AssistedBodyweight'
  if(!old || (selectMin?value<old.value:value>old.value))grouped.set(session.id,{id:session.id,date:session.localDate,name:session.name,value})
 }
 return [...grouped.values()]
}
export function weeklySets(rows:ResultRow[]):Point[] {
 const weeks=new Map<string,number>()
 for(const r of rows) {
  const d=new Date(`${r.session.localDate}T00:00:00Z`)
  if(!Number.isFinite(d.getTime()) || d.toISOString().slice(0,10)!==r.session.localDate)continue
  d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7))
  const key=d.toISOString().slice(0,10);weeks.set(key,(weeks.get(key)??0)+1)
 }
 return [...weeks].sort(([a],[b])=>a.localeCompare(b)).map(([date,value])=>({id:date,date,name:'Неделя с понедельника',value}))
}
export function csvCell(value:unknown) {
 let s=value===null||value===undefined?'':String(value)
 // Control prefixes are intentional: prevent spreadsheet formula execution.
 // eslint-disable-next-line no-control-regex
 if(/^[\x00-\x20]*[=+@-]|^[\t\r\n]/.test(s))s="'"+s
 return `"${s.replaceAll('"','""')}"`
}
export function sessionsCsv(sessions:Session[]) {
 const header=['session_id','local_date','timezone','session_name','session_status','started_at_utc','completed_at_utc','program_id','program_version','exercise_id','variant_id','equipment_id','exercise','equipment','load_mode','set_id','set_number','set_kind','set_status','weight_input','reps_input','load_grams','confirmed_reps','rir','note','tracking','side','duration_input','duration_seconds','archived_at','deleted_at']
 const rows=sessions.slice().sort((a,b)=>a.startedAt.localeCompare(b.startedAt)).flatMap(s=>s.exercises.flatMap(e=>e.records.map((r,i)=>[s.id,s.localDate,s.timezone,s.name,s.status,s.startedAt,s.completedAt,s.programId,s.programVersion,e.id,e.variantId,e.equipmentId,e.name,e.equipment,e.mode,r.id,i+1,r.kind,r.status,r.weight,r.reps,r.status==='completed'?r.loadGrams:null,r.status==='completed'?r.count:null,r.rir,r.note,e.tracking??'reps',r.side??'both',r.duration??'',r.status==='completed'?r.durationSeconds??null:null,s.archivedAt??'',s.deletedAt??''])))
 return '\ufeff'+[header,...rows].map(row=>row.map(csvCell).join(';')).join('\r\n')+'\r\n'
}
export function downloadCsv(sessions:Session[]) {
 const url=URL.createObjectURL(new Blob([sessionsCsv(sessions)],{type:'text/csv;charset=utf-8'})),a=document.createElement('a')
 a.href=url;a.download=`traininglog-${new Date().toISOString().slice(0,10)}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),10000)
}
