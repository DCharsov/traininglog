import { useEffect, useRef, useState } from 'react'
import { restOver } from './haptics'

let audio:AudioContext|null=null
function beep() {
 try{
  audio=audio??new (window.AudioContext||(window as unknown as {webkitAudioContext:typeof AudioContext}).webkitAudioContext)()
  void audio.resume()
  const osc=audio.createOscillator(),gain=audio.createGain()
  osc.frequency.value=880;gain.gain.value=.0001
  osc.connect(gain);gain.connect(audio.destination)
  const t=audio.currentTime
  gain.gain.exponentialRampToValueAtTime(.25,t+.01);gain.gain.exponentialRampToValueAtTime(.0001,t+.5)
  osc.start(t);osc.stop(t+.5)
 }catch{/* звук не обязателен */}
}

/** Крупный отсчёт отдыха: виден с пола, сам вибрирует и пищит на нуле. */
export default function RestTimer({endsAt,now,disabled,onAdjust,onClose}:{endsAt:number;now:number;disabled:boolean;onAdjust:(ms:number)=>void;onClose:()=>void}) {
 const left=Math.max(0,Math.ceil((endsAt-now)/1000))
 const [total,setTotal]=useState(()=>Math.max(1,left))
 const fired=useRef(false)
 useEffect(()=>{setTotal(old=>Math.max(old,Math.ceil((endsAt-Date.now())/1000)));fired.current=false},[endsAt])
 useEffect(()=>{
  if(left>0||fired.current)return
  fired.current=true
  restOver()
  beep()
 },[left])
 const size=84,stroke=7,radius=(size-stroke)/2,length=2*Math.PI*radius
 const share=total?Math.min(1,left/total):0
 return <div className={`timer ${left?'':'over'}`} aria-label="Отдых между подходами">
  <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
   <circle cx={size/2} cy={size/2} r={radius} fill="none" stroke="var(--line)" strokeWidth={stroke}/>
   <circle cx={size/2} cy={size/2} r={radius} fill="none" stroke="var(--accent)" strokeWidth={stroke} strokeLinecap="round"
    strokeDasharray={length} strokeDashoffset={length*(1-share)} transform={`rotate(-90 ${size/2} ${size/2})`}/>
  </svg>
  <strong className="num" role="timer" aria-live="off">{left?`${Math.floor(left/60)}:${String(left%60).padStart(2,'0')}`:'Отдых окончен'}</strong>
  <span className="sr-only" role="status">{left?'':'Отдых окончен. Можно продолжать тренировку.'}</span>
  <div className="timer-actions">
   <button type="button" aria-label="Уменьшить отдых на 30 секунд" disabled={disabled} onClick={()=>onAdjust(-30000)}>−30 с</button>
   <button type="button" aria-label="Увеличить отдых на 30 секунд" disabled={disabled} onClick={()=>onAdjust(30000)}>+30 с</button>
   <button type="button" aria-label="Закрыть таймер" disabled={disabled} onClick={onClose}>{left?'Пропустить отдых':'Продолжить'}</button>
  </div>
 </div>
}
