import { formatWeight, type Exercise, type Session, type SetRecord } from './domain'
import { matchingPreviousSet } from './workoutUx'

type SessionExercise=Session['exercises'][number]
export type Suggestion={weight:string;reps:string;duration:string;note?:string}
export type HistoryEntry={session:Session;exercise:SessionExercise}

/** Прибавка веса уместна, пока шаг не больше десятой части рабочего веса: на махах 10 кг следующая гантель — это +25 %. */
export const MAX_JUMP=0.1
/** Без этого упражнения дольше трёх недель прибавка не предлагается. */
export const LAYOFF_DAYS=21

/** Насколько повторения могут расти сверх названной цели, прежде чем менять вес. */
export const repWindow=(n:number)=>n<=6?2:n<=12?3:n<=20?5:8

/** «10 / 8 / 6 / 12» — цель по подходам, «8–12» — диапазон, «∞» — без числа. */
export function targetRange(target:string,ordinal:number):[number,number]|null {
 const parts=target.split('/')
 const part=(parts[Math.min(Math.max(ordinal,0),parts.length-1)]??'').trim()
 const numbers=(part.match(/\d+/g)??[]).map(Number).filter(n=>n>0&&n<=86400)
 if(!numbers.length)return null
 if(numbers.length>1)return [Math.min(...numbers),Math.max(...numbers)]
 return [numbers[0],numbers[0]+repWindow(numbers[0])]
}

/** Следующий вес по профилю оборудования. Для тренажёра с помощью прогресс — это меньше помощи. */
export function nextWeight(exercise:Pick<Exercise,'availableGrams'|'stepGrams'|'mode'>,grams:number,direction:1|-1):number|null {
 const step=exercise.mode==='AssistedBodyweight'?-direction:direction
 const values=[...new Set(exercise.availableGrams??[])].sort((a,b)=>a-b)
 if(values.length)return (step===1?values.find(v=>v>grams):values.slice().reverse().find(v=>v<grams))??null
 if(!exercise.stepGrams)return null
 const next=grams+step*exercise.stepGrams
 return next>=0&&next<=2000000?next:null
}

/** Формула Эпли: расчётный разовый максимум по весу и повторениям. */
export const epleyMax=(grams:number,count:number)=>grams*(1+count/30)
/** Формула Эпли: сколько повторений ожидать на новом весе после прибавки. */
export function epleyReps(fromGrams:number,fromReps:number,toGrams:number):number {
 if(fromGrams<=0||toGrams<=0)return fromReps
 return Math.max(1,Math.round(30*(epleyMax(fromGrams,fromReps)/toGrams-1)))
}

const done=(exercise:SessionExercise,record:SetRecord):number|null=>(exercise.tracking==='duration'?record.durationSeconds:record.count)??null
const ordinalOf=(exercise:SessionExercise,record:SetRecord)=>exercise.records.filter(r=>r.kind===record.kind&&(!exercise.unilateral||r.side===record.side)).findIndex(r=>r.id===record.id)

/** Занятие годится для прибавки, только если ни один рабочий подход не пропущен и не ниже своей цели. */
function solid(exercise:SessionExercise) {
 const working=exercise.records.filter(r=>r.kind==='working')
 if(!working.length||working.some(r=>r.status!=='completed'))return false
 return working.every(record=>{
  const range=targetRange(exercise.target,ordinalOf(exercise,record)),value=done(exercise,record)
  return !range||value===null||value>=range[0]
 })
}

/** Последние занятия с этим же упражнением, оборудованием и способом учёта веса, новые первыми. */
export function exerciseHistory(sessions:Session[],current:Session,exercise:Exercise,limit=3):HistoryEntry[] {
 const out:HistoryEntry[]=[]
 const candidates=sessions.filter(s=>s.status==='completed'&&!s.deletedAt&&s.id!==current.id&&s.startedAt<current.startedAt).sort((a,b)=>b.startedAt.localeCompare(a.startedAt))
 for(const session of candidates){
  const found=session.exercises.find(e=>e.variantId===exercise.variantId&&e.equipmentId===exercise.equipmentId&&e.mode===exercise.mode&&(e.tracking??'reps')===(exercise.tracking??'reps')&&!!e.unilateral===!!exercise.unilateral&&e.records.some(r=>r.status==='completed'&&r.kind==='working'))
  if(found)out.push({session,exercise:found})
  if(out.length>=limit)break
 }
 return out
}

const shape=(exercise:SessionExercise,grams:number|null,count:number):Suggestion=>({
 weight:exercise.mode==='BodyweightOnly'||grams===null?'':formatWeight(grams),
 reps:exercise.tracking==='duration'?'':String(count),
 duration:exercise.tracking==='duration'?String(count):'',
})

/**
 * Двойная прогрессия: сначала растут повторения до верха диапазона, затем вес.
 * Без указанной цели повторений приложение ничего не выдумывает и повторяет прошлый результат.
 * Вес поднимается только после двух занятий подряд на верхней границе с одним весом,
 * и только если шаг оборудования не слишком крупный для этого веса.
 */
export function suggestSet(exercise:SessionExercise,record:SetRecord,history:HistoryEntry[],today=new Date()):Suggestion|null {
 const last=history[0]
 const lastRecord=last?matchingPreviousSet(exercise,record,last.exercise):undefined
 const lastValue=lastRecord?done(exercise,lastRecord):null
 if(!last||!lastRecord||lastValue===null)return null
 const grams=lastRecord.loadGrams
 const repeat=(note?:string):Suggestion=>({...shape(exercise,grams,lastValue),note})
 if(record.kind==='warmup'||!exercise.target.trim())return repeat()
 if((today.getTime()-new Date(last.session.localDate+'T12:00:00').getTime())/86400000>LAYOFF_DAYS)return repeat('После перерыва — как в прошлый раз')

 const range=targetRange(exercise.target,ordinalOf(exercise,record))
 const bottom=range?range[0]:1,top=range?range[1]:null
 const step=exercise.tracking==='duration'?5:1
 const previousOf=(entry?:HistoryEntry)=>{
  const found=entry?matchingPreviousSet(exercise,record,entry.exercise):undefined
  return found&&found.loadGrams===grams?done(exercise,found):null
 }
 const beforeValue=previousOf(history[1]),thirdValue=previousOf(history[2])

 if(beforeValue!==null&&lastValue<=beforeValue&&(top===null||lastValue<top)) {
  const down=thirdValue!==null&&beforeValue<=thirdValue&&grams!==null?nextWeight(exercise,grams,-1):null
  if(down!==null)return {...shape(exercise,down,top??lastValue),note:'Шаг вниз — прогресса не было'}
  return repeat('Тот же вес — в прошлый раз без прогресса')
 }

 if(top!==null&&lastValue>=top&&grams!==null&&exercise.mode!=='BodyweightOnly') {
  const next=nextWeight(exercise,grams,1)
  if(next!==null) {
   const assisted=exercise.mode==='AssistedBodyweight'
   const affordable=assisted||grams===0||Math.abs(next-grams)/grams<=MAX_JUMP
   const confirmed=beforeValue!==null&&beforeValue>=top&&solid(last.exercise)
   if(confirmed&&(affordable||lastValue>=top+repWindow(top)))
    return shape(exercise,next,assisted||exercise.tracking==='duration'?bottom:Math.max(1,Math.min(top,epleyReps(grams,lastValue,next))))
   if(affordable)return repeat()
  }
 }
 return shape(exercise,grams,lastValue+step)
}
