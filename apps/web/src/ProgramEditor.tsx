import { useLayoutEffect, useRef, useState } from 'react'
import { ChevronDown, Plus, X } from 'lucide-react'
import ExerciseGuide from './ExerciseGuide'
import { EquipmentPicker, TrackingFields } from './ManageData'
import { exerciseName, guides } from './exerciseLibrary'
import { MUSCLE_NAMES, musclesFor } from './muscles'
import { defaultRest } from './restDefaults'
import { modes, muscleIds, programSchema, uid, type Exercise, type MuscleId, type Program } from './domain'
import { copyDay, moveItem } from './workoutEditing'
import { Sheet } from './Sheet'
import { useEditorDraft } from './editorDrafts'
import './management.css'

export const blankExercise=():Exercise=>({id:uid(),variantId:uid(),equipmentId:uid(),name:'',equipment:'',mode:'BarbellTotal',sets:3,target:'',rest:90})
export const blankProgram=():Program=>({id:uid(),name:'Моя программа',version:1,days:[{id:uid(),name:'',exercises:[blankExercise()]}]})
type Props={initial?:Program;save:(p:Program,original:Program)=>Promise<boolean>;onCancel?:()=>void}
type FieldErrors=Record<string,string>

export default function ProgramEditor({initial,save,onCancel}:Props) {
 const [base]=useState(()=>initial??blankProgram())
 const {value:p,setValue:setP,original,ready,status,error:draftError,clear,flush}=useEditorDraft('program',base)
 const [notes,setNotes]=useState(false),[saving,setSaving]=useState(false),[error,setError]=useState(''),[errors,setErrors]=useState<FieldErrors>({})
 const [open,setOpen]=useState<Set<string>>(()=>new Set(base.days.flatMap(d=>d.exercises.filter(e=>!e.name.trim()).map(e=>e.id))))
 const [lookup,setLookup]=useState<{dayId:string;exerciseId:string}|null>(null),[query,setQuery]=useState('')
 const [focusRequest,setFocusRequest]=useState<{path:string}|null>(null)
 const form=useRef<HTMLFormElement>(null)
 const isOpen=(ex:Exercise)=>open.has(ex.id)||!ex.name.trim()
 const toggle=(id:string)=>setOpen(old=>{const next=new Set(old);if(next.has(id))next.delete(id);else next.add(id);return next})
 const update=(fn:(p:Program)=>void)=>{setP(old=>{const next=structuredClone(old);fn(next);return next});setErrors({});setError('')}
 const focusField=(path:string)=>setFocusRequest({path})
 useLayoutEffect(()=>{
  if(!focusRequest)return
  const input=form.current?.querySelector<HTMLElement>('[data-field="'+focusRequest.path+'"]')
  if(input){let parent=input.parentElement;while(parent){if(parent instanceof HTMLDetailsElement)parent.open=true;parent=parent.parentElement}input.focus({preventScroll:true});input.scrollIntoView({block:'center'})}
 },[focusRequest])
 const fieldProps=(path:string)=>({'data-field':path,'aria-invalid':!!errors[path],'aria-describedby':errors[path]?'error-'+path:undefined})
 const fieldError=(path:string)=>errors[path]?<small className="field-error" id={'error-'+path}>{errors[path]}</small>:null
 async function submit() {
  const candidate={...p,version:original.version+1}
  const validation=programSchema.safeParse(candidate),nextErrors:FieldErrors={}
  if(!validation.success)for(const issue of validation.error.issues){
   const key=issue.path.join('.'),field=String(issue.path[issue.path.length-1])
   nextErrors[key]=field==='name'?'Введите название.':field==='equipment'?'Укажите оборудование или «Собственный вес».':field==='sets'?'Укажите от 1 до 30 подходов.':field==='rest'?'Отдых: целое число от 0 до 1800 секунд.':'Проверьте значение поля.'
  }
  if(!p.name.trim())nextErrors.name='Введите название программы.'
  p.days.forEach((day,di)=>{if(!day.name.trim())nextErrors['days.'+di+'.name']='Введите название дня.';day.exercises.forEach((ex,ei)=>{if(!ex.name.trim())nextErrors['days.'+di+'.exercises.'+ei+'.name']='Введите название упражнения.';if(!ex.equipment.trim())nextErrors['days.'+di+'.exercises.'+ei+'.equipment']='Укажите оборудование или «Собственный вес».'})})
  if(Object.keys(nextErrors).length){
   setErrors(nextErrors);setError('Проверьте выделенные поля. Изменения пока не применены.')
   setOpen(old=>new Set([...old,...p.days.flatMap((day,di)=>day.exercises.filter((_,ei)=>Object.keys(nextErrors).some(key=>key.startsWith('days.'+di+'.exercises.'+ei+'.'))).map(ex=>ex.id))]))
   focusField(Object.keys(nextErrors)[0]);return
  }
  setSaving(true);setError('')
  try{await flush();if(await save(candidate,original))await clear()}catch(e){setError(e instanceof Error?e.message:'Не удалось сохранить программу. Черновик сохранён.')}
  finally{setSaving(false)}
 }
 async function cancel(){setSaving(true);try{await clear();onCancel?.()}catch(e){setError(e instanceof Error?e.message:'Не удалось удалить черновик.')}finally{setSaving(false)}}
 const suggestions=guides.filter(g=>(g.ru+' '+g.english).toLocaleLowerCase('ru-RU').includes(query.trim().toLocaleLowerCase('ru-RU')))
 return <>
 <form ref={form} noValidate onSubmit={e=>{e.preventDefault();void submit()}} className="editor program-editor">
  <div className="editor-draft-status" role="status">{ready?status:'Открываем черновик…'}<small>Изменения войдут в программу после сохранения.</small></div>
  {(error||draftError)&&<div className="alert" role="alert">{error||draftError}</div>}
  <fieldset disabled={!ready||saving}>
  <label>Название программы<input required maxLength={2000} {...fieldProps('name')} value={p.name} onChange={e=>update(p=>{p.name=e.target.value})}/>{fieldError('name')}</label>
  {p.days.map((d,di)=><section className="card" key={d.id}>
   <div className="section-head">
    <span className="eyebrow">ДЕНЬ {di+1}</span>
    <div className="order-actions">
     <button type="button" aria-label={'День '+(di+1)+' выше'} disabled={di===0} onClick={()=>update(p=>moveItem(p.days,di,-1))}>↑</button>
     <button type="button" aria-label={'День '+(di+1)+' ниже'} disabled={di===p.days.length-1} onClick={()=>update(p=>moveItem(p.days,di,1))}>↓</button>
     <button type="button" disabled={p.days.length>=30} onClick={()=>update(p=>copyDay(p,di))}>Копировать день</button>
     {p.days.length>1&&<button type="button" aria-label={'Удалить день '+(di+1)} onClick={()=>update(p=>{p.days.splice(di,1)})}><X size={18}/></button>}
    </div>
   </div>
   <label>Название дня<input required maxLength={2000} {...fieldProps('days.'+di+'.name')} placeholder="Например, спина" value={d.name} onChange={e=>update(p=>{p.days[di].name=e.target.value})}/>{fieldError('days.'+di+'.name')}</label>
   {d.exercises.map((ex,ei)=>{const path='days.'+di+'.exercises.'+ei;return <div className={'exercise-editor '+(isOpen(ex)?'open':'')} key={ex.id}>
    <button type="button" className="ex-toggle" aria-expanded={isOpen(ex)} onClick={()=>toggle(ex.id)}>
     <span>{ei+1}. {exerciseName(ex)||'Новое упражнение'}<small>{ex.sets} подходов{ex.target?' · '+ex.target:''}{ex.rest!=null?' · отдых '+ex.rest+' сек':''}</small></span><ChevronDown size={18}/>
    </button>
    {isOpen(ex)&&<>
    <div className="order-actions">
     <button type="button" aria-label={'Упражнение '+(ei+1)+' выше'} disabled={ei===0} onClick={()=>update(p=>moveItem(p.days[di].exercises,ei,-1))}>↑</button>
     <button type="button" aria-label={'Упражнение '+(ei+1)+' ниже'} disabled={ei===d.exercises.length-1} onClick={()=>update(p=>moveItem(p.days[di].exercises,ei,1))}>↓</button>
     {d.exercises.length>1&&<button type="button" aria-label="Удалить упражнение" onClick={()=>update(p=>{p.days[di].exercises.splice(ei,1)})}><X size={18}/></button>}
    </div>
    <div className="form-grid">
     <label>Название и вариант<input required maxLength={2000} {...fieldProps(path+'.name')} value={exerciseName(ex)} placeholder="Название упражнения" onChange={e=>{setOpen(old=>new Set(old).add(ex.id));update(p=>{p.days[di].exercises[ei].name=e.target.value})}}/>{fieldError(path+'.name')}</label>
     <button type="button" className="ghost exercise-lookup" onClick={()=>{setLookup({dayId:d.id,exerciseId:ex.id});setQuery('')}}>Найти в справочнике</button>
     <label>Тренажёр / оборудование<input required maxLength={2000} {...fieldProps(path+'.equipment')} value={ex.equipment} placeholder="Конкретный тренажёр" onChange={e=>update(p=>{p.days[di].exercises[ei].equipment=e.target.value})}/>{fieldError(path+'.equipment')}</label>
     <label>Рабочие подходы{ex.unilateral?' на каждую сторону':''}<input required type="number" min="1" max="30" {...fieldProps(path+'.sets')} value={ex.sets||''} onChange={e=>update(p=>{p.days[di].exercises[ei].sets=Number(e.target.value)})}/>{fieldError(path+'.sets')}</label>
     <label>{ex.tracking==='duration'?'Цель по длительности':'Цель по повторениям'}<input maxLength={2000} placeholder={ex.tracking==='duration'?'30–45 секунд':'8–12'} value={ex.target} onChange={e=>update(p=>{p.days[di].exercises[ei].target=e.target.value})}/></label>
     <label>Отдых, секунд<input type="number" min="0" max="1800" placeholder={String(defaultRest(ex))} {...fieldProps(path+'.rest')} value={ex.rest??''} onChange={e=>update(p=>{p.days[di].exercises[ei].rest=e.target.value===''?null:Number(e.target.value)})}/>{fieldError(path+'.rest')}</label>
    </div>
    <details className="advanced"><summary>Оборудование и дополнительные настройки</summary>
     <div className="form-grid">
      <EquipmentPicker exercise={ex} onChange={fields=>update(p=>{Object.assign(p.days[di].exercises[ei],fields)})}/>
      <label>Как учитывать вес<select value={ex.mode} onChange={e=>update(p=>{const x=p.days[di].exercises[ei];x.mode=e.target.value as Exercise['mode'];x.equipmentId=uid();x.stepGrams=null;x.availableGrams=[]})}>{Object.entries(modes).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <TrackingFields exercise={ex} onChange={fields=>update(p=>{Object.assign(p.days[di].exercises[ei],fields)})}/>
      <label>Группа мышц<select value={ex.muscle??''} onChange={e=>update(p=>{p.days[di].exercises[ei].muscle=e.target.value===''?undefined:e.target.value as MuscleId})}>
       <option value="">По справочнику{musclesFor({name:ex.name})?' · '+MUSCLE_NAMES[musclesFor({name:ex.name})!.primary]:' · не определена'}</option>
       {muscleIds.map(id=><option key={id} value={id}>{MUSCLE_NAMES[id]}</option>)}
      </select></label>
     </div>
     <p className="profile-help">Правка названия сохраняет сравнение с прошлыми тренировками. Для другого тренажёра выберите профиль из каталога или создайте новый профиль ниже.</p>
     <button className="ghost" type="button" onClick={()=>update(p=>{const x=p.days[di].exercises[ei];x.equipmentId=uid();x.stepGrams=null;x.availableGrams=[]})}>Другое оборудование: новый профиль</button>
     <ExerciseGuide exercise={ex}/>
     <label><input type="checkbox" checked={!!ex.optionalWeekly} onChange={e=>update(p=>{p.days[di].exercises[ei].optionalWeekly=e.target.checked})}/>Необязательный блок раз в неделю</label>
     <label>Подсказки упражнения<textarea maxLength={2000} value={ex.sourceNote??''} onChange={e=>update(p=>{p.days[di].exercises[ei].sourceNote=e.target.value})}/></label>
     <button className="ghost" type="button" onClick={()=>update(p=>{p.days[di].exercises[ei].variantId=uid()})}>Новый вариант: не сравнивать со старым</button>
    </details></>}
   </div>})}
   <button type="button" className="ghost" disabled={d.exercises.length>=50} onClick={()=>{const fresh=blankExercise();setOpen(old=>new Set(old).add(fresh.id));update(p=>{p.days[di].exercises.push(fresh)});focusField('days.'+di+'.exercises.'+d.exercises.length+'.name')}}><Plus size={18}/> Упражнение</button>
  </section>)}
  <div className="actions">
   <button type="button" className="ghost" disabled={p.days.length>=30} onClick={()=>{const ex=blankExercise();setOpen(old=>new Set(old).add(ex.id));update(p=>{p.days.push({id:uid(),name:'',exercises:[ex]})});focusField('days.'+p.days.length+'.name')}}><Plus size={18}/> День</button>
   <button type="button" className="ghost" onClick={()=>setNotes(true)}>Заметки программы</button>
  </div>
  <div className="actions editor-save-actions"><button className="primary">{saving?'Сохраняем…':'Сохранить программу'}</button>{onCancel&&<button type="button" onClick={()=>void cancel()}>Отменить изменения</button>}</div>
  </fieldset>
 </form>
 {notes&&<Sheet title="Заметки программы" onClose={()=>setNotes(false)}><label>Заметки программы<textarea maxLength={2000} value={p.sourceNote??''} onChange={e=>update(p=>{p.sourceNote=e.target.value})}/></label><button type="button" onClick={()=>setNotes(false)}>Готово</button></Sheet>}
 {lookup&&<Sheet title="Справочник упражнений" onClose={()=>setLookup(null)}><label>Поиск упражнения<input type="search" placeholder="Название на русском или английском" value={query} onChange={e=>setQuery(e.target.value)}/></label><p>Выберите название или закройте справочник и введите своё.</p><div className="exercise-results">{suggestions.length?suggestions.map(g=><button type="button" key={g.english} onClick={()=>{update(p=>{const ex=p.days.find(d=>d.id===lookup.dayId)?.exercises.find(ex=>ex.id===lookup.exerciseId);if(ex)ex.name=g.ru});setLookup(null)}}><strong>{g.ru}</strong><small>{g.english}</small></button>):<p>Упражнение не найдено. Можно указать его вручную.</p>}</div></Sheet>}
 </>
}
