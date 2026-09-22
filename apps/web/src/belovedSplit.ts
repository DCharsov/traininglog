import { db } from './data'
import { programSchema, type Exercise } from './domain'

const stable = (n: number) => `be180926-0001-4000-8000-${String(n).padStart(12, '0')}`
type ExerciseOptions = Pick<Exercise, 'name' | 'equipment' | 'mode' | 'muscle' | 'target'> &
  Partial<Pick<Exercise, 'sets' | 'rest' | 'unilateral' | 'requiresEquipment' | 'sourceNote'>>

const exercise = (n: number, options: ExerciseOptions): Exercise => ({
  id: stable(n), variantId: stable(n), equipmentId: stable(n + 100),
  sets: 3, rest: 90, ...options,
  sourceNote: `Оставляй 1–3 повтора в запасе (RIR). ${options.sourceNote ?? ''}`.trim(),
})

export const belovedSplit = programSchema.parse({
  id: stable(1), seedKey: 'beloved-three-day-split', contentRevision: 1, version: 1,
  name: 'Для Любименькой ❤️',
  sourceNote: [
    '3 силовые тренировки в неделю: Пн — ноги + ягодицы; Ср — спина + плечи; Пт — руки + корпус. Дни можно менять. Плавание — между силовыми по желанию. При двух занятиях в неделю в исходном плане предложен отдельный full body; этот шаблон рассчитан на три дня.',
    'Двойная прогрессия: сначала увеличивай повторения в заданном диапазоне с прежним весом. Когда все рабочие подходы достигнут верхней границы с сохранной техникой и запасом 1–3 повтора, попробуй следующий доступный вес и снова двигайся от нижней границы. Пример для 3×8–12: 20 кг — 10/9/8 → 11/10/9 → 12/12/12; затем следующий вес — около 9/8/8. 20 кг — пример, не стартовая нагрузка. Фактический вес подбирается самостоятельно.',
    'Цель — 1–3 повтора в запасе (RIR). Если техника нарушается, появляются компенсации корпусом или дискомфорт в спине, снизь нагрузку; при боли прекрати упражнение.',
    'Отдых: гакк-присед, выпады, мост и тяги — 2–3 минуты (таймер 150 с); изоляция — 60–90 с (таймер 90 с); корпус — 45–90 с (таймер 60 с). Таймеры можно менять. Для face pull и молотковых сгибаний выбран нижний объём: 2 подхода из предложенных 2–3.',
    'Варианты: чередовать гакк-присед и присед с гирей по неделям; верхний блок заменять подтягиваниями; сгибания с гантелями — сгибаниями на блоке; молотковые сгибания — разгибанием руки из-за головы на блоке 2–3×10–15. Замены доступны через действия упражнения или редактор программы.',
    'Гиперэкстензия — необязательное дополнение к дню ног, 2–3×10–15 при хорошей переносимости; добавляется вручную. Сведения ног не обязательны. При включении и гакка, и приседа с гирей уменьшить изоляцию ног. В третий день ноги не добавлены.',
  ].join('\n\n'),
  days: [
    { id: stable(2), name: 'Ноги + ягодицы', exercises: [
      exercise(11, { name: 'Гакк-присед', equipment: 'Гакк-тренажёр · выбрать способ учёта веса', mode: 'Unspecified', requiresEquipment: true, muscle: 'quads', target: '8–12', rest: 150,
        sourceNote: '3×8–12. Отдых 2–3 минуты. Выбери профиль своего тренажёра: блины без платформы или стек. Неделя А — гакк-присед, неделя Б — присед с гирей вместо него; выпады остаются. Гиперэкстензию можно добавить отдельно в этот день: 2–3×10–15, если хорошо переносится. Сведения ног не обязательны.' }),
      exercise(12, { name: 'Выпады с гантелями', equipment: 'Гантели', mode: 'PerDumbbell', muscle: 'quads', target: '8–12', rest: 150, unilateral: true,
        sourceNote: '3×8–12 на каждую ногу. Вес указан для одной гантели; левую и правую стороны записывай отдельно. Отдых 2–3 минуты. Для выпадов без отягощения выбери «Собственный вес».' }),
      exercise(13, { name: 'Ягодичный мост', equipment: 'Штанга или тренажёр · выбрать профиль', mode: 'Unspecified', requiresEquipment: true, muscle: 'glutes', target: '10–12', rest: 150,
        sourceNote: '3×10–12. Отдых 2–3 минуты. Укажи фактическое оборудование и учёт веса: штанга вместе с грифом, блины тренажёра или стек.' }),
      exercise(14, { name: 'Сгибание ног в тренажёре', equipment: 'Тренажёр для сгибания ног', mode: 'MachineStack', muscle: 'hamstrings', target: '10–15',
        sourceNote: '3×10–15. Отдых 60–90 секунд. Для сравнения результатов используй тот же тренажёр и вариант сгибания.' }),
      exercise(15, { name: 'Разгибание ног в тренажёре', equipment: 'Тренажёр для разгибания ног', mode: 'MachineStack', muscle: 'quads', target: '10–15',
        sourceNote: '3×10–15. Отдых 60–90 секунд.' }),
      exercise(16, { name: 'Разведение ног в тренажёре', equipment: 'Тренажёр для разведения ног', mode: 'MachineStack', muscle: 'glutes', target: '15–20',
        sourceNote: '3×15–20. Отдых 60–90 секунд.' }),
    ] },
    { id: stable(3), name: 'Спина + плечи', exercises: [
      exercise(21, { name: 'Тяга верхнего блока к груди', equipment: 'Верхний блок', mode: 'MachineStack', muscle: 'back', target: '8–12', rest: 150,
        sourceNote: '3×8–12. Отдых 2–3 минуты. Можно заменить подтягиваниями: неделя 1 — верхний блок, неделя 2 — подтягивания; либо оставить подтягивания постоянно. Для замены выбери учёт собственного веса, помощи тренажёра или дополнительного веса по факту.' }),
      exercise(22, { name: 'Тяга горизонтального блока к животу', equipment: 'Горизонтальный блок', mode: 'MachineStack', muscle: 'back', target: '8–12', rest: 150,
        sourceNote: '3×8–12. Отдых 2–3 минуты.' }),
      exercise(23, { name: 'Тяга Хаммера', equipment: 'Хаммер для тяги · выбрать способ учёта веса', mode: 'Unspecified', requiresEquipment: true, muscle: 'back', target: '8–12', rest: 150,
        sourceNote: '3×8–12. Отдых 2–3 минуты. Выбери профиль конкретного тренажёра: блины или стек.' }),
      exercise(24, { name: 'Обратная бабочка', equipment: 'Тренажёр «обратная бабочка»', mode: 'MachineStack', muscle: 'shoulders', target: '12–15',
        sourceNote: '3×12–15. Задняя дельта. Отдых 60–90 секунд.' }),
      exercise(25, { name: 'Разведения гантелей в стороны сидя', equipment: 'Гантели и скамья', mode: 'PerDumbbell', muscle: 'shoulders', target: '12–15',
        sourceNote: '3×12–15. Записывай вес одной гантели. Отдых 60–90 секунд.' }),
      exercise(26, { name: 'Face pull — тяга каната к лицу', equipment: 'Блок с канатом', mode: 'MachineStack', muscle: 'shoulders', sets: 2, target: '12–15',
        sourceNote: '2–3×12–15; в шаблоне 2 подхода, третий можно добавить. Отдых 60–90 секунд.' }),
    ] },
    { id: stable(4), name: 'Руки + корпус', exercises: [
      exercise(31, { name: 'Сгибания рук с гантелями на бицепс', equipment: 'Гантели', mode: 'PerDumbbell', muscle: 'biceps', target: '10–12',
        sourceNote: '3×10–12. Вес одной гантели. Альтернатива — сгибание рук на блоке с соответствующим профилем оборудования. Отдых 60–90 секунд.' }),
      exercise(32, { name: 'Разгибание рук с канатом на трицепс', equipment: 'Верхний блок с канатом', mode: 'MachineStack', muscle: 'triceps', target: '10–15',
        sourceNote: '3×10–15. Отдых 60–90 секунд.' }),
      exercise(33, { name: 'Молотковые сгибания с гантелями', equipment: 'Гантели', mode: 'PerDumbbell', muscle: 'biceps', sets: 2, target: '10–12',
        sourceNote: '2–3×10–12; в шаблоне 2 подхода. Вес одной гантели. Вместо этого упражнения можно выбрать разгибание руки из-за головы на блоке: 2–3×10–15. Отдых 60–90 секунд.' }),
      exercise(34, { name: 'Dead bug', equipment: 'Коврик · собственный вес', mode: 'BodyweightOnly', muscle: 'abs', target: '8–10', rest: 60, unilateral: true,
        sourceNote: '3×8–10 на каждую сторону; стороны записываются отдельно. Отдых 45–90 секунд.' }),
      exercise(35, { name: 'Bird dog', equipment: 'Коврик · собственный вес', mode: 'BodyweightOnly', muscle: 'abs', target: '8–10', rest: 60, unilateral: true,
        sourceNote: '3×8–10 на каждую сторону; стороны записываются отдельно. Отдых 45–90 секунд.' }),
      exercise(36, { name: 'Pallof press', equipment: 'Блок', mode: 'MachineStack', muscle: 'abs', target: '10–12', rest: 60, unilateral: true,
        sourceNote: '3×10–12 на каждую сторону; стороны записываются отдельно. Отдых 45–90 секунд.' }),
    ] },
  ],
})

// Stable identity makes repeated imports safe, including after sync or a rename.
// Keep edited, archived and deleted copies intact; lifecycle changes are explicit.
export async function importBelovedSplit() {
  return db.transaction('rw', db.programs, async () => {
    const existing = await db.programs.filter(p => p.id === belovedSplit.id || p.seedKey === belovedSplit.seedKey).first()
    if (existing) return existing
    const program = structuredClone(belovedSplit)
    await db.programs.add(program)
    return program
  })
}
