import type { Program, Session } from './domain'
export function nextDay(program:Program,sessions:Session[]) {
 const recent=sessions.filter(s=>!s.deletedAt&&s.programId===program.id&&s.status==='completed'&&program.days.some(d=>d.id===s.dayId)).sort((a,b)=>b.startedAt.localeCompare(a.startedAt)||b.id.localeCompare(a.id))[0]
 const index=recent?program.days.findIndex(d=>d.id===recent.dayId):-1
 return {day:program.days[(index+1)%program.days.length],previous:recent}
}
export type Block={indices:number[];superset:boolean}
/** Упражнения, которые выполняются вместе: одиночное упражнение или связка суперсета. */
export function blocks(session:Session):Block[] {
 const exercises=session.exercises
 const labels=exercises.map(e=>/^([A-Z][12])\s*·\s*Суперсет с ([A-Z][12])(?:\s*·|$)/.exec(e.sourceNote??''))
 const groups=exercises.map((e,i)=>{
  if(e.supersetGroup!==undefined)return e.supersetGroup
  const own=labels[i]
  if(!own||labels.filter(m=>m?.[1]===own[1]).length!==1)return null
  const matches=labels.filter(m=>m&&m[1]===own[2]&&m[2]===own[1])
  return matches.length===1?own[1][0]:null
 })
 const used=new Set<number>(),result:Block[]=[]
 for(let i=0;i<exercises.length;i++){
  if(used.has(i))continue
  const indices=groups[i]?groups.flatMap((g,n)=>g===groups[i]&&!used.has(n)?[n]:[]):[i]
  indices.forEach(n=>used.add(n))
  result.push({indices,superset:indices.length>1})
 }
 return result
}
export function setSequence(session:Session) {
 const exercises=session.exercises,sequence:{exercise:Session['exercises'][number];record:Session['exercises'][number]['records'][number];index:number;superset:boolean}[]=[]
 for(const {indices,superset} of blocks(session)){
  const length=Math.max(...indices.map(n=>exercises[n].records.length))
  for(let r=0;r<length;r++)for(const n of indices){const record=exercises[n].records[r];if(record)sequence.push({exercise:exercises[n],record,index:r,superset})}
 }
 return sequence
}
export function nextSet(session:Session) {return setSequence(session).find(s=>s.record.status==='draft')}
/** Номер блока, в котором лежит упражнение; -1 если не найдено. */
export function blockOf(session:Session,exerciseId:string) {
 return blocks(session).findIndex(b=>b.indices.some(n=>session.exercises[n]?.id===exerciseId))
}
export function scrollToSet(id:string){document.getElementById(`set-${id}`)?.scrollIntoView({block:'center',behavior:'instant'})}
