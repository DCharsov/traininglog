import { useEffect, useRef, useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { Activity, CalendarDays, ListChecks, Plus, Settings, TrendingUp } from 'lucide-react'
import { change, db, lifecycleChange, start } from './data'
import { calendarSchema, confirmSet, programSchema, uid, visible, type Program, type Session, type SetRecord } from './domain'
import { validateSet, type SetConfirmResult } from './setValidation'
import { offerWeeklyOptional } from './hypertrophyAB'
import MobileViewport from './MobileViewport'
import OfflineStatus from './OfflineStatus'
import Progress, { initialProgressState, type ProgressState } from './ProgressView'
import HistoryEditor from './HistoryEditor'
import HistoryScreen, { emptyHistoryFilters, type HistoryFilters } from './HistoryScreen'
import type { RestAction } from './HistoryCalendar'
import ProgramEditor, { blankProgram } from './ProgramEditor'
import ProgramOverview from './ProgramOverview'
import TodayScreen from './TodayScreen'
import WorkoutScreen from './WorkoutScreen'
import ExerciseScreen from './ExerciseScreen'
import SettingsScreen from './SettingsScreen'
import SeedPrograms from './SeedPrograms'
import RestTimer from './RestTimer'
import { SyncStatus } from './SyncPanel'
import { useSyncController } from './useSyncController'
import { canonical } from './sync'
import { useAsk } from './Sheet'
import { useWakeLock } from './useWakeLock'
import { readStored, useNavigation, type Tab } from './navigation'
import { askRestNotice, useRestNotice } from './restNotice'
import './App.css'

const tabs=[{name:'Сегодня',icon:Activity},{name:'Программы',icon:ListChecks},{name:'История',icon:CalendarDays},{name:'Прогресс',icon:TrendingUp}] as const
const completedCount=(s:Session)=>s.exercises.reduce((n,e)=>n+e.records.filter(r=>r.status==='completed').length,0)
function storedNewProgram(){try{const raw=localStorage.getItem('traininglog-new-program');return raw?JSON.parse(raw) as Program:blankProgram()}catch{return blankProgram()}}

export default function App() {
 const {route,navigate}=useNavigation()
 const [error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[editable,setEditable]=useState(false),[lockReady,setLockReady]=useState(false),[now,setNow]=useState(()=>Date.now())
 const [updating,setUpdating]=useState(false)
 const [editorKey,setEditorKey]=useState(0),[newProgram,setNewProgram]=useState(storedNewProgram)
 const [selectedProgram,setSelectedProgram]=useState(()=>localStorage.getItem('traininglog-selected-program')??'')
 const [progressState,setProgressState]=useState<ProgressState>(()=>readStored('traininglog-progress',initialProgressState()))
 const [historyFilters,setHistoryFilters]=useState<HistoryFilters>(()=>readStored('traininglog-history',emptyHistoryFilters))
 const pending=useRef(Promise.resolve()),failedDrafts=useRef(new Set<string>()),confirming=useRef(new Set<string>())
 const {ask,dialog}=useAsk()
 const sync=useSyncController({editable})
 const data=useLiveQuery(async()=>{try{return {programs:await db.programs.toArray(),sessions:await db.sessions.toArray()}}catch{setError('Не удалось открыть локальное хранилище.');return {programs:[],sessions:[]}}})
 useEffect(()=>{
  let release:(()=>void)|undefined,disposed=false
  const controller=new AbortController(),interval=setInterval(()=>setNow(Date.now()),1000)
  const waiting=setTimeout(()=>{if(!disposed){setLockReady(true);if(!navigator.locks)setError('Для записи нужен браузер с поддержкой безопасного локального хранилища.')}},300)
  if(navigator.locks)void navigator.locks.request('traininglog-editor',{signal:controller.signal},async()=>{if(disposed)return;setEditable(true);setLockReady(true);await new Promise<void>(resolve=>{release=resolve});if(!disposed)setEditable(false)}).catch(e=>{if(e.name!=='AbortError')setError('Не удалось получить блокировку редактора.')})
  return()=>{disposed=true;controller.abort();release?.();clearInterval(interval);clearTimeout(waiting)}
 },[])
 useEffect(()=>{
  if(new URLSearchParams(window.location.search).get('action')!=='start')return
  navigate({tab:'Сегодня',workoutOpen:true},true)
  window.history.replaceState(window.history.state,'',import.meta.env.BASE_URL)
 // Ярлык с домашнего экрана срабатывает один раз при открытии.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[])
 useEffect(()=>{localStorage.setItem('traininglog-selected-program',selectedProgram)},[selectedProgram])
 useEffect(()=>{sessionStorage.setItem('traininglog-progress',JSON.stringify(progressState))},[progressState])
 useEffect(()=>{sessionStorage.setItem('traininglog-history',JSON.stringify(historyFilters))},[historyFilters])
 const programs=(data?.programs??[]).filter(visible),sessions=(data?.sessions??[]).filter(s=>!s.deletedAt)
 const program=programs.find(p=>p.id===selectedProgram)??programs.find(p=>!p.seedKey)??programs[0]
 const editorTargetId=route.editProgramId??(selectedProgram==='new'?newProgram.id:program?.id)
 const editorCopy=useLiveQuery(()=>route.programEditing&&editorTargetId?db.editorDrafts.get(`program:${editorTargetId}`):undefined,[route.programEditing,editorTargetId])
 const editorProgram=data?.programs.find(p=>p.id===editorTargetId)??(editorCopy?.kind==='program'?editorCopy.original as Program:undefined)??(editorTargetId===newProgram.id?newProgram:undefined)
 const active=sessions.find(s=>s.status==='active')
 const inWorkout=!!active&&route.tab==='Сегодня'&&route.workoutOpen
 const viewing=route.viewId?sessions.find(s=>s.id===route.viewId):inWorkout?active:undefined
 const summary=route.summaryId?sessions.find(s=>s.id===route.summaryId):undefined
 useWakeLock(inWorkout)
 useRestNotice(active?.restEndsAt,!!active)
 const calendar=(useLiveQuery(()=>db.calendar.toArray())??[]).filter(visible)
 const restToday=calendar.some(entry=>entry.date===new Date().toLocaleDateString('sv-SE'))
 const disabled=!editable||busy||updating
 const goTab=(tab:Tab)=>navigate({tab,workoutOpen:tab==='Сегодня'})
 const openSession=(id:string,origin:'История'|'Прогресс')=>navigate({tab:'История',workoutOpen:false,viewId:id,origin})
 const closeSession=()=>navigate({tab:route.origin??'История',workoutOpen:false})

 async function prepareUpdate() {
  if(busy||confirming.current.size)throw new Error('Дождитесь завершения сохранения и повторите обновление.')
  // Draft writes run in a queue; a click must not reload ahead of the last keystroke.
  let saving:Promise<void>
  do {saving=pending.current;await saving} while(saving!==pending.current)
  if(failedDrafts.current.size)throw new Error('Ввод не сохранён. Повторите изменение подхода перед обновлением.')
 }

 async function run(action:()=>Promise<unknown>,message='Сохранено') {
  setError('');setBusy(true)
  try{await pending.current;if(failedDrafts.current.size)throw new Error('Черновик подхода не сохранён. Повторите ввод.');await action();setNotice(message);return true}
  catch(e){setNotice('');setError(e instanceof Error?e.message:'Ошибка сохранения. Повторите.');return false}
  finally{setBusy(false)}
 }
 const mutate=(fn:(s:Session)=>boolean|void)=>{if(viewing&&editable)void run(()=>change(viewing.id,-1,fn))}
 function draft(sessionId:string,exerciseId:string,setId:string,patch:Partial<SetRecord>) {
  if(!editable)return
  setNotice('Сохраняем подход…')
  pending.current=pending.current.then(async()=>{
   try{await change(sessionId,-1,s=>{const r=s.exercises.find(e=>e.id===exerciseId)?.records.find(x=>x.id===setId);if(!r)throw new Error('Подход уже изменился.');if(r.status!=='completed')Object.assign(r,patch)},false);failedDrafts.current.delete(setId);if(!failedDrafts.current.size){setError('');setNotice('Черновик сохранён на устройстве')}}
   catch{failedDrafts.current.add(setId);setNotice('');setError('Ошибка локального сохранения. Ввод остался на экране.')}
  })
 }
 async function confirm(exerciseId:string,setId:string):Promise<SetConfirmResult> {
  if(!editable||!viewing)return {ok:false,message:'Редактирование недоступно в этой вкладке.'}
  if(confirming.current.has(setId))return {ok:false,message:'Сохраняем подход…'}
  confirming.current.add(setId);setBusy(true);setError('')
  try{
   await pending.current
   if(failedDrafts.current.size)throw new Error('Не удалось сохранить ввод. Повторите изменение.')
   let result:SetConfirmResult={ok:true}
   await change(viewing.id,-1,s=>{result=validateSet(s,exerciseId,setId);return result.ok?confirmSet(s,exerciseId,setId):false})
   if(result.ok)setNotice('Подход сохранён на устройстве')
   return result
  }catch(e){const message=e instanceof Error?e.message:'Ошибка сохранения';setError(message);return {ok:false,message}}
  finally{confirming.current.delete(setId);setBusy(false)}
 }
 async function finish(){
  if(!active)return
  await pending.current
  const latest=await db.sessions.get(active.id)
  if(!latest)return
  const left=latest.exercises.reduce((n,e)=>n+e.records.filter(r=>r.status==='draft').length,0)
  if(!await ask(left?`Завершить тренировку? Незаписанных подходов: ${left} — они станут пропущенными.`:'Завершить тренировку?','Завершить'))return
  if(await run(()=>change(active.id,-1,s=>{s.status='completed';s.completedAt=new Date().toISOString();s.restEndsAt=null;s.exercises.forEach(e=>e.records.forEach(r=>{if(r.status!=='completed')r.status='skipped'}))}),'Тренировка сохранена'))navigate({tab:'Сегодня',workoutOpen:false,summaryId:active.id},true)
 }
 async function cancelWorkout(){
  if(!active||!await ask('Отменить тренировку? Записи останутся в истории с пометкой «Отменена».','Отменить тренировку'))return
  if(await run(()=>change(active.id,-1,s=>{s.status='cancelled';s.completedAt=new Date().toISOString();s.restEndsAt=null})))navigate({tab:'Сегодня',workoutOpen:false,summaryId:active.id},true)
 }
 async function restDay(date:string,action:RestAction){
  if(action==='remove'){await run(()=>lifecycleChange('calendar',calendar.find(entry=>entry.date===date)?.id??'','delete'),'Отдых убран');return}
  await run(()=>db.transaction('rw',db.calendar,async()=>{
   const existing=(await db.calendar.where('date').equals(date).toArray()).find(visible)
   if(action==='plan'){
    if(existing)throw new Error('На эту дату отдых уже добавлен.')
    await db.calendar.add(calendarSchema.parse({id:uid(),name:'День отдыха',date,status:'planned'}));return
   }
   if(!existing)throw new Error('Запись изменилась.')
   await db.calendar.put({...existing,status:existing.status==='planned'?'completed':'planned'})
  }),action==='plan'?'Отдых запланирован':'Отдых обновлён')
 }
 async function begin(p:Program,d:Program['days'][number]){
  askRestNotice()
  const optional=offerWeeklyOptional(p.id,d,sessions)&&await ask('Добавить необязательный блок: '+d.exercises.filter(e=>e.optionalWeekly).map(e=>e.name).join(', ')+'?','Добавить')
  if(await run(()=>start(p,d,optional),'Тренировка началась'))navigate({tab:'Сегодня',workoutOpen:true})
 }
 function createProgram(){localStorage.setItem('traininglog-new-program',JSON.stringify(newProgram));setSelectedProgram('new');navigate({tab:'Программы',workoutOpen:false,programEditing:true,editProgramId:newProgram.id})}
 async function programLifecycle(action:'archive'|'delete'){
  if(!program)return
  if(action==='delete'&&!await ask(`Переместить «${program.name}» в корзину? Программу можно восстановить в настройках.`,'Переместить'))return
  if(await run(()=>lifecycleChange('programs',program.id,action),action==='archive'?'Программа в архиве':'Программа в корзине'))setSelectedProgram('')
 }
 const restTimer=active?.restEndsAt&&inWorkout?<RestTimer endsAt={active.restEndsAt} now={now} disabled={disabled} onAdjust={ms=>mutate(s=>{s.restEndsAt=Math.max(Date.now(),(s.restEndsAt??Date.now())+ms)})} onClose={()=>mutate(s=>{s.restEndsAt=null})}/>:undefined
 return <div className={`app ${inWorkout?'workout-active':''}`}>
  <MobileViewport/>
  {!inWorkout&&<nav aria-label="Разделы дневника">{tabs.map(t=><button key={t.name} className={route.tab===t.name?'selected':''} aria-current={route.tab===t.name?'page':undefined} onClick={()=>goTab(t.name)}><t.icon size={20}/><span>{t.name}</span></button>)}</nav>}
  <main>
   {!inWorkout&&<div className="topbar"><h1>{route.viewId?'Тренировка':route.tab}</h1><button className={`icon ${route.tab==='Настройки'?'selected':''}`} aria-label="Настройки" onClick={()=>goTab('Настройки')}><Settings size={20}/></button></div>}
   <OfflineStatus showCheck={route.tab==='Настройки'} blockedReason={busy?'Дождитесь завершения сохранения.':route.programEditing||route.editingHistory?'Сохраните или закройте редактор перед обновлением.':''} beforeReload={prepareUpdate} onReloading={setUpdating}/>
   {error&&<div className="alert" role="alert">{error}</div>}
   {!editable&&lockReady&&<div className="alert">Режим чтения. Дневник открыт в другой вкладке — закройте её, чтобы продолжить запись.</div>}
   <div className="save-status" aria-live="polite" key={notice}>{notice}</div>
   {!inWorkout&&<SyncStatus controller={sync} localStatus={error?'Проверьте сообщение об ошибке':busy||notice.startsWith('Сохраняем')?'Сохраняем…':notice?'Сохранено на устройстве':'Дневник на устройстве'} onOpen={()=>navigate({tab:'Настройки',workoutOpen:false,settingsSection:'sync'})}/>}
   {!data&&<p>Открываем дневник…</p>}
   {active&&!inWorkout&&<button className="primary resume-workout" onClick={()=>navigate({tab:'Сегодня',workoutOpen:true})}>Продолжить тренировку · {active.name}</button>}

   {route.tab==='Сегодня'&&!inWorkout&&data&&<>
    {summary&&<section className="card workout-summary"><span className="eyebrow">{summary.status==='cancelled'?'Тренировка отменена':'Тренировка завершена'}</span><h2>{summary.name}</h2><p>{summary.exercises.filter(e=>e.records.some(r=>r.status==='completed')).length} упражнений · {completedCount(summary)} подходов выполнено · {summary.exercises.reduce((n,e)=>n+e.records.filter(r=>r.status==='skipped').length,0)} пропущено</p><button className="primary" onClick={()=>openSession(summary.id,'История')}>Посмотреть запись</button></section>}
    {!active&&<TodayScreen programs={programs} program={program} sessions={sessions} disabled={disabled} restToday={restToday} onSelect={setSelectedProgram} onStart={(p,d)=>void begin(p,d)} onCreate={createProgram} seeds={<SeedPrograms disabled={disabled} programs={programs} program={program} run={run} onSelectProgram={setSelectedProgram} refresh={()=>{}}/>}/>}
   </>}

   {route.exerciseKey&&data&&<ExerciseScreen sessions={sessions} contextKey={route.exerciseKey} onOpen={id=>navigate({...route,exerciseKey:undefined,viewId:id})} onBack={()=>navigate({...route,exerciseKey:undefined})}/>}
   {!route.exerciseKey&&viewing&&((route.tab==='Сегодня'&&inWorkout)||(route.tab==='История'&&route.viewId))&&<>
    {route.viewId&&<div className="actions"><button className="ghost" onClick={closeSession}>{route.origin==='Прогресс'?'К прогрессу':'К истории'}</button>{!route.editingHistory&&<button className="ghost" disabled={disabled} onClick={()=>navigate({...route,editingHistory:{}})}>Исправить запись</button>}</div>}
    {route.editingHistory?<HistoryEditor key={viewing.id} initial={viewing} initialExerciseId={route.editingHistory.exerciseId} initialSetId={route.editingHistory.setId} disabled={disabled} onClose={()=>navigate({...route,editingHistory:undefined},true)}/>:<WorkoutScreen key={viewing.id} session={viewing} sessions={sessions} programs={programs} disabled={disabled} editorKey={editorKey} run={run} mutate={mutate} draft={draft} confirm={confirm} change={change} finish={()=>void finish()} cancel={()=>void cancelWorkout()} restTimer={restTimer} onCollapse={()=>navigate({tab:'Сегодня',workoutOpen:false})} onEditSet={(exerciseId,setId)=>navigate({...route,editingHistory:{exerciseId,setId}})} onOpenExercise={key=>navigate({...route,exerciseKey:key})}/>}
    {route.viewId&&!route.editingHistory&&<div className="actions"><button className="ghost" disabled={disabled} onClick={()=>void run(()=>lifecycleChange('sessions',viewing.id,'archive'),'Тренировка в архиве').then(ok=>{if(ok)closeSession()})}>В архив</button><button className="ghost danger" disabled={disabled} onClick={()=>void ask('Переместить тренировку в корзину? Её можно восстановить в настройках.','Переместить').then(async ok=>{if(ok&&await run(()=>lifecycleChange('sessions',viewing.id,'delete'),'Тренировка в корзине'))closeSession()})}>В корзину</button></div>}
   </>}
   {route.viewId&&!viewing&&!route.exerciseKey&&data&&<section className="card"><p>Запись недоступна. Проверьте архив и корзину.</p><button onClick={closeSession}>Назад</button></section>}
   {route.tab==='Прогресс'&&data&&<Progress sessions={sessions} state={progressState} onStateChange={setProgressState} onOpen={id=>openSession(id,'Прогресс')}/>}
   {route.tab==='Программы'&&data&&<>
    {!route.programEditing&&<div className="actions"><button className="ghost" disabled={disabled} onClick={createProgram}><Plus size={16}/> Новая программа</button>{programs.length>1&&<label className="program-pick">Текущая программа<select value={program?.id??''} onChange={e=>setSelectedProgram(e.target.value)}>{programs.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}</div>}
    {route.programEditing?(editorProgram?<fieldset disabled={disabled}><ProgramEditor key={`${editorTargetId}-${editorKey}`} initial={editorProgram} onCancel={()=>{if(editorTargetId===newProgram.id){localStorage.removeItem('traininglog-new-program');setNewProgram(blankProgram());setSelectedProgram('')}navigate({...route,programEditing:false,editProgramId:undefined},true)}} save={async(p,original)=>{
     const ok=await run(async()=>{await db.transaction('rw',db.programs,async()=>{const current=await db.programs.get(p.id);if(current&&(current.version!==p.version-1||canonical(current)!==canonical(original)))throw new Error('Программа обновилась на другом устройстве. Черновик сохранён; отмените правки, чтобы открыть новую версию.');if(!current&&p.id!==newProgram.id)throw new Error('Исходная программа больше недоступна. Черновик сохранён.');await db.programs.put(programSchema.parse(p))})},'Программа сохранена.')
     if(ok){setSelectedProgram(p.id);if(editorTargetId===newProgram.id){localStorage.removeItem('traininglog-new-program');setNewProgram(blankProgram())}navigate({...route,programEditing:false,editProgramId:undefined},true)}return ok
    }}/></fieldset>:<section className="card"><p>Программа недоступна. Откройте список программ или восстановите её из корзины.</p><button onClick={()=>navigate({tab:'Программы',workoutOpen:false},true)}>К программам</button></section>):program?<ProgramOverview program={program} disabled={disabled} onEdit={()=>{setSelectedProgram(program.id);navigate({...route,programEditing:true,editProgramId:program.id})}} onArchive={()=>void programLifecycle('archive')} onDelete={()=>void programLifecycle('delete')}/>:<section className="card empty"><h2>Добавьте первую программу</h2><button className="primary" disabled={disabled} onClick={createProgram}>Создать программу</button></section>}
    {!route.programEditing&&<section className="card"><h2>Готовые программы</h2><SeedPrograms disabled={disabled} programs={programs} program={program} run={run} onSelectProgram={setSelectedProgram} refresh={()=>{}}/></section>}
   </>}
   {route.tab==='История'&&!route.viewId&&data&&<HistoryScreen sessions={sessions} programs={data.programs} calendar={calendar} filters={historyFilters} disabled={disabled} onFilters={setHistoryFilters} onOpen={id=>openSession(id,'История')} onRest={(date,action)=>void restDay(date,action)}/>}
   {route.tab==='Настройки'&&data&&<SettingsScreen disabled={disabled} editable={editable} programs={programs} program={program} run={run} refresh={()=>{setEditorKey(k=>k+1);if(!localStorage.getItem('traininglog-new-program'))setNewProgram(blankProgram())}} onSelectProgram={setSelectedProgram} ask={ask} sync={sync} section={route.settingsSection} onSectionChange={settingsSection=>navigate({...route,settingsSection})}/>}
  </main>{dialog}
 </div>
}
