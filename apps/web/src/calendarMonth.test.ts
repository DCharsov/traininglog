import { expect, it } from 'vitest'
import { makeSession, uid, type CalendarEntry, type Program, type Session } from './domain'
import { completedSets, dayMark, monthCells, monthName, shiftMonth } from './calendarMonth'

function fixture(name:string):Program {
 const id=uid()
 return {id:uid(),name:'TEST ONLY',version:1,days:[{id:uid(),name,exercises:[{id,variantId:id,equipmentId:id,name:'Тестовое упражнение',equipment:'TEST ONLY',mode:'SmithPlatesOnly',sets:2,target:'8–12',rest:90}]}]}
}
function session(name:string,date:string):Session {
 const value=makeSession(fixture(name),fixture(name).days[0])
 value.name=name;value.localDate=date;value.status='completed';value.startedAt=new Date(date+'T10:00:00Z').toISOString()
 value.exercises[0].records.forEach(record=>{record.status='completed';record.count=10;record.loadGrams=50000})
 return value
}
const rest=(date:string,status:CalendarEntry['status']):CalendarEntry=>({id:uid(),name:'День отдыха',date,status})

it('lays out a month starting on Monday and keeps every day in its own cell',()=>{
 const workout=session('Грудь','2026-09-15')
 const {blanks,cells}=monthCells('2026-09',[workout],[rest('2026-09-16','planned')],new Date('2026-09-17T12:00:00'))
 expect(blanks).toBe(1)
 expect(cells).toHaveLength(30)
 expect(cells[14]).toMatchObject({date:'2026-09-15',day:15,today:false})
 expect(cells[14].sessions[0].name).toBe('Грудь')
 expect(cells[15].rest?.status).toBe('planned')
 expect(cells[16].today).toBe(true)
 expect(cells[16].sessions).toHaveLength(0)
 expect(completedSets(workout)).toBe(2)
})

it('starts February 2027 on a Monday and keeps 28 days',()=>{
 const {blanks,cells}=monthCells('2027-02',[],[])
 expect(blanks).toBe(0)
 expect(cells).toHaveLength(28)
})

it('shortens the workout name for a cell',()=>{
 expect(dayMark('Тренировка А')).toBe('А')
 expect(dayMark('Грудь и трицепс')).toBe('ГР')
 expect(dayMark('Ноги')).toBe('НО')
 expect(dayMark('  ')).toBe('')
})

it('moves between months across a year boundary',()=>{
 expect(shiftMonth('2026-01',-1)).toBe('2025-12')
 expect(shiftMonth('2026-12',1)).toBe('2027-01')
 expect(shiftMonth('2026-03',-1)).toBe('2026-02')
})

it('writes the month name with a single capital letter',()=>{
 expect(monthName('2026-09')).toBe('Сентябрь 2026 г.')
})
