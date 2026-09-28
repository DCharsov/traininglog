import { expect, it } from 'vitest'
import cases from '../../watch/WorkoutCore/Sources/WorkoutCore/Resources/progression-cases.json'
import { suggestSet, type HistoryEntry } from './progression'
import type { Session } from './domain'

for (const c of cases) it(`shared Swift progression: ${c.name}`, () => {
 const record = {id:'set',kind:c.kind??'working',status:'draft',side:'left'}
 const exercise = {...c,records:c.unilateral?[{...record,id:'right',side:'right'},record]:[record]}
 const history = c.values.map((value,index)=>({
  session:{localDate:c.old?'2026-07-01':`2026-09-${String(10-index*3).padStart(2,'0')}`},
  exercise:{...exercise,records:[
   ...(c.unilateral?[{...record,id:'right',side:'right',status:'completed',loadGrams:90000,count:99}]:[]),
   {...record,status:c.missing?'skipped':'completed',loadGrams:c.grams,count:value,durationSeconds:value},
   ...(c.skip&&index===0?[{...record,id:'skip',status:'skipped'}]:[]),
  ]},
 }))
 const result=suggestSet(exercise as unknown as Session['exercises'][number], record as Session['exercises'][number]['records'][number],history as unknown as HistoryEntry[], new Date(2026,8,17,12))
 expect(result===null?null:JSON.parse(JSON.stringify(result))).toEqual(c.expected)
})
