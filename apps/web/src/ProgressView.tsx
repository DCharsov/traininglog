import { useState } from 'react'
import { exerciseName } from './exerciseLibrary'
import { contexts, results, points, weeklySets, downloadCsv, type Point } from './progress'
import { sideNames, formatWeight, modes, type Session } from './domain'
import { chartCoordinates, chartDate, periodDates } from './progressChart'
import YearMap from './YearMap.tsx'
import MuscleVolume from './MuscleVolume.tsx'
import './management.css'

export type ProgressState={
 chosen:string;from:string;to:string;minimum:number;load:string;side:'left'|'right'
 preset:'all'|'month'|'quarter'|'custom'
 selectedPoints:{load:string;reps:string;weekly:string}
}
export const initialProgressState=():ProgressState=>({chosen:'',from:'',to:'',minimum:1,load:'',side:'left',preset:'all',selectedPoints:{load:'',reps:'',weekly:''}})
type ChartProps={data:Point[];label:string;format:(n:number)=>string;selected:string;onSelect:(id:string)=>void;onOpen?:(id:string)=>void}

export function Chart({data,label,format,selected,onSelect,onOpen}:ChartProps) {
 if(!data.length)return <p>За выбранный период подходов нет. Попробуйте другой период или вес.</p>
 const width=360,height=240,layout=chartCoordinates(data,width,height)
 const active=data.find(p=>p.id===selected)??data[data.length-1]
 const dates=data.map(p=>p.date).sort(),firstDate=dates[0],lastDate=dates[dates.length-1]
 const ticks=layout.max===layout.min?[layout.max]:[layout.max,(layout.min+layout.max)/2,layout.min]
 return <div className="progress-chart-block">
  <svg className="progress-chart readable-chart" viewBox={'0 0 '+width+' '+height} role="group" aria-label={label}>
   <title>{label}. Выберите точку, чтобы увидеть результат.</title>
   {ticks.map((value,i)=>{const y=ticks.length===1?(layout.top+height-layout.bottom)/2:layout.top+i/(ticks.length-1)*(height-layout.top-layout.bottom);return <g key={i}><line x1={layout.left} x2={width-layout.right} y1={y} y2={y} stroke="#2c3644"/><text x={layout.left-10} y={y+5} textAnchor="end">{format(value)}</text></g>})}
   <text x={layout.left} y={height-10} textAnchor="start">{chartDate(firstDate)}</text>
   {lastDate!==firstDate&&<text x={width-layout.right} y={height-10} textAnchor="end">{chartDate(lastDate)}</text>}
   <polyline points={layout.points.map(p=>p.x+','+p.y).join(' ')} fill="none" stroke="#c4f16b" strokeWidth="3"/>
   {layout.points.map(({point:p,x,y},i)=><g className="progress-point" role="button" tabIndex={p.id===active.id?0:-1} aria-label={p.date+': '+format(p.value)+' · '+p.name} aria-pressed={p.id===active.id} key={p.id} onClick={()=>onSelect(p.id)} onKeyDown={e=>{
    if(e.key==='Enter'||e.key===' '){e.preventDefault();onSelect(p.id)}
    if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();const index=Math.max(0,Math.min(data.length-1,i+(e.key==='ArrowRight'?1:-1)));onSelect(data[index].id);e.currentTarget.ownerSVGElement?.querySelectorAll<SVGGElement>('.progress-point')[index]?.focus()}
   }}><circle cx={x} cy={y} r="32" fill="transparent"/><circle className="point-dot" cx={x} cy={y} r={p.id===active.id?7:4} fill="#c4f16b" pointerEvents="none"/></g>)}
  </svg>
  <p className="chart-current" aria-live="polite">{active.date} · <strong>{format(active.value)}</strong></p>
  <div className="chart-readout">
   <label>Точка графика<select value={active.id} onChange={e=>onSelect(e.target.value)}>{data.map(p=><option key={p.id} value={p.id}>{p.date} · {format(p.value)}</option>)}</select></label>
   {onOpen&&<button className="ghost" onClick={()=>onOpen(active.id)}>Открыть тренировку</button>}
  </div>
 </div>
}

