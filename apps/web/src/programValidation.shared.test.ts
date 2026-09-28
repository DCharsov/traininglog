import {expect,it} from 'vitest'
import {programSchema} from './domain'
import cases from '../../watch/WorkoutCore/Sources/WorkoutCore/Resources/program-validation-cases.json'
import session from '../../watch/WorkoutCore/Sources/WorkoutCore/Resources/demo-session.json'

for(const c of cases) it(`shared Swift program validation: ${c.name}`,()=>{
 const exercise=structuredClone(session.exercises[0]) as Record<string,unknown>
 const day:Record<string,unknown>={id:session.dayId,name:'Day',exercises:[exercise]}
 const program:Record<string,unknown>={id:session.programId,name:'Program',version:1,days:[day]}
 const target=c.scope==='exercise'?exercise:c.scope==='day'?day:program
 target[c.key]=c.value
 expect(programSchema.safeParse(program).success).toBe(c.valid)
})
