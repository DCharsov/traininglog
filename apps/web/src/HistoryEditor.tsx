import { useRef, useState } from 'react'
import { exerciseName } from './exerciseLibrary'
import { confirmSet, type Session, type SetRecord, modes, sideNames } from './domain'
import { saveCorrection } from './historyCorrection'
import { useEditorDraft } from './editorDrafts'
import './management.css'

type Props={initial:Session;disabled:boolean;onClose:()=>void;initialExerciseId?:string;initialSetId?:string}
const toggleId=(current:Set<string>,id:string,open:boolean)=>{const next=new Set(current);if(open)next.add(id);else next.delete(id);return next}

export default function HistoryEditor({initial,disabled,onClose,initialExerciseId,initialSetId}:Props) {
 const {value:draft,setValue:setDraft,original:snapshot,ready,status,error:draftError,clear,flush}=useEditorDraft('history',initial)
 const firstExercise=initial.exercises.find(ex=>ex.id===initialExerciseId)??initial.exercises[0]
 const firstSet=firstExercise?.records.find(r=>r.id===initialSetId)??firstExercise?.records[0]
 const [openExercises,setOpenExercises]=useState(()=>new Set(firstExercise?[firstExercise.id]:[]))
 const [openSets,setOpenSets]=useState(()=>new Set(firstSet?[firstSet.id]:[]))
 const [error,setError]=useState(''),[errorSet,setErrorSet]=useState(''),[saving,setSaving]=useState(false)
 const form=useRef<HTMLFormElement>(null)
 const patch=(ei:number,ri:number,fields:Partial<SetRecord>)=>{setDraft(old=>{const next=structuredClone(old);Object.assign(next.exercises[ei].records[ri],fields);return next});setError('');setErrorSet('')}
 const changed=draft.exercises.reduce((count,ex)=>count+ex.records.filter(r=>JSON.stringify(r)!==JSON.stringify(snapshot.exercises.find(x=>x.id===ex.id)?.records.find(x=>x.id===r.id))).length,0)
 async function submit(){
  setError('');setErrorSet('')
  const check=structuredClone(draft)
  for(const ex of check.exercises)for(const record of ex.records)if(record.status==='completed'){
   try{record.status='draft';confirmSet(check,ex.id,record.id)}catch(e){
    setError(e instanceof Error?e.message:'Проверьте введённые значения.');setErrorSet(record.id)
    setOpenExercises(old=>new Set(old).add(ex.id));setOpenSets(old=>new Set(old).add(record.id))
    requestAnimationFrame(()=>{const row=form.current?.querySelector<HTMLElement>('[data-record="'+record.id+'"]');row?.scrollIntoView({block:'center',behavior:'smooth'});row?.querySelector<HTMLInputElement>('input:not(:disabled)')?.focus()})
    return
   }
  }
  setSaving(true)
  try{await flush();await saveCorrection(snapshot,draft);await clear();onClose()}
  catch(e){setError(e instanceof Error?e.message:'Ошибка сохранения. Введённые изменения остались в черновике.')}
  finally{setSaving(false)}
 }
 async function cancel(){setSaving(true);try{await clear();onClose()}catch(e){setError(e instanceof Error?e.message:'Не удалось удалить черновик.')}finally{setSaving(false)}}
 return <section className="card history-editor">
  <h2>Исправление записи</h2><p>{snapshot.name} · {snapshot.localDate}. Дата и статус тренировки сохранятся. Графики пересчитаются после сохранения.</p>
  <div className="editor-draft-status" role="status">{ready?status:'Открываем черновик…'}<small>Изменено подходов: {changed}</small></div>
  {(error||draftError)&&<div className="alert" role="alert">{error||draftError}</div>}
  <form ref={form} noValidate onSubmit={e=>{e.preventDefault();void submit()}}><fieldset disabled={disabled||saving||!ready}>
   {draft.exercises.map((ex,ei)=><details className="exercise-editor correction-exercise" key={ex.id} open={openExercises.has(ex.id)} onToggle={e=>{const opened=e.currentTarget.open;setOpenExercises(old=>toggleId(old,ex.id,opened))}}>
    <summary><span><strong>{exerciseName(ex)}</strong><small>{ex.equipment} · {modes[ex.mode]} · {ex.records.length} подходов</small></span></summary>
    {ex.records.map((r,ri)=>{const dirty=JSON.stringify(r)!==JSON.stringify(snapshot.exercises.find(x=>x.id===ex.id)?.records.find(x=>x.id===r.id));return <details className={'correction-set '+(dirty?'correction-dirty':'')} key={r.id} data-record={r.id} open={openSets.has(r.id)} onToggle={e=>{const opened=e.currentTarget.open;setOpenSets(old=>toggleId(old,r.id,opened))}}>
     <summary>Подход {ri+1} · {r.status==='skipped'?'Пропущен':r.status==='draft'?'Черновик':(ex.mode==='BodyweightOnly'?'':r.weight+' кг × ')+(ex.tracking==='duration'?(r.duration??'')+' сек':r.reps+' повт.')}{ex.unilateral?' · '+sideNames[r.side??'both']:''}{dirty?' · изменён':''}</summary>
     {errorSet===r.id&&<p className="field-error">{error}</p>}
     <div className="form-grid">
      <label>Статус подхода<select value={r.status} onChange={e=>patch(ei,ri,{status:e.target.value as SetRecord['status']})}><option value="completed">Выполнен</option><option value="skipped">Пропущен</option><option value="draft">Черновик</option></select></label>
      <label>Тип подхода<select value={r.kind} onChange={e=>patch(ei,ri,{kind:e.target.value as SetRecord['kind']})}><option value="working">Рабочий</option><option value="warmup">Разминка</option></select></label>
      {ex.mode!=='BodyweightOnly'&&<label>Вес, кг<input inputMode="decimal" value={r.weight} onChange={e=>patch(ei,ri,{weight:e.target.value})}/></label>}
      <label>{ex.tracking==='duration'?'Секунды':'Повторы'}<input inputMode="numeric" value={ex.tracking==='duration'?r.duration??'':r.reps} onChange={e=>patch(ei,ri,ex.tracking==='duration'?{duration:e.target.value}:{reps:e.target.value})}/></label>
      {ex.unilateral&&<label>Сторона<select value={r.side??'both'} onChange={e=>patch(ei,ri,{side:e.target.value as SetRecord['side']})}><option value="both">Выберите сторону</option><option value="left">Левая</option><option value="right">Правая</option></select></label>}
      <label>RIR<input inputMode="numeric" value={r.rir} onChange={e=>patch(ei,ri,{rir:e.target.value})}/><small>Сколько повторов оставалось в запасе: 0–10. Можно оставить пустым.</small></label>
      <label>Заметка<input maxLength={2000} value={r.note} onChange={e=>patch(ei,ri,{note:e.target.value})}/></label>
     </div>
    </details>})}
   </details>)}
   <div className="actions editor-save-actions"><button className="primary">{saving?'Сохраняем…':'Сохранить исправления'}</button><button type="button" onClick={()=>void cancel()}>Отменить исправления</button></div>
  </fieldset></form>
 </section>
}
