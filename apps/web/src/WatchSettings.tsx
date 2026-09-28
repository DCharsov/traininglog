import { useState } from 'react'
import { api, authState, saveFile } from './sync'
import { getWatchDevices, type WatchDevice } from './watchApi'

export default function WatchSettings({disabled,run,ask}:{disabled:boolean;run:(fn:()=>Promise<unknown>,message?:string)=>Promise<boolean>;ask:(text:string,confirm?:string)=>Promise<boolean>}) {
 const [devices,setDevices]=useState<WatchDevice[]>([]),[code,setCode]=useState<{code:string;expiresAt:number}|null>(null),[enabled,setEnabled]=useState(false)
 const refresh=async()=>{await authState();const data=await getWatchDevices();setDevices(data.devices);setEnabled(data.enabled)}
 return <section className="card"><h2>Apple Watch</h2>
  <p>Начните тренировку на телефоне, затем передайте её часам. До подтверждения загрузки не отключайте сеть.</p>
  <button disabled={disabled} onClick={()=>void run(refresh,'Подключения обновлены')}>Проверить подключения</button>
  <button disabled={disabled||!enabled} onClick={()=>void run(async()=>{await authState();setCode(await api('/watch/pairing','POST',{}))},'Введите код на часах')}>Создать код подключения</button>
  {code&&<p>Код: <strong>{code.code}</strong> · до {new Date(code.expiresAt).toLocaleTimeString('ru-RU')}</p>}
  {!enabled&&<p>Подключение станет доступно после включения совместимой версии сервера.</p>}
  {devices.map(d=><div key={d.id}><p>{d.name} · {d.revokedAt?'доступ отозван':`последняя связь ${new Date(d.lastSeenAt).toLocaleString('ru-RU')}`}</p>
   {!d.revokedAt&&<button disabled={disabled} onClick={()=>void ask('Отозвать доступ часов? Неотправленные данные останутся на них. Если тренировка передана, затем потребуется аварийный возврат.','Отозвать').then(ok=>{if(ok)void run(async()=>{await api(`/watch/devices/${d.id}`,'DELETE');await refresh()},'Доступ отозван')})}>Отозвать доступ</button>}
  </div>)}
  <button disabled={disabled} onClick={()=>void run(async()=>{
   const rows=await api<{id:string}[]>('/watch/recovery')
   saveFile(await Promise.all(rows.map(r=>api(`/watch/recovery/${r.id}`))),'traininglog-watch-recovery.json')
  },'Восстановительные копии скачаны')}>Скачать восстановительные копии</button>
 </section>
}
