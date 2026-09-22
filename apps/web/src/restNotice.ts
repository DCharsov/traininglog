import { useEffect } from 'react'

/** Напоминание об окончании отдыха, когда приложение свёрнуто или экран погас. */
const TAG='traininglog-rest'
const api=()=>typeof Notification==='undefined'?undefined:Notification
const options={body:'Следующий подход.',tag:TAG,icon:`${import.meta.env.BASE_URL}icon-192.png`,badge:`${import.meta.env.BASE_URL}icon-192.png`}

/** Спрашиваем один раз, по нажатию «Начать тренировку». Отказ больше не тревожим. */
export function askRestNotice() {
 const notification=api()
 if(!notification||notification.permission!=='default')return
 try{void notification.requestPermission()}catch{/* старый браузер с колбэком — обойдёмся без напоминания */}
}

const registration=async()=>{try{return await navigator.serviceWorker?.getRegistration()}catch{return undefined}}

async function show() {
 const notification=api()
 if(!notification||notification.permission!=='granted'||document.visibilityState==='visible')return
 try{
  const worker=await registration()
  if(worker){await worker.showNotification('Отдых окончен',options);return}
  new Notification('Отдых окончен',options)
 }catch{/* уведомление необязательно */}
}

async function dismiss() {
 try{
  const worker=await registration()
  for(const item of await worker?.getNotifications({tag:TAG})??[])item.close()
 }catch{/* нечего закрывать */}
}

/** Держит одно отложенное напоминание на текущий отдых. */
export function useRestNotice(endsAt:number|null|undefined,active:boolean) {
 useEffect(()=>{
  if(!active||!endsAt)return
  const left=endsAt-Date.now()
  if(left<=0)return
  const timer=setTimeout(()=>{void show()},left)
  const onVisible=()=>{if(document.visibilityState==='visible')void dismiss()}
  document.addEventListener('visibilitychange',onVisible)
  return()=>{clearTimeout(timer);document.removeEventListener('visibilitychange',onVisible);void dismiss()}
 },[endsAt,active])
}
