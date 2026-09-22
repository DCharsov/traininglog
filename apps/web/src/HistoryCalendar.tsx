import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Sheet } from './Sheet'
import { completedSets, dayMark, dayName, monthCells, monthName, shiftMonth, type DayCell } from './calendarMonth'
import type { CalendarEntry, Session } from './domain'
import './calendar.css'

const weekdays=['Пн','Вт','Ср','Чт','Пт','Сб','Вс']
export type RestAction='plan'|'toggle'|'remove'
type Props={
 sessions:Session[];calendar:CalendarEntry[];month:string;disabled:boolean
 onMonth:(month:string)=>void;onOpen:(id:string)=>void;onRest:(date:string,action:RestAction)=>void
}
const state=(cell:DayCell)=>cell.sessions.length?cell.sessions.map(s=>s.status==='cancelled'?`${s.name} — отменена`:s.name).join(', ')
 :cell.rest?cell.rest.status==='completed'?'отдых отмечен':'отдых запланирован':'нет записей'

export default function HistoryCalendar({sessions,calendar,month,disabled,onMonth,onOpen,onRest}:Props) {
 const [picked,setPicked]=useState<string|null>(null)
 const {blanks,cells}=monthCells(month,sessions,calendar)
 const open=cells.find(cell=>cell.date===picked)
 const workouts=cells.reduce((total,cell)=>total+cell.sessions.length,0)
 const sets=cells.reduce((total,cell)=>total+cell.sessions.reduce((n,session)=>n+completedSets(session),0),0)
 const pick=(cell:DayCell)=>{if(cell.sessions.length===1&&!cell.rest)onOpen(cell.sessions[0].id);else setPicked(cell.date)}
 const rest=(action:RestAction)=>{if(open){onRest(open.date,action);setPicked(null)}}
 return <section className="card calendar">
  <div className="calendar-head">
   <button type="button" className="icon" aria-label="Предыдущий месяц" onClick={()=>onMonth(shiftMonth(month,-1))}><ChevronLeft size={22}/></button>
   <strong>{monthName(month)}</strong>
   <button type="button" className="icon" aria-label="Следующий месяц" onClick={()=>onMonth(shiftMonth(month,1))}><ChevronRight size={22}/></button>
  </div>
  <div className="calendar-grid">
   {weekdays.map(day=><span className="calendar-weekday" key={day}>{day}</span>)}
   {Array.from({length:blanks},(_,index)=><span key={`blank-${index}`}/>)}
   {cells.map(cell=>{
    const workout=cell.sessions.find(session=>session.status==='completed')??cell.sessions[0]
    const classes=['calendar-cell',workout?workout.status==='cancelled'?'cancelled':'workout':'',cell.rest?cell.rest.status==='completed'?'rest-done':'rest':'',cell.today?'today':''].filter(Boolean).join(' ')
    return <button type="button" key={cell.date} className={classes} aria-label={`${dayName(cell.date)} · ${state(cell)}`} onClick={()=>pick(cell)}>
     <span>{cell.day}</span>{workout&&<small>{dayMark(workout.name)}</small>}
    </button>
   })}
  </div>
  <p className="calendar-summary">{workouts} занятий · {sets} подходов</p>
  {open&&<Sheet title={dayName(open.date)} onClose={()=>setPicked(null)}>
   {open.sessions.map(session=><button type="button" key={session.id} onClick={()=>onOpen(session.id)}>
    {session.name} · {completedSets(session)} подходов{session.status==='cancelled'?' · отменена':''}
   </button>)}
   {open.rest
    ?<><button type="button" disabled={disabled} onClick={()=>rest('toggle')}>{open.rest.status==='planned'?'Отметить отдых':'Вернуть в план'}</button>
      <button type="button" className="ghost" disabled={disabled} onClick={()=>rest('remove')}>Убрать отдых</button></>
    :!open.sessions.length&&<button type="button" disabled={disabled} onClick={()=>rest('plan')}>Запланировать отдых</button>}
  </Sheet>}
 </section>
}
