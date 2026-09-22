import { expect, it } from 'vitest'
import { exerciseName, guideFor, guides } from './exerciseLibrary'
import { broSplit } from './broSplit'
const assets=import.meta.glob('./assets/exercises/*.jpg',{query:'?url',import:'default'})
it('every source exercise has Russian text and two bundled photos',()=>{
 expect(guides).toHaveLength(28)
 for(const e of broSplit.days.flatMap(d=>d.exercises)){
  const g=guideFor(e)!;expect(g).toBeDefined();expect(e.name).toBe(g.ru);expect(g.images).toHaveLength(2)
  for(const image of g.images)expect(Object.hasOwn(assets,`./assets/exercises/${image}`)).toBe(true)
 }
})
it('localizes old snapshots without changing records or matching arbitrary edited names',()=>{
 const legacy={name:'Incline Pronated DB Bench Press',variantId:'keep',weight:'42'}
 expect(exerciseName(legacy)).toBe('Жим гантелей на наклонной скамье');expect(legacy.name).toBe('Incline Pronated DB Bench Press');expect(legacy.variantId).toBe('keep')
 expect(exerciseName({name:'Мой особый жим'})).toBe('Мой особый жим');expect(guideFor({name:'Incline Pronated DB Bench Press edited'})).toBeUndefined()
})
