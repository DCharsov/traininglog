import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { ChevronDown, ChevronLeft, ChevronRight, ListChecks, MoreHorizontal, Plus } from 'lucide-react'
import { nextSet } from './workoutFlow'
import { exerciseName, guideFor } from './exerciseLibrary'
import { contextKey } from './progress'
import { sessionRecords } from './records'
import { recordHit } from './haptics'
import { emptySet, formatWeight, previous, sideNames, type Program, type Session, type SetRecord } from './domain'
import type { SetConfirmResult } from './setValidation'
import ExerciseGuide from './ExerciseGuide'
import ExerciseSwap from './ExerciseSwap'
import { EquipmentPicker } from './ManageData'
import SetRow, { type Field } from './SetRow'
import { Sheet } from './Sheet'
import { moveItem, swapExercise } from './workoutEditing'
import { matchingPreviousSet, precedingCompletedSet, resolveWorkoutSelection, type WorkoutSelection } from './workoutUx'
import { exerciseHistory, suggestSet } from './progression'
import './workout.css'

type Exercised=Session['exercises'][number]
type Props={
 session:Session; sessions:Session[]; programs:Program[]; disabled:boolean; editorKey:number
 run:(action:()=>Promise<unknown>,message?:string)=>Promise<boolean>
 mutate:(fn:(s:Session)=>boolean|void)=>void
 draft:(sessionId:string,exerciseId:string,setId:string,patch:Partial<SetRecord>)=>void
 confirm:(exerciseId:string,setId:string)=>Promise<SetConfirmResult>
 change:(id:string,revision:number,fn:(s:Session)=>boolean|void)=>Promise<unknown>
 finish:()=>void; cancel:()=>void
 onCollapse?:()=>void; restTimer?:ReactNode; onEditSet?:(exerciseId:string,setId:string)=>void; onOpenExercise?:(key:string)=>void
}
const selectionKey=(id:string)=>`traininglog-workout-selection:${id}`
function savedSelection(id:string):WorkoutSelection|null {
 try{const value=JSON.parse(sessionStorage.getItem(selectionKey(id))??'null') as WorkoutSelection|null;return value&&typeof value.exerciseId==='string'&&typeof value.setId==='string'?value:null}catch{return null}
}
const statusText=(record:SetRecord)=>record.status==='completed'?'Выполнен':record.status==='skipped'?'Пропущен':'Осталось'
const setValues=(exercise:Exercised,record:SetRecord)=>`${exercise.mode==='BodyweightOnly'?'':`${record.weight||'—'} кг × `}${exercise.tracking==='duration'?`${record.duration||'—'} сек`:`${record.reps||'—'} повт.`}`

