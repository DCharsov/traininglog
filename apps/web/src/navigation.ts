import { useEffect, useRef, useState } from 'react'
import type { SettingsSection } from './SettingsScreen'
export type Tab='Сегодня'|'Программы'|'История'|'Прогресс'|'Настройки'
export type Route={tab:Tab;workoutOpen:boolean;viewId?:string;exerciseKey?:string;origin?:'История'|'Прогресс';editingHistory?:{exerciseId?:string;setId?:string};programEditing?:boolean;editProgramId?:string;summaryId?:string;settingsSection?:SettingsSection|null}
export function readStored<T>(key:string,fallback:T):T {try{const raw=sessionStorage.getItem(key);return raw?JSON.parse(raw) as T:fallback}catch{return fallback}}
export function useNavigation() {
 const [route,setRoute]=useState<Route>(()=>readStored('traininglog-route',{tab:'Сегодня',workoutOpen:true}))
 const current=useRef(route),positions=useRef<Record<string,number>>({})
 const routeKey=(r:Route)=>`${r.tab}:${r.viewId??''}:${r.exerciseKey??''}:${r.editingHistory?.setId??''}:${r.programEditing??false}:${r.editProgramId??''}:${r.workoutOpen}:${r.settingsSection??''}`
 const apply=(next:Route)=>{
  positions.current[routeKey(current.current)]=window.scrollY
  current.current=next;setRoute(next);sessionStorage.setItem('traininglog-route',JSON.stringify(next))
  requestAnimationFrame(()=>window.scrollTo({top:positions.current[routeKey(next)]??0,behavior:'instant'}))
 }
 const navigate=(next:Route,replace=false)=>{window.history[replace?'replaceState':'pushState']({traininglog:next},'');apply(next)}
 useEffect(()=>{
  window.history.replaceState({traininglog:current.current},'')
  const back=(event:PopStateEvent)=>{if(event.state?.traininglog)apply(event.state.traininglog as Route)}
  window.addEventListener('popstate',back);return()=>window.removeEventListener('popstate',back)
 },[])
 return {route,navigate}
}
