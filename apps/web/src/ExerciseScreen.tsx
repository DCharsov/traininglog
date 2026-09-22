import { useState } from 'react'
import { ChevronLeft } from 'lucide-react'
import { Chart } from './ProgressView'
import ExerciseGuide from './ExerciseGuide'
import { Sheet } from './Sheet'
import { exerciseName, guideFor } from './exerciseLibrary'
import { contexts, points, results, type ResultRow } from './progress'
import { epleyMax } from './progression'
import { formatWeight, modes, sideNames, type Session } from './domain'
import './management.css'

type Props={sessions:Session[];contextKey:string;onOpen:(id:string)=>void;onBack:()=>void}
const short=(date:string)=>new Date(date+'T12:00:00').toLocaleDateString('ru-RU',{day:'numeric',month:'short'})

export default function ExerciseScreen({sessions,contextKey,onOpen,onBack}:Props) {
 const [guide,setGuide]=useState(false),[selected,setSelected]=useState('')
 const option=contexts(sessions).find(item=>item.key===contextKey)
 const back=<button type="button" className="ghost" onClick={onBack}><ChevronLeft size={18}/>Назад</button>
 if(!option)return <><div className="actions">{back}</div><section className="card empty"><h2>Записей пока нет</h2><p>Здесь появится история упражнения после первой завершённой тренировки.</p></section></>
 const exercise=option.exercise
 const assisted=exercise.mode==='AssistedBodyweight',body=exercise.mode==='BodyweightOnly',duration=exercise.tracking==='duration'
 const rows=results(sessions,{context:contextKey})
 const loads=rows.flatMap(row=>row.record.loadGrams===null?[]:[row.record.loadGrams])
 const counts=rows.flatMap(row=>{const value=duration?row.record.durationSeconds:row.record.count;return value===null||value===undefined?[]:[value]})
 const bestLoad=loads.length?assisted?Math.min(...loads):Math.max(...loads):null
 const bestCount=counts.length?Math.max(...counts):null
 const bestMax=body||duration||assisted?null:rows.reduce((best,row)=>row.record.loadGrams===null||row.record.count===null?best:Math.max(best,epleyMax(row.record.loadGrams,row.record.count)),0)
 const chart=body||duration?points(rows,duration?'duration':'reps',1,null):points(rows,'load',1)
 const recent=[...rows.reduce((map,row)=>map.set(row.session.id,[...(map.get(row.session.id)??[]),row]),new Map<string,ResultRow[]>())].slice(-5).reverse()
 const values=(row:ResultRow)=>`${body?'':`${formatWeight(row.record.loadGrams)} кг × `}${duration?`${row.record.durationSeconds} сек`:row.record.count}${exercise.unilateral?` ${sideNames[row.record.side??'both'].toLocaleLowerCase('ru')}`:''}`
 return <>
  <div className="actions">{back}{(guideFor(exercise)||exercise.sourceNote)&&<button type="button" className="ghost" onClick={()=>setGuide(true)}>Как выполнять</button>}</div>
  <section className="card">
   <h2>{exerciseName(exercise)}</h2>
   <p className="exercise-meta">{exercise.equipment} · {modes[exercise.mode]}{exercise.unilateral?' · по сторонам':''}</p>
  </section>
  <div className="progress-stats">
   <section className="card"><span>{duration?'Дольше всего':body?'Больше повторов':assisted?'Меньше помощи':'Лучший вес'}</span>
    <strong>{duration||body?bestCount===null?'—':`${bestCount}${duration?' сек':''}`:bestLoad===null?'—':`${formatWeight(bestLoad)} кг`}</strong></section>
   <section className="card"><span>Расчётный максимум</span><strong>{bestMax?`${formatWeight(Math.round(bestMax))} кг`:'—'}</strong></section>
   <section className="card"><span>Занятий</span><strong>{new Set(rows.map(row=>row.session.id)).size}</strong></section>
  </div>
  <section className="card">
   <h2>{duration?'Длительность':body?'Повторения':assisted?'Помощь тренажёра':'Вес'}</h2>
   <Chart data={chart} label={`${exerciseName(exercise)} по тренировкам`} selected={selected} onSelect={setSelected} onOpen={onOpen}
    format={value=>duration?`${value} сек`:body?`${value} повт.`:`${formatWeight(value)} кг`}/>
  </section>
  <section className="card"><h2>Последние занятия</h2><div className="progress-row-list">
   {!recent.length?<p>Записей пока нет.</p>:recent.map(([id,sets])=><button type="button" className="day-start" key={id} onClick={()=>onOpen(id)}>
    <span><strong>{short(sets[0].session.localDate)} · {sets[0].session.name}</strong><small>{sets.map(values).join(' · ')}</small></span>
   </button>)}
  </div></section>
  {guide&&<Sheet title={`Как выполнять: ${exerciseName(exercise)}`} onClose={()=>setGuide(false)}>
   <div className="focus-guide" ref={node=>{node?.querySelector('details')?.setAttribute('open','')}}><ExerciseGuide exercise={exercise}/></div>
   {exercise.sourceNote&&<p className="guide-note">{exercise.sourceNote}</p>}
  </Sheet>}
 </>
}
