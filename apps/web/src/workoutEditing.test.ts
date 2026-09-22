import { expect, it } from 'vitest'
import { broSplit } from './broSplit'
import { makeSession, uid } from './domain'
import { copyDay, moveItem, swapExercise } from './workoutEditing'
it('copies identities of day/items while retaining comparable exercise profiles',()=>{
 const p=structuredClone(broSplit),old=structuredClone(p.days[0]);copyDay(p,0)
 expect(p.days[1].id).not.toBe(old.id);expect(p.days[1].exercises[0].id).not.toBe(old.exercises[0].id)
 expect(p.days[1].exercises[0].variantId).toBe(old.exercises[0].variantId)
 expect(p.days[1].exercises[0].equipmentId).toBe(old.exercises[0].equipmentId)
 p.days[1].exercises[0].name='changed';expect(p.days[0]).toEqual(old)
 moveItem(p.days,1,-1);expect(p.days[0].exercises[0].name).toBe('changed')
 const order=p.days.map(d=>d.id);moveItem(p.days,0,-1);expect(p.days.map(d=>d.id)).toEqual(order)
})
it('replaces only an untouched snapshot and leaves program unchanged',()=>{
 const p=structuredClone(broSplit),s=makeSession(p,p.days[0]),old=structuredClone(p),id=s.exercises[0].id,replacement=p.days[1].exercises[0]
 expect(swapExercise(s,id,replacement)).toBe(false);expect(s.exercises).toHaveLength(p.days[0].exercises.length)
 expect(s.exercises[0].variantId).toBe(replacement.variantId);expect(s.exercises[0].id).not.toBe(replacement.id)
 expect(s.exercises[0].records.every(r=>r.status==='draft'&&r.weight===''&&r.count===null)).toBe(true);expect(p).toEqual(old)
 expect(()=>swapExercise(s,id,replacement)).toThrow('изменилось')
})
it('preserves even unfinished input when adding a replacement',()=>{
 const p=structuredClone(broSplit),s=makeSession(p,p.days[0]);s.exercises[0].records[0].weight='72,'
 const old=structuredClone(s.exercises[0]);expect(swapExercise(s,old.id,p.days[1].exercises[0])).toBe(true)
 expect(s.exercises[0]).toEqual(old);expect(s.exercises[1].records.every(r=>r.weight==='')).toBe(true)
 s.status='completed';expect(()=>swapExercise(s,old.id,p.days[1].exercises[0])).toThrow('активной')
})
it('enforces limits before mutation',()=>{
 const p=structuredClone(broSplit);p.days=Array.from({length:30},()=>({...structuredClone(p.days[0]),id:uid()}));expect(()=>copyDay(p,0)).toThrow();expect(p.days).toHaveLength(30)
 const s=makeSession(p,p.days[0]);s.exercises=Array.from({length:50},()=>({...structuredClone(s.exercises[0]),id:uid()}));s.exercises[0].records[0].note='keep'
 expect(()=>swapExercise(s,s.exercises[0].id,p.days[0].exercises[0])).toThrow();expect(s.exercises).toHaveLength(50)
})
