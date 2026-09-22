import { expect, it } from 'vitest'
import { chartCoordinates, periodDates } from './progressChart'
import type { Point } from './progress'

const point=(date:string,value:number):Point=>({id:date,date,name:'Тренировка',value})
it('spaces dates proportionally rather than treating a month as a day',()=>{
 const layout=chartCoordinates([point('2026-01-01',10),point('2026-01-02',20),point('2026-01-11',30)])
 const [first,second,last]=layout.points
 expect((second.x-first.x)/(last.x-first.x)).toBeCloseTo(.1)
 expect(first.y).toBeGreaterThan(last.y)
})
it('centers a single date and constant values without NaN coordinates',()=>{
 const layout=chartCoordinates([point('2026-01-01',10),point('2026-01-01',10)])
 expect(layout.points.every(p=>Number.isFinite(p.x)&&Number.isFinite(p.y))).toBe(true)
 expect(layout.points[0].x).toBe(layout.points[1].x)
 expect(layout.points[0].y).toBe(layout.points[1].y)
})
it('clamps month presets at month end and crosses year boundaries in local dates',()=>{
 expect(periodDates(1,new Date(2026,2,31,23,30))).toEqual({from:'2026-02-28',to:'2026-03-31'})
 expect(periodDates(3,new Date(2026,0,15))).toEqual({from:'2025-10-15',to:'2026-01-15'})
})
