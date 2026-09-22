import type { CSSProperties } from 'react'
import { MUSCLE_NAMES } from './muscles'
import { weeklyMuscleVolume } from './muscleVolume'
import { muscleIds, type Session } from './domain'
import './calendar.css'

const LOW=10,HIGH=20
const amount=(value:number)=>value.toLocaleString('ru-RU',{maximumFractionDigits:1})

export default function MuscleVolume({sessions}:{sessions:Session[]}) {
 const {current,previous}=weeklyMuscleVolume(sessions)
 const rows=muscleIds.map(id=>({id,now:current.sets.get(id)??0,was:previous.sets.get(id)??0}))
  .filter(row=>row.now>0||row.was>0).sort((a,b)=>b.now-a.now||MUSCLE_NAMES[a.id].localeCompare(MUSCLE_NAMES[b.id]))
 const scale=Math.max(HIGH+4,...rows.map(row=>row.now))
 return <section className="card">
  <h2>Объём за неделю</h2>
  {!rows.length?<p>Подходы появятся после первой тренировки на этой неделе.</p>:<div>
   {rows.map(row=><div className="volume-row" key={row.id}>
    <span className="volume-name">{MUSCLE_NAMES[row.id]}</span>
    <span className="volume-count num">{amount(row.now)}{row.was?<small> / {amount(row.was)}</small>:null}</span>
    <span className="volume-track" style={{'--low':`${LOW/scale*100}%`,'--high':`${HIGH/scale*100}%`} as CSSProperties}>
     <i className={row.now>=LOW?'enough':''} style={{width:`${Math.min(100,row.now/scale*100)}%`}}/>
    </span>
   </div>)}
  </div>}
  <p className="volume-legend">Коридор 10–20 подходов в неделю. Вторым числом — прошлая неделя.</p>
  {current.unknown>0&&<p className="volume-legend">Без группы: {amount(current.unknown)} подходов — укажите группу мышц в редакторе программы.</p>}
 </section>
}
