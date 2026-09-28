import { useEffect, useState } from 'react'
import { api, authState, saveFile } from './sync'
import { getWatchDevices, type WatchDevice } from './watchApi'

export default function WatchSettings({disabled,run,ask}:{disabled:boolean;run:(fn:()=>Promise<unknown>,message?:string)=>Promise<boolean>;ask:(text:string,confirm?:string)=>Promise<boolean>}) {
 const [devices,setDevices]=useState<WatchDevice[]>([]),[windowEnds,setWindowEnds]=useState(0),[linkError,setLinkError]=useState('')
 const [requests,setRequests]=useState<{id:string;name:string;label:string;expiresAt:number}[]>([])
 const refresh=async()=>{await authState();const data=await getWatchDevices();setDevices(data.devices)}
 useEffect(()=>{
  if(!windowEnds)return
  let disposed=false,running=false
  const tick=async()=>{
   if(disposed||running||document.visibilityState!=='visible')return
   if(Date.now()>=windowEnds){setWindowEnds(0);setRequests([]);setLinkError('Время ожидания истекло. Нажмите «Подключить часы» ещё раз.');return}
   running=true
   try{const rows=await api<typeof requests>('/watch/link/requests');if(!disposed){setRequests(rows);setLinkError('')}}
   catch{if(!disposed)setLinkError('Не удалось проверить подключение. Проверьте сеть.')}
   finally{running=false}
  }
  void tick();const timer=setInterval(()=>void tick(),2000)
  return()=>{disposed=true;clearInterval(timer)}
 },[windowEnds])
 return <section className="card"><h2>Apple Watch</h2>
  <p>Начните тренировку на телефоне, затем передайте её часам. До подтверждения загрузки не отключайте сеть.</p>
  <button disabled={disabled} onClick={()=>void run(refresh,'Подключения обновлены')}>Проверить подключения</button>
  <button disabled={disabled||!!windowEnds} onClick={()=>void run(async()=>{await authState();const window=await api<{expiresAt:number}>('/watch/link/window','POST',{});setRequests([]);setLinkError('');setWindowEnds(window.expiresAt)},'На часах нажмите «Подключить» — ничего вводить не нужно')}>Подключить часы</button>
  {!!windowEnds&&<p>Теперь нажмите «Подключить» на часах. Затем подтвердите их здесь. Никаких кодов вводить не нужно.</p>}
  {requests.map(r=><div key={r.id}><p>{r.name}</p><strong>{r.label}</strong><p>На часах должны быть те же слова. Если слова отличаются, не подтверждайте.</p>
   <button disabled={disabled} onClick={()=>void run(async()=>{await api(`/watch/link/requests/${r.id}/approve`,'POST',{});setWindowEnds(0);setRequests([]);await refresh()},'Часы подключены. Можно передавать тренировку')}>Это мои часы</button>
  </div>)}
  {linkError&&<p role="status">{linkError}</p>}
  {devices.map(d=><div key={d.id}><p>{d.name} · {d.revokedAt?'доступ отозван':`последняя связь ${new Date(d.lastSeenAt).toLocaleString('ru-RU')}`}</p>
   {!d.revokedAt&&<button disabled={disabled} onClick={()=>void ask('Отозвать доступ часов? Неотправленные данные останутся на них. Если тренировка передана, затем потребуется аварийный возврат.','Отозвать').then(ok=>{if(ok)void run(async()=>{await api(`/watch/devices/${d.id}`,'DELETE');await refresh()},'Доступ отозван')})}>Отозвать доступ</button>}
  </div>)}
  <button disabled={disabled} onClick={()=>void run(async()=>{
   const rows=await api<{id:string}[]>('/watch/recovery')
   saveFile(await Promise.all(rows.map(r=>api(`/watch/recovery/${r.id}`))),'traininglog-watch-recovery.json')
  },'Восстановительные копии скачаны')}>Скачать восстановительные копии</button>
 </section>
}
