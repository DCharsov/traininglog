import { expect, it } from 'vitest'
import { makeSession, uid, type Exercise, type Program, type Session } from './domain'
import { sessionRecords } from './records'

const ids={variant:uid(),equipment:uid()}
function fixture(extra:Partial<Exercise>={},sets=2):Program {
 return {id:uid(),name:'TEST ONLY',version:1,days:[{id:uid(),name:'День',exercises:[
  {id:uid(),variantId:ids.variant,equipmentId:ids.equipment,name:'Тест',equipment:'TEST ONLY',mode:'SmithPlatesOnly',sets,target:'8–12',rest:90,...extra}]}]}
}
function done(program:Program,date:string,results:{grams?:number|null;value:number}[],status:Session['status']='completed'):Session {
 const session=makeSession(program,program.days[0]),exercise=session.exercises[0]
 session.status=status;session.localDate=date;session.startedAt=new Date(date+'T10:00:00Z').toISOString()
 exercise.records.forEach((record,index)=>{
  const result=results[Math.min(index,results.length-1)]
  record.status='completed';record.completedAt=session.startedAt
  record.loadGrams=result.grams===undefined?50000:result.grams
  if(exercise.tracking==='duration')record.durationSeconds=result.value; else record.count=result.value
 })
 return session
}

it('marks a heavier set and a better estimated maximum, but never the very first result',()=>{
 const p=fixture()
 const first=done(p,'2026-09-01',[{grams:50000,value:10}])
 expect(sessionRecords([],first).size).toBe(0)
 const heavier=done(p,'2026-09-08',[{grams:52500,value:8}])
 expect(sessionRecords([first],heavier).get(heavier.exercises[0].records[0].id)).toBe('weight')
 const moreReps=done(p,'2026-09-08',[{grams:50000,value:12}])
 expect(sessionRecords([first],moreReps).get(moreReps.exercises[0].records[0].id)).toBe('max')
 const weaker=done(p,'2026-09-08',[{grams:50000,value:9}])
 expect(sessionRecords([first],weaker).size).toBe(0)
})

it('compares sets inside one session too',()=>{
 const p=fixture()
 const first=done(p,'2026-09-01',[{grams:50000,value:10}])
 const session=done(p,'2026-09-08',[{grams:50000,value:11},{grams:55000,value:6}])
 const found=sessionRecords([first],session)
 expect(found.get(session.exercises[0].records[0].id)).toBe('max')
 expect(found.get(session.exercises[0].records[1].id)).toBe('weight')
})

it('ignores warm-ups, skipped sets and unfinished sessions',()=>{
 const p=fixture()
 const first=done(p,'2026-09-01',[{grams:50000,value:10}])
 const cancelled=done(p,'2026-09-05',[{grams:90000,value:10}],'cancelled')
 const session=done(p,'2026-09-08',[{grams:60000,value:10}])
 session.exercises[0].records[0].kind='warmup'
 session.exercises[0].records[1].status='skipped'
 expect(sessionRecords([first,cancelled],session).size).toBe(0)
})

it('counts repetitions for bodyweight work and seconds for holds',()=>{
 const body=fixture({mode:'BodyweightOnly'})
 const beforeBody=done(body,'2026-09-01',[{grams:null,value:20}])
 const moreReps=done(body,'2026-09-08',[{grams:null,value:22}])
 expect(sessionRecords([beforeBody],moreReps).get(moreReps.exercises[0].records[0].id)).toBe('reps')
 const hold=fixture({mode:'BodyweightOnly',tracking:'duration'})
 const beforeHold=done(hold,'2026-09-01',[{grams:null,value:40}])
 const longer=done(hold,'2026-09-08',[{grams:null,value:45}])
 expect(sessionRecords([beforeHold],longer).get(longer.exercises[0].records[0].id)).toBe('duration')
})

it('treats less machine assistance as a record and keeps sides apart',()=>{
 const assisted=fixture({mode:'AssistedBodyweight'})
 const before=done(assisted,'2026-09-01',[{grams:30000,value:10}])
 const lighter=done(assisted,'2026-09-08',[{grams:25000,value:8}])
 expect(sessionRecords([before],lighter).get(lighter.exercises[0].records[0].id)).toBe('weight')
 const sided=fixture({unilateral:true},1)
 const past=done(sided,'2026-09-01',[{grams:20000,value:10},{grams:30000,value:10}])
 past.exercises[0].records[0].side='left';past.exercises[0].records[1].side='right'
 const now=done(sided,'2026-09-08',[{grams:22000,value:10},{grams:22000,value:10}])
 now.exercises[0].records[0].side='left';now.exercises[0].records[1].side='right'
 const found=sessionRecords([past],now)
 expect(found.get(now.exercises[0].records[0].id)).toBe('weight')
 expect(found.get(now.exercises[0].records[1].id)).toBeUndefined()
})
