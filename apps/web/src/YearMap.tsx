import { useEffect, useRef } from 'react'
import { monthLabels, yearCells, YEAR_WEEKS } from './yearMap'
import type { Session } from './domain'
import './calendar.css'

const monthShort=(month:string)=>new Date(month+'-01T12:00:00').toLocaleDateString('ru-RU',{month:'short'}).replace('.','')
const title=(date:string,names:string[])=>`${new Date(date+'T12:00:00').toLocaleDateString('ru-RU',{day:'numeric',month:'long'})}${names.length?` · ${names.join(', ')}`:''}`

export default function YearMap({sessions}:{sessions:Session[]}) {
 const strip=useRef<HTMLDivElement>(null)
 const cells=yearCells(sessions)
 const labels=monthLabels(cells)
 const total=cells.reduce((sum,cell)=>sum+cell.count,0)
 // Текущая неделя интереснее прошлогодней: показываем правый край.
 useEffect(()=>{if(strip.current)strip.current.scrollLeft=strip.current.scrollWidth},[])
 return <section className="card">
  <h2>Год тренировок</h2>
  <div className="year-strip" ref={strip}>
   <div className="year-inner" role="img" aria-label={`Карта активности за год: ${total} занятий`}>
    <div className="year-months">{labels.map(label=><span key={label.month} style={{gridColumn:`${label.column+1} / span ${label.span}`}}>{label.span>2?monthShort(label.month):''}</span>)}</div>
    <div className="year-grid" style={{gridTemplateColumns:`repeat(${YEAR_WEEKS},var(--year-cell))`}}>
     {cells.map(cell=><i key={cell.date} className={cell.count?cell.count>1?'busy':'done':''} title={title(cell.date,cell.names)}/>)}
    </div>
   </div>
  </div>
  <p className="calendar-summary">{total} занятий за год</p>
 </section>
}
