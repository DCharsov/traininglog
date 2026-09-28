import { useState, type ReactNode } from 'react'
import { ChevronRight } from 'lucide-react'
import { nextDay } from './workoutFlow'
import { exerciseName } from './exerciseLibrary'
import { Sheet } from './Sheet'
import type { Program, Session } from './domain'
type Props={programs:Program[];program?:Program;sessions:Session[];disabled:boolean;restToday:boolean;onSelect:(id:string)=>void;onStart:(program:Program,day:Program['days'][number])=>void;onCreate:()=>void;seeds:ReactNode}
const load=(d:Program['days'][number])=>({exercises:d.exercises.filter(e=>!e.optionalWeekly).length,sets:d.exercises.filter(e=>!e.optionalWeekly).reduce((n,e)=>n+e.sets*(e.unilateral?2:1),0)})
export default function TodayScreen({programs,program,sessions,disabled,restToday,onSelect,onStart,onCreate,seeds}:Props) {
 const [preview,setPreview]=useState<string|null>(null)
 const suggested=program?.days.some(d=>!d.archivedAt)?nextDay(program,sessions):null,day=program?.days.find(d=>d.id===preview&&!d.archivedAt)
 const latest=sessions.filter(s=>s.status==='completed'&&!s.deletedAt).sort((a,b)=>b.startedAt.localeCompare(a.startedAt))[0]
 const lastProgram=latest?programs.find(p=>p.id===latest.programId):undefined
 const lastDay=lastProgram?.days.find(d=>d.id===latest?.dayId&&!d.archivedAt)
 const repeatable=lastProgram&&lastDay&&lastDay.id!==suggested?.day.id?{program:lastProgram,day:lastDay}:null
 if(!program)return <section className="card empty"><h2>Начните с программы</h2><p>Выберите готовую программу или составьте свою.</p>{seeds}<button className="primary" disabled={disabled} onClick={onCreate}>Создать программу</button></section>
 return <>
  {programs.length>1?<label className="program-pick today-program">Текущая программа<select value={program.id} onChange={e=>{setPreview(null);onSelect(e.target.value)}}>{programs.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>:<p className="today-program">{program.name}</p>}
  {restToday&&<section className="card rest-day"><strong>Сегодня день отдыха</strong><small>Можно начать занятие, если планы изменились.</small></section>}
  {suggested&&<section className="card next-day"><span className="eyebrow">Следующая тренировка</span><h2>{suggested.day.name}</h2><p>{load(suggested.day).exercises} упражнений · {load(suggested.day).sets} подходов</p><button className="primary" disabled={disabled} onClick={()=>onStart(program,suggested.day)}>Начать предложенный день</button><button className="ghost" onClick={()=>setPreview(suggested.day.id)}>Посмотреть упражнения</button>
   {repeatable&&<button className="ghost" disabled={disabled} onClick={()=>onStart(repeatable.program,repeatable.day)}>Повторить: {repeatable.day.name}</button>}</section>}
  <section className="card"><h2>Другой день</h2>{!program.days.some(d=>!d.archivedAt)&&<p>Все дни в архиве. Верните нужный день в редакторе программы.</p>}<div className="day-list">{program.days.filter(d=>!d.archivedAt).map(d=>{const summary=load(d);return <button disabled={disabled} key={d.id} className="day-start" onClick={()=>setPreview(d.id)}><span><strong>{d.name}</strong><small>{summary.exercises} упражнений · {summary.sets} подходов</small></span><ChevronRight/></button>})}</div></section>
  {day&&<Sheet title={day.name} onClose={()=>setPreview(null)}><p>{load(day).exercises} упражнений · {load(day).sets} подходов</p><ol className="day-preview">{day.exercises.map(e=><li key={e.id}><strong>{exerciseName(e)}</strong><small>{e.sets} подходов{e.unilateral?' на сторону':''}{e.target?` · ${e.target} ${e.tracking==='duration'?'сек':'повт.'}`:''}{e.optionalWeekly?' · необязательно':''}</small></li>)}</ol><button className="primary" disabled={disabled} onClick={()=>{setPreview(null);onStart(program,day)}}>Начать тренировку</button></Sheet>}
 </>
}
