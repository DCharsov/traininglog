import type { Session } from './domain'
import { dateKey } from './calendarMonth'

export const YEAR_WEEKS=53
export type YearCell={date:string;count:number;names:string[]}
/** Карта активности: 53 недели по 7 дней, последний столбец — текущая неделя. */
export function yearCells(sessions:Session[],today=new Date()):YearCell[] {
 const end=new Date(today.getFullYear(),today.getMonth(),today.getDate(),12)
 end.setDate(end.getDate()+6-((end.getDay()+6)%7))
 const start=new Date(end)
 start.setDate(start.getDate()-YEAR_WEEKS*7+1)
 const done=new Map<string,string[]>()
 for(const session of sessions){
  if(session.status!=='completed'||session.deletedAt)continue
  done.set(session.localDate,[...(done.get(session.localDate)??[]),session.name])
 }
 return Array.from({length:YEAR_WEEKS*7},(_,index)=>{
  const day=new Date(start);day.setDate(day.getDate()+index)
  const date=dateKey(day),names=done.get(date)??[]
  return {date,count:names.length,names}
 })
}
/** Подписи месяцев: столбец начала и сколько столбцов занимает месяц. */
export function monthLabels(cells:YearCell[]) {
 const labels:{month:string;column:number;span:number}[]=[]
 for(let column=0;column<cells.length/7;column++){
  const month=cells[column*7]?.date.slice(0,7)
  if(!month)continue
  const previous=labels[labels.length-1]
  if(previous&&previous.month===month)previous.span++
  else labels.push({month,column,span:1})
 }
 return labels
}
