import { useEffect, useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { watchControls } from './data'
import { getWatchDevices, type WatchDevice } from './watchApi'
import { handoffToWatch, refreshWatchControl, retryWatchCommand, returnWatchControl } from './watchControl'
import { syncOnce } from './sync'

type Props={id:string;disabled:boolean;enabled:boolean;run:(fn:()=>Promise<unknown>,message?:string)=>Promise<boolean>;ask:(text:string,confirm?:string)=>Promise<boolean>;beforeTransfer:()=>Promise<void>}
export default function WatchSessionPanel({id,disabled,enabled,run,ask,beforeTransfer}:Props) {
 const control=useLiveQuery(()=>watchControls.get(id),[id]),[devices,setDevices]=useState<WatchDevice[]>([]),[selected,setSelected]=useState(''),[checking,setChecking]=useState(false)
 useEffect(()=>{
  if(!enabled)return
  let running=false,failures=0,next=0,disposed=false
  const tick=async()=>{
   if(running||document.visibilityState!=='visible'||!navigator.onLine||Date.now()<next)return
   running=true;setChecking(true)
   try{await refreshWatchControl(id);const current=await watchControls.get(id);failures=0;next=Date.now()+(current&&current.state!=='phone'?5000:30000)}catch{next=Date.now()+Math.min(60000,5000*2**++failures)}
   finally{running=false;if(!disposed)setChecking(false)}
  }
  void tick()
  const timer=setInterval(()=>void tick(),5000)
  document.addEventListener('visibilitychange',tick)
  return()=>{disposed=true;clearInterval(timer);document.removeEventListener('visibilitychange',tick)}
 },[id,enabled,control?.state])
 if(!enabled&&!control)return null
 return <section className="card"><h2>Apple Watch</h2>
  <p>{control?.state==='watch'?'Управление на часах':control?.state==='offered'?'Ожидаем приёма на часах':control?.state==='preparing'?'Подтверждаем передачу':control?.state==='unknown'?'Проверяем управление':'Управление на телефоне'}{checking?' · проверка…':''}</p>
  {control?.checkedAt? <p>Последняя проверка: {new Date(control.checkedAt).toLocaleTimeString('ru-RU')}. Телефон показывает только доставленные записи.</p>:null}
  {(!control||control.state==='phone')&&<>
   <button disabled={disabled} onClick={()=>void run(async()=>{const result=await getWatchDevices();if(!result.enabled)throw new Error('Функция часов выключена на сервере');const available=result.devices.filter(d=>!d.revokedAt&&d.expiresAt>Date.now());setDevices(available);setSelected(available[0]?.id??'')},'Выберите часы')}>Выбрать часы</button>
   {!!devices.length&&<><select aria-label="Часы для тренировки" value={selected} onChange={e=>setSelected(e.target.value)}>{devices.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select><button disabled={disabled||!selected} onClick={()=>void run(async()=>{await beforeTransfer();await handoffToWatch(id,selected)},'Откройте TrainingLog на часах и примите тренировку')}>Продолжить на часах</button></>}
  </>}
  {control?.pending&&<button disabled={disabled} onClick={()=>void run(()=>retryWatchCommand(id),'Запрос подтверждён')}>Повторить подтверждение</button>}
  {control?.state==='offered'&&<button disabled={disabled} onClick={()=>void run(()=>returnWatchControl(id,false),'Передача отменена')}>Отменить передачу</button>}
  {(control?.state==='watch'||control?.state==='unknown')&&<button disabled={disabled} onClick={()=>void ask('Вернуть управление принудительно? На часах могут оставаться неотправленные подходы. Серверная копия будет сохранена для восстановления.','Вернуть управление').then(ok=>{if(ok)void run(()=>returnWatchControl(id,true),'Управление возвращено')})}>Аварийный возврат на телефон</button>}
  {control&&control.state!=='phone'&&<button disabled={disabled} onClick={()=>void run(async()=>{await refreshWatchControl(id);await syncOnce()},'Состояние обновлено')}>Обновить результаты</button>}
 </section>
}