type Props={sessions:Session[];onOpen:(id:string)=>void;state?:ProgressState;onStateChange?:(next:ProgressState)=>void}
export default function Progress({sessions,onOpen,state:controlled,onStateChange}:Props) {
 const [local,setLocal]=useState(initialProgressState),state=controlled??local
 const update=(patch:Partial<ProgressState>)=>{const next={...state,...patch};setLocal(next);onStateChange?.(next)}
 const selectPoint=(kind:keyof ProgressState['selectedPoints'],id:string)=>update({selectedPoints:{...state.selectedPoints,[kind]:id}})
 const options=contexts(sessions),{chosen,from,to,minimum,load,side}=state
 const selected=options.find(o=>o.key===chosen)??options[0]
 if(!selected)return <section className="card empty"><h2>Прогресс появится после тренировки</h2><p>Завершите тренировку с хотя бы одним рабочим подходом.</p></section>
 const invalid=!!from&&!!to&&from>to
 const rows=invalid?[]:results(sessions,{from,to,context:selected.key,side:selected.exercise.unilateral?side:undefined})
 const mode=selected.exercise.mode,body=mode==='BodyweightOnly',assisted=mode==='AssistedBodyweight',duration=selected.exercise.tracking==='duration'
 const weights=[...new Set(rows.flatMap(r=>r.record.loadGrams===null?[]:[r.record.loadGrams]))].sort((a,b)=>a-b)
 const weight=weights.includes(Number(load))&&load!==''?Number(load):weights[weights.length-1]??null
 const loadPoints=points(rows,'load',minimum),repPoints=points(rows,duration?'duration':'reps',1,weight),weeks=weeklySets(rows)
 const best=loadPoints.length?loadPoints.reduce((n,p)=>assisted?Math.min(n,p.value):Math.max(n,p.value),loadPoints[0].value):null
 const profileLabels=options.map(o=>exerciseName(o.exercise)+' · '+o.exercise.equipment+' · '+modes[o.exercise.mode]+(o.exercise.tracking==='duration'?' · секунды':'')+(o.exercise.unilateral?' · по сторонам':''))
 const profileLabel=(i:number)=>{const label=profileLabels[i];if(profileLabels.filter(x=>x===label).length===1)return label;const since=results(sessions,{context:options[i].key})[0]?.session.localDate;return label+' · с '+since+' · вариант '+(profileLabels.slice(0,i).filter(x=>x===label).length+1)}
 const preset=(value:ProgressState['preset'])=>update({preset:value,...(value==='all'?{from:'',to:''}:periodDates(value==='month'?1:3))})
 return <>
  <MuscleVolume sessions={sessions}/>
  <YearMap sessions={sessions}/>
  <section className="card">
   <label>Упражнение и профиль<select value={selected.key} onChange={e=>update({chosen:e.target.value,load:'',selectedPoints:{load:'',reps:'',weekly:''}})}>{options.map((o,i)=><option key={o.key} value={o.key}>{profileLabel(i)}</option>)}</select></label>
   <p className="progress-profile-help"><strong>{exerciseName(selected.exercise)}</strong><span>{selected.exercise.equipment} · {modes[mode]}</span></p>
   {selected.exercise.unilateral&&<label className="stacked">Сторона для сравнения<select value={side} onChange={e=>update({side:e.target.value as 'left'|'right'})}><option value="left">Левая</option><option value="right">Правая</option></select></label>}
   <div className="period-presets" role="group" aria-label="Период прогресса"><button aria-pressed={state.preset==='month'} onClick={()=>preset('month')}>Месяц</button><button aria-pressed={state.preset==='quarter'} onClick={()=>preset('quarter')}>3 месяца</button><button aria-pressed={state.preset==='all'} onClick={()=>preset('all')}>Всё время</button></div>
   <details><summary>Период и выгрузка</summary>
    <div className="form-grid">
     <label>С даты<input type="date" value={from} onChange={e=>update({from:e.target.value,preset:'custom'})}/></label>
     <label>По дату<input type="date" value={to} onChange={e=>update({to:e.target.value,preset:'custom'})}/></label>
    </div>
    {invalid&&<p role="alert">Начало периода должно быть не позже окончания.</p>}
    <button className="ghost" onClick={()=>downloadCsv(sessions.filter(s=>(!from||s.localDate>=from)&&(!to||s.localDate<=to)))} disabled={invalid}>CSV тренировок за период</button>
    <p>Выгрузка содержит все упражнения за выбранные даты.</p>
   </details>
  </section>
  <div className="progress-stats">
   <section className="card"><span>Рабочие подходы</span><strong>{rows.length}</strong></section>
   <section className="card"><span>Занятия</span><strong>{new Set(rows.map(r=>r.session.id)).size}</strong></section>
   <section className="card"><span>{duration?'Дольше всего':body?'Больше повторов':assisted?'Меньше помощи':'Лучший вес'}</span>
    <strong>{duration?(repPoints.length?Math.max(...repPoints.map(p=>p.value))+' сек':'—'):body?(rows.length?rows.reduce((n,r)=>Math.max(n,r.record.count!),0):'—'):best===null?'—':formatWeight(best)+' кг'}</strong></section>
  </div>
  {!body&&!duration&&<section className="card">
   <h2>{assisted?'Помощь тренажёра':'Записанный вес'}</h2>
   {assisted&&<p>Меньше помощи при том же числе повторов — выше результат.</p>}
   <label>Минимум повторений в подходе<input type="number" min="1" max="1000" value={minimum} onChange={e=>update({minimum:Math.max(1,Math.min(1000,Number(e.target.value)||1))})}/></label>
   <Chart data={loadPoints} label="Вес по тренировкам" format={v=>formatWeight(v)+' кг'} selected={state.selectedPoints.load} onSelect={id=>selectPoint('load',id)} onOpen={onOpen}/>
  </section>}
  <section className="card">
   <h2>{duration?'Длительность':body?'Повторения':'Повторения при одном весе'}</h2>
   {!body&&<label>{assisted?'Уровень помощи':'Выбранный вес'}<select value={weight??''} onChange={e=>update({load:e.target.value})}>{!weights.length&&<option value="">Нет данных</option>}{weights.map(w=><option value={w} key={w}>{formatWeight(w)} кг</option>)}</select></label>}
   <Chart data={repPoints} label={duration?'Длительность по тренировкам':'Повторения по тренировкам'} format={v=>v.toLocaleString('ru-RU',{maximumFractionDigits:1})+' '+(duration?'сек':'повт.')} selected={state.selectedPoints.reps} onSelect={id=>selectPoint('reps',id)} onOpen={onOpen}/>
  </section>
  <section className="card"><h2>Подходы по неделям</h2><Chart data={weeks} label="Выполненные подходы по неделям" format={v=>v.toLocaleString('ru-RU',{maximumFractionDigits:1})+' подх.'} selected={state.selectedPoints.weekly} onSelect={id=>selectPoint('weekly',id)}/></section>
  <section className="card"><h2>Все подходы</h2><div className="progress-row-list">
   {!rows.length?<p>За период записей нет.</p>:rows.slice().reverse().map(r=><button className="day-start" key={r.session.id+'-'+r.exercise.id+'-'+r.record.id} onClick={()=>onOpen(r.session.id)}>
    <span><strong>{r.session.localDate} · {r.session.name}</strong><small>Подход {r.index+1}: {body?'':formatWeight(r.record.loadGrams)+' кг × '}{duration?r.record.durationSeconds+' сек':r.record.count+' повторов'}{selected.exercise.unilateral?' · '+sideNames[r.record.side??'both']:''}{r.record.rir?' · RIR '+r.record.rir:''}</small></span></button>)}
  </div></section>
 </>
}
