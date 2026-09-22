import { expect, it } from 'vitest'
import { broSplit } from './broSplit'
import { confirmSet, makeSession, uid, type Exercise } from './domain'
import { defaultRest, restOf } from './restDefaults'

const ex=(name:string,extra:Partial<Exercise>={}):Exercise=>{
 const id=uid()
 return {id,variantId:id,equipmentId:id,name,equipment:'TEST ONLY',mode:'Unspecified',sets:3,target:'8–12',rest:null,...extra}
}

it('gives three minutes to the heaviest lifts and less to lighter work',()=>{
 expect(defaultRest(ex('Становая тяга со штангой'))).toBe(180)
 expect(defaultRest(ex('Тяга верхнего блока с небольшим отклонением'))).toBe(150)
 expect(defaultRest(ex('Pec Deck'))).toBe(120)
 expect(defaultRest(ex('Жим гантелей сидя'))).toBe(120)
 expect(defaultRest(ex('Подъём гантелей через стороны стоя'))).toBe(90)
 expect(defaultRest(ex('Сгибание рук с гантелями на наклонной скамье'))).toBe(90)
 expect(defaultRest(ex('Подъём на носки стоя в тренажёре'))).toBe(60)
 expect(defaultRest(ex('Скручивания стоя с канатом верхнего блока'))).toBe(60)
 expect(defaultRest(ex('Моё упражнение'))).toBe(90)
})

it('shortens the hop between superset partners and keeps a normal rest after the last one',()=>{
 expect(defaultRest(ex('Жим ногами в Cybex, средняя постановка',{sourceNote:'B1 · Суперсет с B2 · Темп 3/0/1/0'}))).toBe(30)
 expect(defaultRest(ex('Выпады с гантелями в ходьбе',{sourceNote:'B2 · Суперсет с B1'}))).toBe(120)
 expect(defaultRest(ex('Разгибание рук с канатом вниз',{sourceNote:'B2 · Суперсет с B1'}))).toBe(90)
 expect(defaultRest(ex('Моё упражнение',{supersetGroup:'Мой круг'}))).toBe(30)
 expect(defaultRest(ex('Моё упражнение',{supersetGroup:null}))).toBe(90)
})

it('never overrides a rest written in the program',()=>{
 expect(restOf(ex('Становая тяга со штангой',{rest:60}))).toBe(60)
 expect(restOf(ex('Становая тяга со штангой',{rest:0}))).toBe(0)
 expect(restOf(ex('Становая тяга со штангой'))).toBe(180)
})

it('writes the rest into a new session and starts the timer for an older one',()=>{
 const shoulders=broSplit.days.find(day=>day.name==='Плечи')!
 const session=makeSession(broSplit,shoulders)
 expect(shoulders.exercises[0].rest).toBeNull()
 expect(session.exercises[0].rest).toBe(120)
 const zero=makeSession(broSplit,shoulders)
 zero.exercises[0].rest=0
 const first=zero.exercises[0].records[0]
 first.weight='20';first.reps='10'
 confirmSet(zero,zero.exercises[0].id,first.id)
 expect(zero.restEndsAt).toBeNull()
 const old=makeSession(broSplit,shoulders)
 old.exercises[0].rest=null
 const record=old.exercises[0].records[0]
 record.weight='20';record.reps='10'
 confirmSet(old,old.exercises[0].id,record.id)
 expect(old.restEndsAt).toBeGreaterThan(Date.now())
})
