import { useEffect } from 'react'
type Lock={release:()=>Promise<void>;addEventListener:(t:string,f:()=>void)=>void}
/** Не даёт экрану гаснуть между подходами. Тихо ничего не делает там, где API нет. */
export function useWakeLock(active:boolean) {
 useEffect(()=>{
  const api=(navigator as Navigator&{wakeLock?:{request:(t:'screen')=>Promise<Lock>}}).wakeLock
  if(!active||!api)return
  let lock:Lock|null=null,disposed=false
  const acquire=async()=>{try{const next=await api.request('screen');if(disposed){void next.release();return}lock=next}catch{/* батарея, фон или отказ — молча */}}
  const revisit=()=>{if(document.visibilityState==='visible'&&!lock)void acquire()}
  void acquire()
  document.addEventListener('visibilitychange',revisit)
  return ()=>{disposed=true;document.removeEventListener('visibilitychange',revisit);void lock?.release();lock=null}
 },[active])
}
