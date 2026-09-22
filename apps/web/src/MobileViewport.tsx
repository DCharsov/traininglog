import { useEffect } from 'react'
export default function MobileViewport() {
 useEffect(()=>{
  const viewport=window.visualViewport
  const update=()=>{
   const focused=document.activeElement
   const input=focused instanceof HTMLInputElement||focused instanceof HTMLTextAreaElement
   document.documentElement.classList.toggle('keyboard-open',input&&!!viewport&&window.innerHeight-viewport.height>150)
  }
  viewport?.addEventListener('resize',update);document.addEventListener('focusin',update);document.addEventListener('focusout',update)
  return ()=>{viewport?.removeEventListener('resize',update);document.removeEventListener('focusin',update);document.removeEventListener('focusout',update);document.documentElement.classList.remove('keyboard-open')}
 },[])
 return null
}