export default function WorkoutScreen(props:Props) {
 const {session,sessions,programs,disabled,editorKey,run,mutate,draft,confirm,change,finish,cancel,onCollapse,restTimer,onEditSet,onOpenExercise}=props
 const active=session.status==='active'
 const [selection,setSelection]=useState<WorkoutSelection|null>(()=>savedSelection(session.id))
 const [overview,setOverview]=useState(false),[menu,setMenu]=useState<string|null>(null),[swapping,setSwapping]=useState<string|null>(null)
 const [guide,setGuide]=useState<string|null>(null),[equipment,setEquipment]=useState<string|null>(null)
 const [pad,setPad]=useState<Field|null>(null)
 const selected=resolveWorkoutSelection(session,selection),next=nextSet(session)
 const selectedExerciseId=selected?.exercise.id,selectedSetId=selected?.record.id
 const best=useMemo(()=>sessionRecords(sessions,session),[sessions,session])
 const records=session.exercises.flatMap(e=>e.records),done=records.filter(r=>r.status==='completed').length,skipped=records.filter(r=>r.status==='skipped').length,total=records.length

 useEffect(()=>{
  if(!active||!selectedExerciseId||!selectedSetId)return
  if(selection?.exerciseId===selectedExerciseId&&selection.setId===selectedSetId)return
  try{sessionStorage.setItem(selectionKey(session.id),JSON.stringify({exerciseId:selectedExerciseId,setId:selectedSetId}))}catch{/* Selection is optional if storage is unavailable. */}
 },[session.id,active,selectedExerciseId,selectedSetId,selection])

 const seen=useRef<Set<string>|null>(null)
 useEffect(()=>{
  const ids=new Set(best.keys())
  const known=seen.current
  seen.current=ids
  // При открытии записи отклика нет: вибрируем только на рекорд, поставленный сейчас.
  if(known&&active&&[...ids].some(id=>!known.has(id)))recordHit()
 },[best,active])

 const select=(exerciseId:string,setId:string)=>{
  const value={exerciseId,setId}
  try{sessionStorage.setItem(selectionKey(session.id),JSON.stringify(value))}catch{/* Selection is optional if storage is unavailable. */}
  setSelection(value);setPad(null);setOverview(false)
 }
 const selectExercise=(index:number)=>{
  const exercise=session.exercises[index]
  const record=exercise?.records.find(r=>r.status==='draft')??exercise?.records[0]
  if(exercise&&record)select(exercise.id,record.id)
 }
 const advance=(exerciseId:string,setId:string,status:'completed'|'skipped')=>{
  const updated=structuredClone(session)
  const record=updated.exercises.find(e=>e.id===exerciseId)?.records.find(r=>r.id===setId)
  if(record)record.status=status
  const following=nextSet(updated)
  if(following)select(following.exercise.id,following.record.id)
 }
 const saveSet=async(exerciseId:string,setId:string)=>{
  const result=await confirm(exerciseId,setId)
  if(result.ok)advance(exerciseId,setId,'completed')
  return result
 }
 const renderSet=(exercise:Exercised,record:SetRecord,index:number)=>
  <SetRow key={`${session.id}-${record.id}-${editorKey}`} total={exercise.records.length} best={best.get(record.id)} suggestion={active?suggestSet(exercise,record,exerciseHistory(sessions,session,exercise))??undefined:undefined}
   repeatSet={active?precedingCompletedSet(exercise,record):undefined} record={record} index={index} exercise={exercise} bodyweight={exercise.mode==='BodyweightOnly'} disabled={disabled||!active}
   patch={patch=>draft(session.id,exercise.id,record.id,patch)} confirm={()=>saveSet(exercise.id,record.id)}
   pad={active?pad:null} onPad={setPad} current={active} onEquipmentError={()=>setEquipment(exercise.id)}
   skip={()=>{mutate(s=>{const r=s.exercises.find(e=>e.id===exercise.id)?.records.find(r=>r.id===record.id);if(r)r.status='skipped'});advance(exercise.id,record.id,'skipped')}}
   edit={()=>mutate(s=>{const r=s.exercises.find(e=>e.id===exercise.id)?.records.find(r=>r.id===record.id);if(r)r.status='draft'})}
   onHistoryEdit={!active&&onEditSet?()=>onEditSet(exercise.id,record.id):undefined}/>
 const menuExercise=session.exercises.find(e=>e.id===menu),menuIndex=menuExercise?session.exercises.indexOf(menuExercise):-1
 const guideExercise=session.exercises.find(e=>e.id===guide),equipmentExercise=session.exercises.find(e=>e.id===equipment)
 const currentIndex=selected?session.exercises.indexOf(selected.exercise):0
 const prev=selected?previous(sessions,session,selected.exercise):null
 const previousRecord=selected?matchingPreviousSet(selected.exercise,selected.record,prev?.exercise):undefined

 if(!active)return <div className="workout-history">
  <section className="workout-heading"><h2>{session.name}</h2><p>{session.localDate} · {session.status==='cancelled'?'Отменена':'Завершена'}</p><p>{done} из {total} подходов выполнено{skipped?` · ${skipped} пропущено`:''}</p></section>
  {session.exercises.map(exercise=><section className="card exercise" key={exercise.id}>
   <h2>{onOpenExercise?<button type="button" className="exercise-link" onClick={()=>onOpenExercise(contextKey(exercise))}>{exerciseName(exercise)}<ChevronRight size={18}/></button>:exerciseName(exercise)}</h2>
   <p className="exercise-meta">{exercise.equipment}</p>{exercise.records.map((record,index)=>renderSet(exercise,record,index))}</section>)}
 </div>

 return <div className={`workout-focus ${pad?'pad-open':''}`}>
  <header className="workout-focus-header">
   <div className="focus-title"><h1>{session.name}</h1>{onCollapse&&<button type="button" className="ghost collapse-workout" onClick={onCollapse}><ChevronDown size={18}/>Свернуть</button>}</div>
   <div className="focus-navigation">
    <button type="button" className="icon" aria-label="Предыдущее упражнение" disabled={currentIndex<=0} onClick={()=>selectExercise(currentIndex-1)}><ChevronLeft size={22}/></button>
    <button type="button" className="workout-overview-button" onClick={()=>setOverview(true)} aria-label="Обзор тренировки"><ListChecks size={20}/><span>Упражнение {currentIndex+1} из {session.exercises.length}<small>{done} из {total} подходов выполнено{skipped?` · ${skipped} пропущено`:''}</small></span></button>
    <button type="button" className="icon" aria-label="Следующее упражнение" disabled={currentIndex>=session.exercises.length-1} onClick={()=>selectExercise(currentIndex+1)}><ChevronRight size={22}/></button>
   </div>
   <div className="wk-bar" aria-hidden="true"><i style={{width:`${total?(done+skipped)/total*100:0}%`}}/></div>
  </header>

  {selected&&<section className="card exercise focus-exercise" key={selected.exercise.id}>
   <div className="exercise-head"><h2>{exerciseName(selected.exercise)}</h2><button type="button" className="icon" aria-label={`Действия: ${exerciseName(selected.exercise)}`} disabled={disabled} onClick={()=>setMenu(selected.exercise.id)}><MoreHorizontal size={20}/></button></div>
   <p className="exercise-meta">{selected.exercise.equipment}{selected.exercise.target?` · цель ${selected.exercise.target} ${selected.exercise.tracking==='duration'?'сек':'повт.'}`:''}</p>
   <div className="focus-exercise-tools">
    {(guideFor(selected.exercise)||selected.exercise.sourceNote)&&<button type="button" className="ghost" onClick={()=>setGuide(selected.exercise.id)}>Как выполнять</button>}
    {selected.exercise.requiresEquipment&&<button type="button" className={`ghost ${selected.exercise.mode==='Unspecified'?'equipment-required':''}`} onClick={()=>setEquipment(selected.exercise.id)}>{selected.exercise.mode==='Unspecified'?'Выбрать оборудование':'Оборудование'}</button>}
   </div>
   {previousRecord&&prev&&<p className="previous"><span>Прошлый раз · {new Date(prev.session.localDate+'T12:00:00').toLocaleDateString('ru-RU',{day:'numeric',month:'long'})}</span>{selected.exercise.mode==='BodyweightOnly'?'':`${formatWeight(previousRecord.loadGrams)} кг × `}{selected.exercise.tracking==='duration'?`${previousRecord.durationSeconds} сек`:previousRecord.count}</p>}
   {renderSet(selected.exercise,selected.record,selected.index)}
  </section>}

  {restTimer&&<div className="workout-rest">{restTimer}</div>}
  {next?(next.record.id!==selectedSetId||next.exercise.id!==selectedExerciseId)&&<div className="focus-next">
   <span>{next.superset?'Суперсет · по очереди':'Следующий подход'}<strong>{exerciseName(next.exercise)} · {next.index+1}{next.exercise.unilateral?` · ${sideNames[next.record.side??'both']}`:''}</strong></span>
   <button type="button" onClick={()=>select(next.exercise.id,next.record.id)}>К следующему подходу</button>
  </div>:<div className="workout-complete" role="status"><strong>Все подходы записаны</strong></div>}
  <button type="button" className={`${next?'ghost':'primary'} finish`} disabled={disabled} onClick={finish}>Завершить тренировку</button>

  {overview&&<Sheet title="Обзор тренировки" onClose={()=>setOverview(false)}>
   <p>{done} выполнено · {skipped} пропущено · {total-done-skipped} осталось</p>
   <div className="workout-overview">{session.exercises.map(exercise=><section key={exercise.id}>
    <h3>{exerciseName(exercise)}</h3>
    {exercise.records.map((record,index)=><button type="button" key={record.id} className={`overview-set ${record.status}`} aria-current={record.id===selectedSetId?'step':undefined} onClick={()=>select(exercise.id,record.id)}>
     <span>Подход {index+1}{exercise.unilateral?` · ${sideNames[record.side??'both']}`:''}{record.kind==='warmup'?' · разминка':''}<small>{setValues(exercise,record)}</small></span><span>{statusText(record)}</span>
    </button>)}
   </section>)}</div>
  </Sheet>}

  {guideExercise&&<Sheet title={`Как выполнять: ${exerciseName(guideExercise)}`} onClose={()=>setGuide(null)}>
   <div className="focus-guide" ref={node=>{node?.querySelector('details')?.setAttribute('open','')}}><ExerciseGuide exercise={guideExercise}/></div>
   {guideExercise.sourceNote&&<p className="guide-note">{guideExercise.sourceNote}</p>}
  </Sheet>}
  {equipmentExercise&&<Sheet title="Оборудование" onClose={()=>setEquipment(null)}>
   {equipmentExercise.records.some(r=>r.status==='completed')?<><p>Подходы уже записаны с этим оборудованием. Чтобы продолжить на другом, добавьте замену упражнения.</p><button type="button" disabled={disabled} onClick={()=>{setSwapping(equipmentExercise.id);setEquipment(null)}}>Заменить упражнение</button></>:<fieldset disabled={disabled}><EquipmentPicker exercise={equipmentExercise} onChange={fields=>mutate(s=>{const exercise=s.exercises.find(e=>e.id===equipmentExercise.id);if(!exercise)return;if(exercise.records.some(r=>r.status==='completed'))throw new Error('Для смены оборудования после записи используйте замену упражнения.');Object.assign(exercise,fields)})}/></fieldset>}
   <button type="button" onClick={()=>setEquipment(null)}>Вернуться к подходу</button>
  </Sheet>}
  {swapping&&<Sheet title="Заменить на сегодня" onClose={()=>setSwapping(null)}>
   {session.exercises.find(e=>e.id===swapping)&&<ExerciseSwap original={session.exercises.find(e=>e.id===swapping)!} programs={programs} disabled={disabled} onCancel={()=>setSwapping(null)} onSave={async replacement=>{const ok=await run(()=>change(session.id,-1,s=>{swapExercise(s,swapping,replacement)}),'Замена сохранена только в этой тренировке.');if(ok)setSwapping(null);return ok}}/>}
  </Sheet>}
  {menuExercise&&<Sheet title={exerciseName(menuExercise)} onClose={()=>setMenu(null)}>
   <button type="button" disabled={disabled} onClick={()=>{setSwapping(menuExercise.id);setMenu(null)}}>Заменить на сегодня</button>
   <button type="button" disabled={disabled||menuIndex<=0} aria-label={`Переместить ${exerciseName(menuExercise)} выше`} onClick={()=>{mutate(s=>{moveItem(s.exercises,s.exercises.findIndex(e=>e.id===menuExercise.id),-1)});setMenu(null)}}>Переместить выше</button>
   <button type="button" disabled={disabled||menuIndex>=session.exercises.length-1} aria-label={`Переместить ${exerciseName(menuExercise)} ниже`} onClick={()=>{mutate(s=>{moveItem(s.exercises,s.exercises.findIndex(e=>e.id===menuExercise.id),1)});setMenu(null)}}>Переместить ниже</button>
   <button type="button" disabled={disabled} onClick={()=>{mutate(s=>{const exercise=s.exercises.find(e=>e.id===menuExercise.id);if(!exercise)return;const amount=exercise.unilateral?2:1;if(exercise.records.length+amount>100)throw new Error('Не более 100 подходов.');exercise.records.push({...emptySet(),...(exercise.unilateral?{side:'left' as const}:{})});if(exercise.unilateral)exercise.records.push({...emptySet(),side:'right'})});setMenu(null)}}><Plus size={16}/>{menuExercise.unilateral?'Добавить подход на обе стороны':'Добавить подход'}</button>
   <hr/><button type="button" className="ghost danger" disabled={disabled} onClick={()=>{setMenu(null);cancel()}}>Отменить тренировку</button>
  </Sheet>}
 </div>
}
