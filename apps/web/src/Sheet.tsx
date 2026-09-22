import { useEffect, useRef, useState, type ReactNode } from 'react'
import { X } from 'lucide-react'

const dialogs: HTMLElement[] = []
let previousOverflow = ''
let pointerTrigger:{element:HTMLElement;at:number}|null=null
// Safari touch clicks do not focus buttons. Remember the actual opener before rendering a sheet.
if(typeof document!=='undefined')document.addEventListener('pointerdown',event=>{
 const target=event.target instanceof Element?event.target.closest<HTMLElement>('button, a[href], input, select, textarea, [tabindex]'):null
 pointerTrigger=target?{element:target,at:performance.now()}:null
},true)
const focusable = (panel: HTMLElement) => Array.from(panel.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex="0"]')).filter(el => el.getClientRects().length > 0)

/** A sheet owns focus until it closes; renders and timer ticks never reset it. */
export function Sheet({title,onClose,children,role='dialog'}:{title:string;onClose:()=>void;children:ReactNode;role?:'dialog'|'alertdialog'}) {
 const panel=useRef<HTMLDivElement>(null)
 const close=useRef(onClose)
 useEffect(()=>{close.current=onClose},[onClose])
 useEffect(()=>{
  const element=panel.current
  if(!element)return
  const active=document.activeElement instanceof HTMLElement?document.activeElement:null
  const opener=pointerTrigger?.element.isConnected&&performance.now()-pointerTrigger.at<1000?pointerTrigger.element:active
  if(!dialogs.length){previousOverflow=document.body.style.overflow;document.body.style.overflow='hidden'}
  dialogs.push(element)
  element.focus()
  const top=()=>dialogs[dialogs.length-1]===element
  const key=(event:KeyboardEvent)=>{
   if(!top())return
   if(event.key==='Escape'){event.preventDefault();event.stopPropagation();close.current();return}
   if(event.key!=='Tab')return
   const items=focusable(element),first=items[0],last=items[items.length-1]
   if(!first){event.preventDefault();element.focus();return}
   if(event.shiftKey&&(document.activeElement===first||document.activeElement===element)){event.preventDefault();last.focus()}
   else if(!event.shiftKey&&(document.activeElement===last||document.activeElement===element)){event.preventDefault();first.focus()}
  }
  const focus=(event:FocusEvent)=>{if(top()&&!element.contains(event.target as Node))(focusable(element)[0]??element).focus()}
  document.addEventListener('keydown',key)
  document.addEventListener('focusin',focus)
  return ()=>{
   document.removeEventListener('keydown',key)
   document.removeEventListener('focusin',focus)
   const index=dialogs.indexOf(element)
   if(index!==-1)dialogs.splice(index,1)
   if(!dialogs.length)document.body.style.overflow=previousOverflow
   if(opener?.isConnected)opener.focus()
  }
 },[])
 return <div className="sheet-backdrop" onClick={onClose}>
  <div className={`sheet ${role==='alertdialog'?'ask':''}`} role={role} aria-modal="true" aria-label={title} tabIndex={-1} ref={panel} onClick={e=>e.stopPropagation()}>
   <div className="sheet-head"><strong>{title}</strong><button type="button" className="icon" aria-label="Закрыть" onClick={onClose}><X size={20}/></button></div>
   <div className="sheet-body">{children}</div>
  </div>
 </div>
}

type Question={text:string;confirm:string;resolve:(ok:boolean)=>void}
export function useAsk() {
 const [question,setQuestion]=useState<Question|null>(null)
 const ask=(text:string,confirm='Да')=>new Promise<boolean>(resolve=>setQuestion({text,confirm,resolve}))
 const answer=(ok:boolean)=>{question?.resolve(ok);setQuestion(null)}
 const dialog=question?<Sheet title={question.text} role="alertdialog" onClose={()=>answer(false)}>
  <div className="ask-actions"><button type="button" className="primary" onClick={()=>answer(true)}>{question.confirm}</button><button type="button" onClick={()=>answer(false)}>Отмена</button></div>
 </Sheet>:null
 return {ask,dialog}
}
