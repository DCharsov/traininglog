import { z } from 'zod'
import { restOf } from './restDefaults'

export const modes = { Unspecified: 'Вес как записан · способ учёта уточнить', BarbellTotal: 'Штанга · вместе с грифом', SmithPlatesOnly: 'Смит · только блины', PerDumbbell: 'Вес одной гантели', MachinePlatesOnly: 'Блины на тренажёре, платформа не учтена', MachineStack: 'Стек тренажёра', AddedBodyweight: 'Дополнительный вес', AssistedBodyweight: 'Помощь тренажёра', BodyweightOnly: 'Собственный вес' } as const
export const muscleIds = ['chest','back','shoulders','biceps','triceps','forearms','quads','hamstrings','glutes','calves','abs'] as const
export type MuscleId = typeof muscleIds[number]
const id = z.string().uuid()
const text = z.string().max(2000)
const lifecycle = { archivedAt: z.string().datetime().nullable().optional(), deletedAt: z.string().datetime().nullable().optional() }
const weightProfile = { stepGrams: z.number().int().min(1).max(2000000).nullable().optional(), availableGrams: z.array(z.number().int().min(0).max(2000000)).max(200).optional() }
export const equipmentSchema = z.object({ id, name: text.min(1), mode: z.enum(Object.keys(modes) as [keyof typeof modes, ...(keyof typeof modes)[]]), ...weightProfile, ...lifecycle })
export const calendarSchema = z.object({ id, name: text.min(1), date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(d => { const n=new Date(d+'T00:00:00Z'); return Number.isFinite(n.getTime())&&n.toISOString().slice(0,10)===d }), status: z.enum(['planned','completed']), ...lifecycle })
export type Equipment = z.infer<typeof equipmentSchema>
export type CalendarEntry = z.infer<typeof calendarSchema>
export const visible = (doc: {deletedAt?: string|null; archivedAt?: string|null}) => !doc.deletedAt && !doc.archivedAt
export const sideNames = { both: 'Обе стороны', left: 'Левая', right: 'Правая' } as const
export const exerciseSchema = z.object({ muscle: z.enum(muscleIds).optional(), optionalWeekly: z.boolean().optional(), requiresEquipment: z.boolean().optional(), tracking: z.enum(['reps','duration']).optional(), unilateral: z.boolean().optional(), supersetGroup: text.max(50).nullable().optional(), ...weightProfile, id, variantId: id, equipmentId: id, name: text.min(1), equipment: text.min(1), mode: z.enum(Object.keys(modes) as [keyof typeof modes, ...(keyof typeof modes)[]]), sets: z.number().int().min(1).max(30), target: text, rest: z.number().int().min(0).max(1800).nullable(), sourceNote: text.optional() })
export const daySchema = z.object({ id, name: text.min(1), exercises: z.array(exerciseSchema).min(1).max(50) })
export const programSchema = z.object({ ...lifecycle, seedKey: text.optional(), contentRevision: z.number().int().positive().optional(), id, name: text.min(1), version: z.number().int().positive(), sourceNote: text.optional(), days: z.array(daySchema).min(1).max(30) })
export const setSchema = z.object({ duration: text.optional(), durationSeconds: z.number().int().min(1).max(86400).nullable().optional(), side: z.enum(['both','left','right']).optional(), id, status: z.enum(['draft', 'completed', 'skipped']), weight: text, reps: text, rir: text, note: text, kind: z.enum(['working', 'warmup']), loadGrams: z.number().int().min(0).max(2000000).nullable(), count: z.number().int().min(1).max(1000).nullable(), completedAt: z.string().nullable() })
export const sessionSchema = z.object({ ...lifecycle, id, programId: id, programVersion: z.number().int(), dayId: id, name: text, status: z.enum(['active', 'completed', 'cancelled']), startedAt: z.string().datetime(), completedAt: z.string().datetime().nullable(), localDate: z.string(), timezone: z.string(), revision: z.number().int().positive(), restEndsAt: z.number().nullable(), exercises: z.array(exerciseSchema.extend({ records: z.array(setSchema).max(100) })).max(50) })
export const backupSchema = z.object({ schemaVersion: z.union([z.literal(1),z.literal(2)]), equipment: z.array(equipmentSchema).max(1000).optional(), calendar: z.array(calendarSchema).max(10000).optional(), exportedAt: z.string(), programs: z.array(programSchema).max(100), sessions: z.array(sessionSchema).max(10000) }).superRefine((data, ctx) => {
  for (const items of [data.programs, data.sessions, data.equipment??[], data.calendar??[]]) if (new Set(items.map(x => x.id)).size !== items.length) ctx.addIssue({ code: 'custom', message: 'Повторяющиеся UUID' })
  if (data.sessions.filter(s => s.status === 'active' && !s.deletedAt).length > 1) ctx.addIssue({ code: 'custom', message: 'Больше одной активной тренировки' })
  for (const s of data.sessions) for (const e of s.exercises) for (const r of e.records) if (r.status === 'completed' && ((e.tracking==='duration' ? r.durationSeconds==null : r.count===null) || (e.mode !== 'BodyweightOnly' && r.loadGrams === null) || (e.unilateral && (!r.side || r.side==='both')))) ctx.addIssue({ code: 'custom', message: 'Неполный выполненный подход' })
})
export type Exercise = z.infer<typeof exerciseSchema>
export type Program = z.infer<typeof programSchema>
export type Day = z.infer<typeof daySchema>
export type SetRecord = z.infer<typeof setSchema>
export type Session = z.infer<typeof sessionSchema>
export type Backup = z.infer<typeof backupSchema>
export const uid = () => crypto.randomUUID()
export function parseWeight(value: string): number {
  const match = /^(\d{1,4})(?:[.,](\d{1,3}))?$/.exec(value.trim())
  if (!match) throw new Error('Введите вес, например 72,5. До трёх знаков после запятой.')
  const grams = Number(match[1]) * 1000 + Number((match[2] ?? '').padEnd(3, '0'))
  if (grams > 2000000) throw new Error('Вес должен быть от 0 до 2000 кг.')
  return grams
}
export const formatWeight = (grams: number | null) => grams === null ? '—' : (grams / 1000).toLocaleString('ru-RU', { maximumFractionDigits: 3, useGrouping: false })
export const emptySet = (): SetRecord => ({ id: uid(), status: 'draft', weight: '', reps: '', rir: '', note: '', kind: 'working', loadGrams: null, count: null, completedAt: null })
export function makeSession(program: Program, day: Day, includeOptional = false): Session {
  const now = new Date()
  return { id: uid(), programId: program.id, programVersion: program.version, dayId: day.id, name: day.name, status: 'active', startedAt: now.toISOString(), completedAt: null, localDate: `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, revision: 1, restEndsAt: null, exercises: day.exercises.filter(e=>!e.optionalWeekly || includeOptional).map(e => ({ ...structuredClone(e), rest: restOf(e), records: Array.from({ length: e.sets*(e.unilateral?2:1) }, (_,i)=>({...emptySet(), ...(e.unilateral?{side:i%2===0?'left' as const:'right' as const}:{})})) })) }
}
export function confirmSet(session: Session, exerciseId: string, setId: string): boolean {
  const e = session.exercises.find(e => e.id === exerciseId)!
  const r = e.records.find(r => r.id === setId)!
  if (r.status === 'completed') return false
  if(e.requiresEquipment && e.mode==='Unspecified') throw new Error('Сначала выберите профиль оборудования и способ учёта веса для этого упражнения.')
  if (e.tracking!=='duration' && (!/^\d{1,4}$/.test(r.reps) || Number(r.reps) < 1 || Number(r.reps) > 1000)) throw new Error('Повторения: целое число от 1 до 1000.')
  if (r.rir !== '' && (!/^\d{1,2}$/.test(r.rir) || Number(r.rir) > 10)) throw new Error('RIR: целое число от 0 до 10 или пустое поле.')
  r.loadGrams = e.mode === 'BodyweightOnly' ? null : parseWeight(r.weight)
  if(e.tracking==='duration' && (!/^\d{1,5}$/.test(r.duration??'') || Number(r.duration)<1 || Number(r.duration)>86400)) throw new Error('Длительность: целое число от 1 до 86400 секунд.')
  if(e.unilateral && r.side!=='left' && r.side!=='right') throw new Error('Выберите левую или правую сторону.')
  r.count = e.tracking==='duration' ? null : Number(r.reps)
  r.durationSeconds = e.tracking==='duration' ? Number(r.duration) : null
  r.side = e.unilateral ? r.side : 'both'
  r.status = 'completed'
  const first = r.completedAt === null
  r.completedAt = new Date().toISOString()
  if (first) { const rest = restOf(e); session.restEndsAt = rest > 0 ? Date.now() + rest * 1000 : null }
  return true
}
export function previous(sessions: Session[], current: Session, exercise: Exercise) {
  const candidates = sessions.filter(s => s.status === 'completed' && !s.deletedAt && s.id !== current.id && s.startedAt < current.startedAt).sort((a,b) => b.startedAt.localeCompare(a.startedAt))
  for (const sameItem of [true, false]) for (const s of candidates) {
    const e = s.exercises.find(e => (!sameItem || e.id === exercise.id) && e.variantId === exercise.variantId && e.equipmentId === exercise.equipmentId && e.mode === exercise.mode && (e.tracking??'reps')===(exercise.tracking??'reps') && !!e.unilateral===!!exercise.unilateral && e.records.some(r => r.status === 'completed' && r.kind === 'working'))
    if (e) return { session: s, exercise: e }
  }
}

/** Ближайший вес из профиля оборудования: гантели и наборы блинов существуют не в любом значении. */
export function snapWeight(exercise: Pick<Exercise,'availableGrams'>, grams: number): number {
  const values = [...new Set(exercise.availableGrams ?? [])].sort((a,b) => a-b)
  if (!values.length) return grams
  return values.reduce((best, v) => Math.abs(v-grams) < Math.abs(best-grams) ? v : best)
}

export function adjustedWeight(exercise: Pick<Exercise,'stepGrams'|'availableGrams'>, input:string, direction:1|-1):string {
  const current=parseWeight(input), values=[...new Set(exercise.availableGrams??[])].sort((a,b)=>a-b)
  const next=values.length ? (direction===1?values.find(v=>v>current):values.slice().reverse().find(v=>v<current)) : exercise.stepGrams ? current+direction*exercise.stepGrams : undefined
  if(next===undefined||next<0||next>2000000)throw new Error('Нет доступного веса в этом направлении. Введите вес вручную.')
  return formatWeight(next)
}
