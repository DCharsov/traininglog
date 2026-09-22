import { emptySet, exerciseSchema, uid, type Program, type Session, type Exercise } from './domain'
export function moveItem<T>(items:T[],index:number,offset:-1|1) {
 const target=index+offset
 if(index<0||index>=items.length||target<0||target>=items.length)return
 ;[items[index],items[target]]=[items[target],items[index]]
}
export function copyDay(program:Program,index:number) {
 if(program.days.length>=30)throw new Error('Не более 30 дней в программе.')
 const day=structuredClone(program.days[index]);if(!day)throw new Error('День не найден.')
 day.id=uid();day.name=(day.name.slice(0,1990)+' — копия')
 day.exercises.forEach(e=>e.id=uid())
 program.days.splice(index+1,0,day)
}
export function hasEntries(e:Session['exercises'][number]) {
 return e.records.some(r=>r.status!=='draft'||!!r.duration||r.durationSeconds!=null||r.weight!==''||r.reps!==''||r.rir!==''||r.note!==''||r.kind!=='working'||r.completedAt!==null||r.loadGrams!==null||r.count!==null)
}
export function swapExercise(session:Session,exerciseId:string,replacement:Exercise) {
 if(session.status!=='active')throw new Error('Заменять упражнения можно только в активной тренировке.')
 const index=session.exercises.findIndex(e=>e.id===exerciseId)
 if(index<0)throw new Error('Упражнение уже изменилось. Откройте замену заново.')
 const next=exerciseSchema.parse(replacement),old=session.exercises[index],keep=hasEntries(old)
 if(keep&&session.exercises.length>=50)throw new Error('Не более 50 упражнений в тренировке.')
 const snapshot={...next,id:uid(),records:Array.from({length:next.sets*(next.unilateral?2:1)},(_,i)=>({...emptySet(),...(next.unilateral?{side:i%2===0?'left' as const:'right' as const}:{})}))}
 session.exercises.splice(keep?index+1:index,keep?0:1,snapshot)
 return keep
}
