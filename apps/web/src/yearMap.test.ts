import { expect, it } from 'vitest'
import { makeSession, uid, type Program, type Session } from './domain'
import { monthLabels, yearCells, YEAR_WEEKS } from './yearMap'

function fixture():Program {
 const id=uid()
 return {id:uid(),name:'TEST ONLY',version:1,days:[{id:uid(),name:'День',exercises:[{id,variantId:id,equipmentId:id,name:'Тест',equipment:'TEST ONLY',mode:'SmithPlatesOnly',sets:1,target:'8–12',rest:90}]}]}
}
function on(date:string,name='Грудь'):Session {
 const p=fixture(),session=makeSession(p,p.days[0])
 session.name=name;session.localDate=date;session.status='completed';session.startedAt=new Date(date+'T10:00:00Z').toISOString()
 return session
}

it('covers a full year of weeks and ends on the current week',()=>{
 const cells=yearCells([],new Date('2026-09-17T12:00:00'))
 expect(cells).toHaveLength(YEAR_WEEKS*7)
 expect(cells[0].date).toBe('2025-09-15')
 expect(cells[cells.length-1].date).toBe('2026-09-20')
 expect(new Date(cells[0].date+'T12:00:00').getDay()).toBe(1)
})

it('counts completed workouts per day and ignores deleted ones',()=>{
 const deleted=on('2026-09-15');deleted.deletedAt=new Date().toISOString()
 const cells=yearCells([on('2026-09-16'),on('2026-09-16','Спина'),deleted,on('2026-09-14')],new Date('2026-09-17T12:00:00'))
 const byDate=new Map(cells.map(cell=>[cell.date,cell]))
 expect(byDate.get('2026-09-16')?.count).toBe(2)
 expect(byDate.get('2026-09-16')?.names).toEqual(['Грудь','Спина'])
 expect(byDate.get('2026-09-15')?.count).toBe(0)
 expect(byDate.get('2026-09-14')?.count).toBe(1)
})

it('groups columns into month labels that cover every week',()=>{
 const labels=monthLabels(yearCells([],new Date('2026-09-17T12:00:00')))
 expect(labels.reduce((sum,label)=>sum+label.span,0)).toBe(YEAR_WEEKS)
 expect(labels[0].column).toBe(0)
 expect(new Set(labels.map(label=>label.month)).size).toBe(labels.length)
})
