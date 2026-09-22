import type { Point } from './progress'

const dayTime=(date:string)=>Date.parse(date+'T00:00:00Z')
export function chartCoordinates(data:Point[],width=640,height=240) {
 const left=88,right=22,top=24,bottom=42
 const times=data.map(p=>dayTime(p.date)),first=Math.min(...times),last=Math.max(...times)
 const min=Math.min(...data.map(p=>p.value)),max=Math.max(...data.map(p=>p.value))
 return {min,max,left,right,top,bottom,points:data.map((p,i)=>({point:p,x:left+(first===last?.5:(times[i]-first)/(last-first))*(width-left-right),y:max===min?(top+height-bottom)/2:top+(max-p.value)/(max-min)*(height-top-bottom)}))}
}
export function periodDates(months:1|3,now=new Date()) {
 const end=new Date(now.getFullYear(),now.getMonth(),now.getDate()),start=new Date(end)
 const day=end.getDate();start.setDate(1);start.setMonth(start.getMonth()-months)
 start.setDate(Math.min(day,new Date(start.getFullYear(),start.getMonth()+1,0).getDate()))
 const localDate=(date:Date)=>`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`
 return {from:localDate(start),to:localDate(end)}
}
export const chartDate=(date:string)=>new Intl.DateTimeFormat('ru-RU',{day:'numeric',month:'short',timeZone:'UTC'}).format(dayTime(date))
