import { useEffect, useRef, useState } from 'react'
import { Check, Minus, MoreHorizontal, Plus, Trophy } from 'lucide-react'
import { adjustedWeight, sideNames, type Exercise, type SetRecord } from './domain'
import type { SetConfirmResult } from './setValidation'
import { copiedSetValues } from './workoutUx'
import type { Suggestion } from './progression'
import type { RecordKind } from './records'
import { setSaved } from './haptics'
import NumberPad from './NumberPad'
import { Sheet } from './Sheet'

export type Field='weight'|'reps'|'duration'
const recordName={weight:'Рекорд веса',max:'Рекорд',reps:'Рекорд повторений',duration:'Рекорд длительности'} as const
type Issue=Extract<SetConfirmResult,{ok:false}>
type Props={
 suggestion?:Suggestion; repeatSet?:SetRecord; total?:number; best?:RecordKind
 exercise:Exercise; record:SetRecord; index:number; bodyweight:boolean; disabled:boolean
 patch:(p:Partial<SetRecord>)=>void; confirm:()=>Promise<SetConfirmResult>; skip:()=>void; edit:()=>void
 pad:Field|null; onPad:(field:Field|null)=>void; current:boolean
 onEquipmentError?:()=>void; onHistoryEdit?:()=>void
}

export default function SetRow({suggestion,repeatSet,total,best,exercise,record,index,bodyweight,disabled,patch,confirm,skip,edit,pad,onPad,current,onEquipmentError,onHistoryEdit}:Props) {
 const [local,setLocal]=useState(record),[more,setMore]=useState(false),[issue,setIssue]=useState<Issue|null>(null)
 const [source,setSource]=useState(''),[submitting,setSubmitting]=useState(false)
 const previousRecord=useRef(record),prefilled=useRef(false),row=useRef<HTMLDivElement>(null),submitBar=useRef<HTMLDivElement>(null)
 const equipmentError=useRef(onEquipmentError)
 useEffect(()=>{equipmentError.current=onEquipmentError},[onEquipmentError])
 const duration=exercise.tracking==='duration',countField:Field=duration?'duration':'reps',countLabel=duration?'Секунды':'Повторения'
 const done=record.status==='completed',skipped=record.status==='skipped',locked=disabled||submitting
 const visibleIssue=issue?.field==='equipment'&&exercise.mode!=='Unspecified'?null:issue
 const errorId=`set-error-${record.id}`

 useEffect(()=>{
  const old=previousRecord.current;previousRecord.current=record
  setLocal(current=>(['weight','reps','duration','rir','note'] as const).every(k=>current[k]===old[k])?record:current)
 },[record])

 useEffect(()=>{
  if(prefilled.current||disabled||done||skipped||!suggestion)return
  prefilled.current=true
  if(local.weight!==''||local.reps!==''||local.duration)return
  const {note,...values}=suggestion
  setLocal(current=>({...current,...values}));patch(values)
  if(note)setSource(note)
 // Prefill runs once for an untouched set, never over manual input.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[suggestion,disabled,done,skipped])

 useEffect(()=>{
  if(!issue?.field)return
  if(issue.field==='equipment'){equipmentError.current?.();return}
  if(issue.field==='rir')setMore(true)
  const frame=requestAnimationFrame(()=>{
   const input=row.current?.querySelector<HTMLElement>(`[data-set-field="${issue.field}"]`)
   input?.focus();input?.scrollIntoView({block:'center'})
  })
  return ()=>cancelAnimationFrame(frame)
 },[issue])

 const field=(key:'weight'|'reps'|'duration'|'rir'|'note',value:string)=>{
  const next={...local,[key]:value};setLocal(next);setSource('')
  if(issue?.field===key)setIssue(null)
  patch({duration:next.duration,weight:next.weight,reps:next.reps,rir:next.rir,note:next.note})
 }
 const openPad=(key:Field,input?:HTMLInputElement)=>{
  if(locked)return
  input?.select();onPad(key)
  if(input)requestAnimationFrame(()=>input.scrollIntoView({block:'center'}))
 }
 const focusCount=()=>{const input=row.current?.querySelector<HTMLInputElement>(`[data-set-field="${countField}"]`);input?.focus();input?.select();onPad(countField)}
 useEffect(()=>{
  const node=submitBar.current
  if(!pad||!node||typeof ResizeObserver==='undefined')return
  const apply=()=>document.documentElement.style.setProperty('--set-submit-height',node.offsetHeight+'px')
  apply()
  const observer=new ResizeObserver(apply)
  observer.observe(node)
  return()=>{observer.disconnect();document.documentElement.style.removeProperty('--set-submit-height')}
 },[pad])

 const submit=async()=>{
  if(locked)return
  onPad(null);setSubmitting(true);setIssue(null)
  try{const result=await confirm();if(result.ok)setSaved();else setIssue(result)}
  finally{setSubmitting(false)}
 }
 const step=(direction:1|-1)=>{
  try{field('weight',adjustedWeight(exercise,local.weight||'0',direction))}
  catch(error){setIssue({ok:false,field:'weight',message:(error as Error).message})}
 }
 const stepCount=(direction:1|-1)=>{
  const next=Math.max(0,Math.min(duration?86400:1000,Number((duration?local.duration:local.reps)||0)+direction*(duration?5:1)))
  field(countField,next?String(next):'')
 }
 const repeat=()=>{
  if(!repeatSet)return
  const values=copiedSetValues(repeatSet,exercise)
  setLocal(current=>({...current,...values}));patch(values);setIssue(null);setSource('')
 }
 const invalid=(key:Issue['field'])=>issue?.field===key
 const weightSteppable=!bodyweight&&!!(exercise.stepGrams||exercise.availableGrams?.length)

 if(done||skipped)return <div id={`set-${record.id}`} className={`set-wrap ${done?'done':'skipped'}`} ref={row}>
  <div className="set-done">
   <span className="set-number">{done?<Check size={16}/>:index+1}</span>
   <span className="set-summary">
    {!bodyweight&&<><input className="flat" style={{width:`${(local.weight.length||1)+.4}ch`}} aria-label={`Вес подхода ${index+1}`} disabled value={local.weight} readOnly/><em>кг</em><span aria-hidden="true">×</span></>}
    <input className="flat" style={{width:`${((duration?local.duration??'':local.reps).length||1)+.4}ch`}} aria-label={`${countLabel} подхода ${index+1}`} disabled value={duration?local.duration??'':local.reps} readOnly/>
    <em>{duration?'сек':'повт.'}</em>{exercise.unilateral&&<em>{sideNames[record.side??'both']}</em>}
   </span>
   {best&&<span className="tag record" title={recordName[best]}><Trophy size={13} aria-hidden="true"/><span className="sr-only">{recordName[best]}</span></span>}
   {skipped&&<small>Пропущен</small>}
   {(onHistoryEdit||!disabled)&&<button type="button" className="ghost" disabled={!onHistoryEdit&&locked} onClick={onHistoryEdit??edit}>{onHistoryEdit?'Исправить подход':'Изменить'}</button>}
  </div>
  {record.note&&<small className="set-note">{record.note}</small>}
 </div>

 return <div id={`set-${record.id}`} className={`set-wrap ${current?'current':''}`} ref={row}>
  <div className="set-live">
   <div className="set-head">
    <strong className="set-position">Подход {index+1}{total?` из ${total}`:''}</strong>
    {record.kind==='warmup'&&<span className="tag">Разминка</span>}
    <button className="icon" type="button" aria-label={`Ещё о подходе ${index+1}`} disabled={locked} onClick={()=>{onPad(null);setMore(true)}}><MoreHorizontal size={18}/></button>
   </div>
   {exercise.unilateral&&<label className="side">Сторона подхода {index+1}
    <select data-set-field="side" aria-invalid={invalid('side')} aria-describedby={invalid('side')?errorId:undefined} disabled={locked} value={record.side??'both'} onChange={e=>{setIssue(null);patch({side:e.target.value as SetRecord['side']})}}>
     <option value="both">Выберите сторону</option><option value="left">Левая</option><option value="right">Правая</option>
    </select></label>}
   {source&&<small className="set-source">{source}</small>}
   {!bodyweight&&<label className="set-field-label">Вес, кг
    <span className="stepper">
     {weightSteppable&&<button type="button" aria-label="− Вес" disabled={locked} onClick={()=>step(-1)}><Minus size={20}/></button>}
     <span className="value"><input data-set-field="weight" inputMode="none" aria-label={`Вес подхода ${index+1}`} aria-invalid={invalid('weight')} aria-describedby={invalid('weight')?errorId:undefined} placeholder="0" disabled={locked} value={local.weight} onFocus={e=>openPad('weight',e.currentTarget)} onClick={e=>openPad('weight',e.currentTarget)} onChange={e=>field('weight',e.target.value)}/><em>кг</em></span>
     {weightSteppable&&<button type="button" aria-label="+ Вес" disabled={locked} onClick={()=>step(1)}><Plus size={20}/></button>}
    </span>
   </label>}
   <label className="set-field-label">{countLabel}
    <span className="stepper">
     <button type="button" aria-label={`− ${countLabel}`} disabled={locked} onClick={()=>stepCount(-1)}><Minus size={20}/></button>
     <span className="value"><input data-set-field={countField} inputMode="none" aria-label={`${countLabel} подхода ${index+1}`} aria-invalid={invalid(countField)} aria-describedby={invalid(countField)?errorId:undefined} placeholder="0" disabled={locked} value={duration?local.duration??'':local.reps} onFocus={e=>openPad(countField,e.currentTarget)} onClick={e=>openPad(countField,e.currentTarget)} onChange={e=>field(countField,e.target.value)}/><em>{duration?'сек':'повт.'}</em></span>
     <button type="button" aria-label={`+ ${countLabel}`} disabled={locked} onClick={()=>stepCount(1)}><Plus size={20}/></button>
    </span>
   </label>
   {visibleIssue&&(!more||visibleIssue.field!=='rir')&&<p role="alert" id={errorId} className="hint set-error">{visibleIssue.message}</p>}
   {repeatSet&&<button type="button" className="ghost repeat-set" disabled={locked} onClick={repeat}>Повторить предыдущий подход</button>}
   <div className="set-submit" ref={submitBar}>
    {pad&&<NumberPad key={pad} value={pad==='weight'?local.weight:pad==='duration'?local.duration??'':local.reps} decimal={pad==='weight'} disabled={locked} onChange={value=>field(pad,value)} onHide={()=>onPad(null)} onNext={pad==='weight'?focusCount:undefined} nextLabel={duration?'К секундам':'К повторениям'}/>}
    <button type="button" className="primary go" disabled={locked} onClick={event=>{if(event.detail<2)void submit()}}>{submitting?'Сохраняем…':'Готово'}</button>
   </div>
  </div>
  {more&&<Sheet title={`Подход ${index+1}`} onClose={()=>setMore(false)}>
   <label>Тип<select disabled={locked} value={record.kind} onChange={e=>patch({kind:e.target.value as SetRecord['kind']})}><option value="working">Рабочий</option><option value="warmup">Разминка</option></select></label>
   <label>RIR<input aria-label="RIR" data-set-field="rir" inputMode="numeric" aria-invalid={invalid('rir')} aria-describedby={invalid('rir')?errorId:undefined} disabled={locked} value={local.rir} onChange={e=>field('rir',e.target.value)}/><small>Сколько повторений осталось в запасе. Можно не заполнять.</small></label>
   {issue?.field==='rir'&&<p role="alert" id={errorId} className="hint">{issue.message}</p>}
   <label>Заметка<textarea aria-label="Заметка" disabled={locked} value={local.note} onChange={e=>field('note',e.target.value)}/></label>
   <button type="button" onClick={()=>setMore(false)}>Готово к подходу</button>
   <button type="button" className="ghost" disabled={locked} onClick={()=>{skip();setMore(false)}}>Пропустить подход</button>
  </Sheet>}
 </div>
}
