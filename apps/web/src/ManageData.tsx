import { useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { db, lifecycleChange, type Kind } from './data'
import { equipmentSchema, formatWeight, modes, parseWeight, uid, visible, type Equipment, type Exercise } from './domain'

export function EquipmentPicker({ exercise, onChange }: { exercise: Exercise; onChange: (fields: Partial<Exercise>) => void }) {
 const items = useLiveQuery(() => db.equipment.toArray()) ?? []
 return <label>Из каталога оборудования<select value={items.some(x => x.id === exercise.equipmentId) ? exercise.equipmentId : ''} onChange={e => { const item = items.find(x => x.id === e.target.value); if (item) onChange({ equipmentId: item.id, equipment: item.name, mode: item.mode, stepGrams: item.stepGrams, availableGrams: item.availableGrams }) }}><option value="">Указать вручную</option>{items.filter(visible).map(item => <option key={item.id} value={item.id}>{item.name} · {modes[item.mode]}</option>)}</select></label>
}
export function TrackingFields({ exercise, onChange }: { exercise: Exercise; onChange: (fields: Partial<Exercise>) => void }) {
 return <><label>Что записывать<select value={exercise.tracking ?? 'reps'} onChange={e => onChange({ tracking: e.target.value as Exercise['tracking'] })}><option value="reps">Повторения</option><option value="duration">Длительность, секунды</option></select></label><label>Стороны<select value={exercise.unilateral ? 'separate' : 'both'} onChange={e => onChange({ unilateral: e.target.value === 'separate' })}><option value="both">Вместе</option><option value="separate">Левая и правая отдельно</option></select></label><label>Группа суперсета<input maxLength={50} placeholder="Например, A — одинаково у участников" value={exercise.supersetGroup === undefined ? (/^([A-Z])[12]\s*·\s*Суперсет/.exec(exercise.sourceNote ?? '')?.[1] ?? '') : exercise.supersetGroup ?? ''} onChange={e => onChange({ supersetGroup: e.target.value.trim() || null })} /></label></>
}
const kindNames = { programs: 'Программы', sessions: 'Тренировки', equipment: 'Оборудование', calendar: 'Дни отдыха' }
type Props = { disabled: boolean; run: (action: () => Promise<unknown>, message?: string) => Promise<boolean>; ask: (text: string, confirm?: string) => Promise<boolean>; section?: 'equipment' | 'archive' }
export default function ManageData({ disabled, run, ask, section }: Props) {
 const data = useLiveQuery(async () => ({ equipment: await db.equipment.toArray(), calendar: await db.calendar.toArray(), programs: await db.programs.toArray(), sessions: await db.sessions.toArray() }))
 const [editing, setEditing] = useState<Equipment | null>(null), [name, setName] = useState(''), [mode, setMode] = useState<Equipment['mode']>('Unspecified'), [step, setStep] = useState(''), [weights, setWeights] = useState('')
 const [search, setSearch] = useState(''), [archiveState, setArchiveState] = useState<'all' | 'archive' | 'trash'>('all'), [archiveKind, setArchiveKind] = useState<Kind | 'all'>('all')
 const [errors, setErrors] = useState<Record<string, string>>({})
 const reset = () => { setEditing(null); setName(''); setStep(''); setWeights(''); setMode('Unspecified'); setErrors({}) }
 const trash = (kind: Kind, id: string, title: string) => void ask(`Переместить «${title}» в корзину на всех устройствах? Запись можно восстановить в настройках.`, 'Переместить').then(ok => { if (ok) void run(() => lifecycleChange(kind, id, 'delete')) })
 const archived = (Object.keys(kindNames) as Kind[]).flatMap(kind => (data?.[kind] ?? []).filter(item => !visible(item)).map(item => ({ kind, item })))
 const shown = archived.filter(({ kind, item }) => (archiveKind === 'all' || kind === archiveKind) && (archiveState === 'all' || (archiveState === 'trash' ? !!item.deletedAt : !item.deletedAt && !!item.archivedAt)) && item.name.toLocaleLowerCase('ru-RU').includes(search.trim().toLocaleLowerCase('ru-RU')))
 return <fieldset disabled={disabled}>
  <section className="card" hidden={!!section && section !== 'equipment'}><h2>Оборудование</h2><p>Шаг и список весов используются кнопками −/+ во время тренировки.</p>
   <form onSubmit={e => {
    e.preventDefault()
    const nextErrors: Record<string, string> = {}; let stepGrams: number | null = null; let availableGrams: number[] = []
    if (!name.trim()) nextErrors.name = 'Укажите название оборудования.'
    try { if (step.trim()) { stepGrams = parseWeight(step); if (!stepGrams) nextErrors.step = 'Шаг должен быть больше нуля.' } } catch (error) { nextErrors.step = (error as Error).message }
    try { if (weights.trim()) availableGrams = weights.split(';').map(value => parseWeight(value)); if (availableGrams.length > 200) nextErrors.weights = 'Можно указать до 200 весов.' } catch { nextErrors.weights = 'Введите веса через точку с запятой, например 5; 7,5; 10.' }
    setErrors(nextErrors); if (Object.keys(nextErrors).length) return
    void run(async () => {
     const profile = equipmentSchema.parse({ ...editing, id: editing?.id ?? uid(), name: name.trim(), mode, stepGrams, availableGrams })
     await db.transaction('rw', db.equipment, async () => { if (editing && JSON.stringify(await db.equipment.get(editing.id)) !== JSON.stringify(editing)) throw new Error('Профиль обновился. Ваш ввод сохранён в форме; откройте профиль заново, чтобы применить правки к новой версии.'); await db.equipment.put(profile) }); reset()
    }, editing ? 'Оборудование сохранено' : 'Оборудование добавлено')
   }}><div className="form-grid">
    <label>Название оборудования<input required maxLength={2000} value={name} aria-invalid={!!errors.name} onChange={e => setName(e.target.value)} />{errors.name && <span className="field-error">{errors.name}</span>}</label>
    <label>Учёт веса<select value={mode} onChange={e => setMode(e.target.value as Equipment['mode'])}>{Object.entries(modes).map(([key, value]) => <option key={key} value={key}>{value}</option>)}</select></label>
    <label>Шаг веса, кг<input inputMode="decimal" placeholder="Неизвестен — оставьте пустым" value={step} aria-invalid={!!errors.step} onChange={e => setStep(e.target.value)} />{errors.step && <span className="field-error">{errors.step}</span>}</label>
    <label>Доступные веса, кг, через ;<input placeholder="5; 7,5; 10; 12,5" value={weights} aria-invalid={!!errors.weights} onChange={e => setWeights(e.target.value)} />{errors.weights && <span className="field-error">{errors.weights}</span>}</label>
   </div><button className="primary">{editing ? 'Сохранить оборудование' : 'Добавить оборудование'}</button>{editing && <button type="button" onClick={reset}>Отмена</button>}</form>
   {data?.equipment.filter(visible).map(item => <div className="manage-row" key={item.id}><strong>{item.name}</strong><p>{modes[item.mode]} · шаг {formatWeight(item.stepGrams ?? null)} кг</p><div className="actions"><button onClick={() => { setEditing(item); setName(item.name); setMode(item.mode); setStep(item.stepGrams ? formatWeight(item.stepGrams) : ''); setWeights((item.availableGrams ?? []).map(formatWeight).join('; ')); setErrors({}) }}>Изменить</button><button onClick={() => void run(() => lifecycleChange('equipment', item.id, 'archive'))}>В архив</button><button onClick={() => trash('equipment', item.id, item.name)}>В корзину</button></div></div>)}
  </section>
  <section className="card" hidden={!!section && section !== 'archive'}><h2>Архив и корзина</h2><p>Архив прячет запись из списков, корзина — ещё и из прогресса. Обе операции обратимы.</p>
   <p>В архиве: {archived.filter(({ item }) => !item.deletedAt).length} · В корзине: {archived.filter(({ item }) => !!item.deletedAt).length}</p>
   <div className="form-grid"><label>Поиск в архиве и корзине<input type="search" placeholder="Название записи" value={search} onChange={e => setSearch(e.target.value)} /></label><label>Расположение<select value={archiveState} onChange={e => setArchiveState(e.target.value as typeof archiveState)}><option value="all">Архив и корзина</option><option value="archive">Только архив</option><option value="trash">Только корзина</option></select></label><label>Тип записей<select value={archiveKind} onChange={e => setArchiveKind(e.target.value as typeof archiveKind)}><option value="all">Все типы</option>{Object.entries(kindNames).map(([kind, label]) => <option key={kind} value={kind}>{label}</option>)}</select></label></div>
   {!shown.length && <p>{archived.length ? 'По этим фильтрам ничего не найдено.' : 'Архив и корзина пусты.'}</p>}
   {(Object.keys(kindNames) as Kind[]).map(kind => { const entries = shown.filter(entry => entry.kind === kind); return entries.length ? <div key={kind}><h3>{kindNames[kind]} ({entries.length})</h3>{entries.map(({ item }) => <div className="manage-row" key={item.id}><strong>{item.name}</strong><p>{'localDate' in item ? item.localDate : 'date' in item ? item.date : ''} · {item.deletedAt ? 'В корзине' : 'В архиве'}</p><div className="actions"><button onClick={() => void run(() => lifecycleChange(kind, item.id, 'restore'), 'Запись восстановлена')}>Восстановить</button>{!item.deletedAt && <button onClick={() => trash(kind, item.id, item.name)}>В корзину</button>}</div></div>)}</div> : null })}
  </section>
 </fieldset>
}
