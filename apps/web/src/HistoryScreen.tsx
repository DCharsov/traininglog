import { CalendarDays, ChevronRight } from 'lucide-react'
import HistoryCalendar, { type RestAction } from './HistoryCalendar'
import { completedSets, monthKey, monthName } from './calendarMonth'
import type { CalendarEntry, Program, Session } from './domain'
export type HistoryFilters={query:string;from:string;to:string;program:string;status:string;view?:'list'|'calendar';month?:string}
export const emptyHistoryFilters:HistoryFilters={query:'',from:'',to:'',program:'',status:''}
type Props={
 sessions:Session[];programs:Program[];calendar:CalendarEntry[];filters:HistoryFilters;disabled:boolean
 onFilters:(filters:HistoryFilters)=>void;onOpen:(id:string)=>void;onRest:(date:string,action:RestAction)=>void
}
export default function HistoryScreen({sessions,programs,calendar,filters,disabled,onFilters,onOpen,onRest}:Props) {
 const update=(patch:Partial<HistoryFilters>)=>onFilters({...filters,...patch})
 const view=filters.view??'list',month=filters.month??monthKey(new Date())
 const invalid=!!filters.from&&!!filters.to&&filters.from>filters.to
 const recorded=sessions.filter(s=>s.status!=='active'&&!s.archivedAt&&!s.deletedAt)
 const rows=recorded.filter(s=>(!filters.query||s.name.toLocaleLowerCase('ru').includes(filters.query.toLocaleLowerCase('ru')))&&(!filters.from||s.localDate>=filters.from)&&(!filters.to||s.localDate<=filters.to)&&(!filters.program||s.programId===filters.program)&&(!filters.status||s.status===filters.status)).sort((a,b)=>b.startedAt.localeCompare(a.startedAt))
 const groups=new Map<string,Session[]>()
 if(!invalid)for(const session of rows){const key=session.localDate.slice(0,7);groups.set(key,[...(groups.get(key)??[]),session])}
 const programOptions=new Map([...programs.map(p=>[p.id,p.name] as const),...sessions.filter(s=>!programs.some(p=>p.id===s.programId)).map(s=>[s.programId,'Архивная программа'] as const)])
 return <>
  <div className="history-view" role="group" aria-label="Вид истории">
   <button type="button" aria-pressed={view==='list'} onClick={()=>update({view:'list'})}>Список</button>
   <button type="button" aria-pressed={view==='calendar'} onClick={()=>update({view:'calendar'})}>Календарь</button>
  </div>
  {view==='calendar'?<HistoryCalendar sessions={recorded} calendar={calendar} month={month} disabled={disabled} onMonth={next=>update({month:next})} onOpen={onOpen} onRest={onRest}/>:<>
  <section className="card history-filters"><label>Поиск тренировки<input type="search" value={filters.query} onChange={e=>update({query:e.target.value})} placeholder="Название занятия"/></label>
   <details><summary>Фильтры истории</summary><div className="form-grid">
    <label>История с даты<input type="date" value={filters.from} onChange={e=>update({from:e.target.value})}/></label>
    <label>История по дату<input type="date" value={filters.to} onChange={e=>update({to:e.target.value})}/></label>
    <label>Программа в истории<select value={filters.program} onChange={e=>update({program:e.target.value})}><option value="">Все программы</option>{[...programOptions].map(([id,name])=><option value={id} key={id}>{name}</option>)}</select></label>
    <label>Статус тренировки<select value={filters.status} onChange={e=>update({status:e.target.value})}><option value="">Все статусы</option><option value="completed">Завершена</option><option value="cancelled">Отменена</option></select></label>
   </div><button className="ghost" onClick={()=>onFilters({...emptyHistoryFilters,view,month})}>Сбросить фильтры</button></details>
   {invalid&&<p role="alert">Начало периода должно быть не позже окончания.</p>}
  </section>
  {[...groups].map(([key,items])=><section key={key}><h2 className="month-heading">{monthName(key)}</h2>{items.map(s=><button className="card history-row" key={s.id} onClick={()=>onOpen(s.id)}><span className="history-date">{new Date(`${s.localDate}T12:00:00`).toLocaleDateString('ru-RU',{day:'numeric',month:'short'})}</span><span><strong>{s.name}</strong><small>{completedSets(s)} подходов{s.status==='cancelled'?' · отменена':''}</small></span><ChevronRight/></button>)}</section>)}
  {!rows.length&&!invalid&&<section className="card empty"><CalendarDays size={32}/><h2>{recorded.length?'Тренировки не найдены':'Здесь будет история'}</h2><p>{recorded.length?'Измените поиск или фильтры.':'Завершённые занятия появятся здесь.'}</p></section>}
  </>}
 </>
}
