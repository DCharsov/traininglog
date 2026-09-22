import type { CalendarEntry, Session } from './domain'

export const dateKey=(date:Date)=>date.toLocaleDateString('sv-SE')
export const monthKey=(date:Date)=>dateKey(date).slice(0,7)
export const monthName=(month:string)=>new Date(month+'-01T12:00:00').toLocaleDateString('ru-RU',{month:'long',year:'numeric'}).replace(/^./,letter=>letter.toLocaleUpperCase('ru'))
export const dayName=(date:string)=>new Date(date+'T12:00:00').toLocaleDateString('ru-RU',{day:'numeric',month:'long'})
export function shiftMonth(month:string,step:number) {
 const date=new Date(month+'-01T12:00:00')
 date.setMonth(date.getMonth()+step)
 return monthKey(date)
}
/** Короткая метка занятия в клетке: «Тренировка А» → «А», «Грудь и трицепс» → «ГР». */
export function dayMark(name:string) {
 const words=name.trim().split(/\s+/).filter(Boolean)
 const last=words[words.length-1]??''
 if(words.length>1&&last.length<=2)return last.toLocaleUpperCase('ru')
 return (words[0]??'').slice(0,2).toLocaleUpperCase('ru')
}
export type DayCell={date:string;day:number;sessions:Session[];rest?:CalendarEntry;today:boolean}
/** Клетки месяца с ведущими пустыми днями до понедельника. */
export function monthCells(month:string,sessions:Session[],calendar:CalendarEntry[],today=new Date()) {
 const start=new Date(month+'-01T12:00:00')
 if(Number.isNaN(start.getTime()))return {blanks:0,cells:[] as DayCell[]}
 const blanks=(start.getDay()+6)%7
 const days=new Date(start.getFullYear(),start.getMonth()+1,0).getDate()
 const now=dateKey(today)
 const cells=Array.from({length:days},(_,index)=>{
  const day=index+1,date=`${month}-${String(day).padStart(2,'0')}`
  return {date,day,today:date===now,
   sessions:sessions.filter(s=>s.localDate===date).sort((a,b)=>a.startedAt.localeCompare(b.startedAt)),
   rest:calendar.find(entry=>entry.date===date)}
 })
 return {blanks,cells}
}
export const completedSets=(session:Session)=>session.exercises.reduce((total,exercise)=>total+exercise.records.filter(record=>record.status==='completed').length,0)
