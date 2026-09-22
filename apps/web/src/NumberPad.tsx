import { useState } from 'react'
import { Delete } from 'lucide-react'
import { keypadValue } from './workoutUx'

const digits=['1','2','3','4','5','6','7','8','9']
export default function NumberPad({value,decimal,onChange,onHide,onNext,nextLabel,disabled=false}:{value:string;decimal:boolean;onChange:(next:string)=>void;onHide:()=>void;onNext?:()=>void;nextLabel?:string;disabled?:boolean}) {
 const [replace,setReplace]=useState(true)
 const press=(key:string)=>{onChange(keypadValue(value,key,decimal,replace));setReplace(false)}
 const hold=(event:React.PointerEvent)=>event.preventDefault()
 return <div className="pad" role="group" aria-label="Цифровая панель">
  <button type="button" className="pad-clear" disabled={disabled} onPointerDown={hold} onClick={()=>press('clear')}>Очистить</button>
  {digits.map(d=><button key={d} type="button" disabled={disabled} onPointerDown={hold} onClick={()=>press(d)}>{d}</button>)}
  <button type="button" disabled={disabled||!decimal} onPointerDown={hold} aria-label="Запятая" onClick={()=>press(',')}>,</button>
  <button type="button" disabled={disabled} onPointerDown={hold} onClick={()=>press('0')}>0</button>
  <button type="button" disabled={disabled} onPointerDown={hold} aria-label="Стереть" onClick={()=>press('erase')}><Delete size={20}/></button>
  <div className="pad-footer"><button type="button" className="ghost" onPointerDown={hold} onClick={onHide}>Скрыть панель</button>{onNext&&<button type="button" disabled={disabled} onPointerDown={hold} onClick={onNext}>{nextLabel??'Далее'}</button>}</div>
 </div>
}
