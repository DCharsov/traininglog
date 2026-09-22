import type { Document, Kind } from './data'
import { formatWeight, modes, sideNames, type Exercise, type Program, type Session } from './domain'

type Field = { label: string; value: string }
export type ConflictDifference = { label: string; local: string; remote: string }
const statuses: Record<string, string> = { active: 'Идёт', completed: 'Завершено', cancelled: 'Отменено', draft: 'Не выполнен', skipped: 'Пропущен', planned: 'Запланирован' }
const date = (value: string | null | undefined) => value ? new Date(value).toLocaleString('ru-RU') : '—'

/** Stable entity keys keep comparisons aligned when exercises or sets are reordered. */
function fields(kind: Kind, document?: Document): Map<string, Field> {
  const rows = new Map<string, Field>()
  if (!document) return rows
  const add = (key: string, label: string, value: unknown) => rows.set(key, { label, value: value === null || value === undefined || value === '' ? '—' : String(value) })
  add('name', 'Название', document.name)
  add('lifecycle', 'Расположение', document.deletedAt ? 'В корзине' : document.archivedAt ? 'В архиве' : 'В дневнике')
  const exercise = (item: Exercise, key: string, title: string) => {
    add(`${key}.name`, `${title} · название`, item.name)
    add(`${key}.equipment`, `${title} · оборудование`, item.equipment)
    add(`${key}.mode`, `${title} · учёт веса`, modes[item.mode])
    add(`${key}.sets`, `${title} · подходов`, item.sets)
    add(`${key}.target`, `${title} · цель`, item.target)
    add(`${key}.rest`, `${title} · отдых`, item.rest == null ? 'Без таймера' : `${item.rest} сек`)
    add(`${key}.tracking`, `${title} · запись результата`, item.tracking === 'duration' ? 'Секунды' : 'Повторения')
    add(`${key}.unilateral`, `${title} · стороны`, item.unilateral ? 'Раздельно' : 'Вместе')
    add(`${key}.superset`, `${title} · суперсет`, item.supersetGroup)
    add(`${key}.note`, `${title} · инструкция`, item.sourceNote)
    add(`${key}.optional`, `${title} · дополнительное упражнение`, item.optionalWeekly ? 'Да' : 'Нет')
    add(`${key}.step`, `${title} · шаг веса`, item.stepGrams == null ? '—' : `${formatWeight(item.stepGrams)} кг`)
    add(`${key}.weights`, `${title} · доступные веса`, item.availableGrams?.map(x => `${formatWeight(x)} кг`).join('; '))
  }
  if (kind === 'programs') {
    const program = document as Program
    add('note', 'Описание программы', program.sourceNote)
    program.days.forEach((day, dayIndex) => {
      add(`day.${day.id}.order`, `День «${day.name}» · порядок`, dayIndex + 1)
      add(`day.${day.id}.name`, `День ${dayIndex + 1} · название`, day.name)
      day.exercises.forEach((item, index) => {
        const key = `day.${day.id}.exercise.${item.id}`, title = `${day.name} · ${item.name}`
        add(`${key}.order`, `${title} · порядок`, index + 1)
        exercise(item, key, title)
      })
    })
  } else if (kind === 'sessions') {
    const session = document as Session
    add('date', 'Дата тренировки', session.localDate)
    add('status', 'Статус тренировки', statuses[session.status])
    add('started', 'Начало', date(session.startedAt)); add('completed', 'Завершение', date(session.completedAt))
    session.exercises.forEach((item, index) => {
      const key = `exercise.${item.id}`
      add(`${key}.order`, `${item.name} · порядок`, index + 1)
      exercise(item, key, item.name)
      item.records.forEach((record, recordIndex) => {
        const recordKey = `${key}.set.${record.id}`, title = `${item.name} · подход ${recordIndex + 1}`
        add(`${recordKey}.order`, `${title} · порядок`, recordIndex + 1)
        add(`${recordKey}.status`, `${title} · статус`, statuses[record.status])
        add(`${recordKey}.kind`, `${title} · тип`, record.kind === 'warmup' ? 'Разминка' : 'Рабочий')
        add(`${recordKey}.side`, `${title} · сторона`, sideNames[record.side ?? 'both'])
        add(`${recordKey}.weight`, `${title} · вес`, record.weight ? `${record.weight} кг` : record.loadGrams == null ? '—' : `${formatWeight(record.loadGrams)} кг`)
        add(`${recordKey}.reps`, `${title} · повторения`, record.reps || record.count)
        add(`${recordKey}.duration`, `${title} · секунды`, record.duration || record.durationSeconds)
        add(`${recordKey}.rir`, `${title} · запас повторений (RIR)`, record.rir)
        add(`${recordKey}.note`, `${title} · заметка`, record.note)
      })
    })
  } else if ('mode' in document) {
    add('mode', 'Учёт веса', modes[document.mode])
    add('step', 'Шаг веса', document.stepGrams == null ? '—' : `${formatWeight(document.stepGrams)} кг`)
    add('weights', 'Доступные веса', document.availableGrams?.map(x => `${formatWeight(x)} кг`).join('; '))
  } else if ('date' in document) {
    add('date', 'Дата отдыха', document.date); add('status', 'Статус отдыха', statuses[document.status])
  }
  return rows
}

export function conflictDifferences(kind: Kind, local?: Document, remote?: Document): ConflictDifference[] {
  const a = fields(kind, local), b = fields(kind, remote)
  return [...new Set([...a.keys(), ...b.keys()])].flatMap(key => {
    const left = a.get(key), right = b.get(key)
    return left?.value === right?.value ? [] : [{ label: right?.label ?? left!.label, local: left?.value ?? 'Нет в этой версии', remote: right?.value ?? 'Нет в этой версии' }]
  })
}
