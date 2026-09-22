import { useEffect, useRef, useState, type SetStateAction } from 'react'
import { db } from './data'
import type { Program, Session } from './domain'

/** Editor copies are local only. Their original revision is kept for conflict checks. */
export function useEditorDraft<T extends Program|Session>(kind:'program'|'history',initial:T) {
 const [value,setValueState]=useState<T>(()=>structuredClone(initial))
 const [original,setOriginal]=useState<T>(()=>structuredClone(initial))
 const [ready,setReady]=useState(false),[status,setStatus]=useState(''),[error,setError]=useState('')
 const current=useRef(value),baseline=useRef(original),mounted=useRef(false),queue=useRef(Promise.resolve()),failure=useRef<Error|null>(null)
 const key=`${kind}:${initial.id}`
 useEffect(()=>{
  mounted.current=true
  let cancelled=false
  void db.editorDrafts.get(key).then(saved=>{
   if(cancelled)return
   const next=structuredClone((saved?.value??initial) as T),base=structuredClone((saved?.original??initial) as T)
   current.current=next;baseline.current=base;setValueState(next);setOriginal(base)
   if(saved)setStatus('Черновик восстановлен')
   setReady(true)
  }).catch(()=>{if(!cancelled)setError('Не удалось открыть черновик. Перезагрузите страницу.')})
  return()=>{cancelled=true;mounted.current=false}
 // The owning editor is keyed by document id; remote changes must not replace its baseline.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[key])
 const setValue=(action:SetStateAction<T>)=>{
  if(!ready)return
  const next=typeof action==='function'?action(current.current):action
  current.current=next;setValueState(next);setStatus('Сохраняем черновик…')
  const entry={key,kind,original:structuredClone(baseline.current),value:structuredClone(next),updatedAt:new Date().toISOString()}
  queue.current=queue.current.then(async()=>{
   try{await db.editorDrafts.put(entry);failure.current=null;if(mounted.current){setError('');setStatus('Черновик сохранён')}}
   catch(e){failure.current=e instanceof Error?e:new Error('Не удалось сохранить черновик');if(mounted.current){setError('Черновик не сохранён. Повторите изменение перед выходом.');setStatus('')}}
  })
 }
 const flush=async()=>{await queue.current;if(failure.current)throw failure.current}
 const clear=async()=>{await queue.current;await db.editorDrafts.delete(key);failure.current=null;if(mounted.current){setStatus('');setError('')}}
 return {value,setValue,original,ready,status,error,clear,flush}
}
