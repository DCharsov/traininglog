import 'fake-indexeddb/auto'
import { beforeEach, expect, it } from 'vitest'
import { belovedSplit as program, importBelovedSplit } from './belovedSplit'
import { broSplit } from './broSplit'
import { hypertrophyAB } from './hypertrophyAB'
import { db, exportData, start } from './data'
import { backupSchema, confirmSet, makeSession, programSchema, uid } from './domain'
import { nextDay } from './workoutFlow'

beforeEach(async () => { for (const table of db.tables) await table.clear() })

it('imports alongside existing programs once and preserves edits, lifecycle and history', async () => {
  await db.programs.bulkAdd([broSplit, hypertrophyAB])
  const existingSession = await start(broSplit, broSplit.days[0])
  await Promise.all([importBelovedSplit(), importBelovedSplit()])
  expect(await db.programs.count()).toBe(3)
  expect(await db.programs.get(broSplit.id)).toEqual(broSplit)
  expect(await db.programs.get(hypertrophyAB.id)).toEqual(hypertrophyAB)
  const edited = structuredClone(program)
  edited.name = 'Мои изменения'
  edited.days[0].exercises[0].sets = 2
  edited.archivedAt = new Date().toISOString()
  edited.deletedAt = new Date().toISOString()
  await db.programs.put(edited)
  expect(await importBelovedSplit()).toEqual(edited)
  expect(await db.programs.count()).toBe(3)
  const backup = backupSchema.parse(await exportData())
  expect(backup.sessions).toEqual([existingSession])
  expect(backup.programs.find(p => p.id === program.id)).toEqual(edited)
})

it('recognizes the seed key when an imported copy has a different document ID', async () => {
  const copy = { ...structuredClone(program), id: uid(), name: 'Переименованная программа' }
  await db.programs.add(copy)
  expect(await importBelovedSplit()).toEqual(copy)
  expect(await db.programs.count()).toBe(1)
})

it('keeps the three-day prescription and alternatives without adding legs to the third day', () => {
  expect(programSchema.parse(program)).toEqual(program)
  expect(program.name).toBe('Для Любименькой ❤️')
  expect(program.days.map(d => d.name)).toEqual(['Ноги + ягодицы', 'Спина + плечи', 'Руки + корпус'])
  expect(program.days.map(d => d.exercises.map(e => e.target))).toEqual([
    ['8–12', '8–12', '10–12', '10–15', '10–15', '15–20'],
    ['8–12', '8–12', '8–12', '12–15', '12–15', '12–15'],
    ['10–12', '10–15', '10–12', '8–10', '8–10', '10–12'],
  ])
  expect(program.days.map(d => d.exercises.reduce((n, e) => n + e.sets, 0))).toEqual([18, 17, 17])
  expect(program.days[2].exercises.map(e => e.muscle)).toEqual(['biceps', 'triceps', 'biceps', 'abs', 'abs', 'abs'])
  expect(program.days[1].exercises[5].sourceNote).toContain('2–3×12–15')
  expect(program.days[2].exercises[2].sourceNote).toContain('2–3×10–15')
  expect(program.sourceNote).toContain('Двойная прогрессия')
  expect(program.sourceNote).toContain('Гиперэкстензия')
  for (const day of program.days) for (const e of day.exercises) {
    expect(e.sourceNote).toContain('1–3 повтора в запасе')
    expect(e.stepGrams).toBeUndefined()
    expect(e.availableGrams).toBeUndefined()
  }
})

it('starts with blank actual results and records all prescribed sides without a weekly-optional gate', () => {
  const sessions = program.days.map(d => makeSession(program, d))
  expect(sessions.map(s => s.exercises.length)).toEqual([6, 6, 6])
  expect(sessions.map(s => s.exercises.reduce((n, e) => n + e.records.length, 0))).toEqual([21, 17, 26])
  for (const s of sessions) for (const e of s.exercises) {
    expect(e.records.every(r => r.status === 'draft' && r.weight === '' && r.reps === '' && r.rir === '' && r.loadGrams === null && r.count === null)).toBe(true)
    if (e.unilateral) expect(e.records.map(r => r.side)).toEqual(['left', 'right', 'left', 'right', 'left', 'right'])
  }
  const core = sessions[2].exercises[3]
  core.records[0].reps = '8'
  confirmSet(sessions[2], core.id, core.records[0].id)
  expect(core.records[0]).toMatchObject({ status: 'completed', side: 'left', count: 8, loadGrams: null })
  expect(core.records[1].status).toBe('draft')
  const lunges = sessions[0].exercises[1]
  lunges.records[0].weight = '5'
  lunges.records[0].reps = '10'
  confirmSet(sessions[0], lunges.id, lunges.records[0].id)
  expect(lunges.records[0].loadGrams).toBe(5000)
})

it('requires an equipment choice where the source does not specify the weight convention', () => {
  for (const day of program.days) {
    const session = makeSession(program, day)
    for (const e of session.exercises.filter(e => e.requiresEquipment)) {
      const record = e.records[0]
      record.reps = '10'; record.weight = '20'
      expect(() => confirmSet(session, e.id, record.id)).toThrow('профиль')
      expect(record.status).toBe('draft')
      e.mode = 'MachinePlatesOnly'
      confirmSet(session, e.id, record.id)
      expect(record.loadGrams).toBe(20000)
    }
  }
})

it('cycles through all three days and keeps the session snapshot when the program is edited', async () => {
  await importBelovedSplit()
  for (let i = 0; i < program.days.length; i++) {
    const completed = makeSession(program, program.days[i])
    completed.status = 'completed'
    expect(nextDay(program, [completed]).day.id).toBe(program.days[(i + 1) % 3].id)
  }
  const session = await start(program, program.days[2])
  const edited = structuredClone(program)
  edited.days[2].exercises[3].sets = 1
  await db.programs.put(edited)
  expect((await db.sessions.get(session.id))?.exercises[3].records).toHaveLength(6)
})
