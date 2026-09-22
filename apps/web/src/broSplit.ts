import { exerciseName } from './exerciseLibrary'
import { programSchema, type Exercise } from './domain'
const stable = (n: number) => `b7050117-2026-4000-8000-${String(n).padStart(12, '0')}`
let counter = 10
function ex(name: string, reps: string, equipment: string, series: string, tempo = '', note = '', rest: number | null = null, bodyweight = false): Exercise {
  const id = stable(counter++)
  return { id, variantId: id, equipmentId: id, name: exerciseName({name}), equipment, mode: bodyweight ? 'BodyweightOnly' : 'Unspecified', sets: reps.split(' / ').length, target: reps, rest, sourceNote: `${series}${tempo ? ` · Темп ${tempo}` : ''}${note ? ` · ${note}` : ''}` }
}
const pyramid = '10 / 8 / 6 / 12', ten = '10 / 10 / 10', twenty = '20 / 20 / 20', thirty = '30 / 30 / 30', tempo = '3/0/1/0'
export const broSplit = programSchema.parse({
  id: stable(1), name: 'Bro Split · Фаза 1', version: 1,
  sourceNote: 'Перенесено со скриншотов STNDRD. Intermediate · 3 недели. Каждую неделю: грудь → спина → отдых → ноги → руки → плечи → отдых. Всего 21 день. На скриншотах отмечены дни 1–16, следующий — отдых, день 17; даты и выполненные подходы неизвестны. История не создаётся. Оценка приложения: 45 минут на занятие (обзор программы: 60–80). ∞ — цель без числового ограничения; записывайте фактически сделанные повторы. Неуказанный отдых оставлен пустым. Веса со скриншотов — справка, не выполненные результаты. Перед записью выберите способ учёта веса для своего оборудования.',
  days: [
    { id: stable(2), name: 'Грудь', exercises: [
      ex('Incline Pronated DB Bench Press', pyramid, 'Гантели · наклонная скамья', 'A', tempo, 'На экране: 40 / 56 / 60 / 56 кг; последний подход BO. Неясно, вес пары или одной гантели.', 90),
      ex('Flat Pronated DB Bench Press', ten, 'Гантели · горизонтальная скамья', 'B', '3/1/1/0', 'На экране: 60 / 60 / 60 кг; способ учёта не указан.', 90),
      ex('Hammer Strength Decline Chest Press', '15 / 15 / 15', 'Hammer Strength', 'C', tempo, 'На экране: 100 / 100 / 100 кг; способ учёта не указан.', 90),
      ex('Pec Deck', twenty, 'Pec Deck', 'D1 · Суперсет с D2', '', 'На экране: 41 / 41 / 41 кг; отдых 10 секунд.', 10),
      ex('Push Ups', '∞ / ∞ / ∞', 'Собственный вес', 'D2 · Суперсет с D1', '', '', null, true),
    ]},
    { id: stable(3), name: 'Спина', exercises: [
      ex('Lat Pulldown Lean Away Medium …', pyramid, 'Верхний блок', 'A', tempo, 'Название в источнике обрезано.'),
      ex('Hammer Strength Overhand Row', ten, 'Hammer Strength', 'B', '3/1/1/0'),
      ex('Chest Supported Incline Neut…', ten, 'Гантели · наклонная скамья', 'C1 · Суперсет с C2', '', 'Название в источнике обрезано.'),
      ex('DB Pullover', twenty, 'Гантель · скамья', 'C2 · Суперсет с C1'),
      ex('Seated Rear Delt Flys', thirty, 'Гантели · скамья', 'D'),
    ]},
    { id: stable(4), name: 'Ноги', exercises: [
      ex('Barbell Deadlift', pyramid, 'Штанга', 'A', tempo),
      ex('Cybex Medium Stance Leg Press', '15 / 15 / 15', 'Cybex · жим ногами', 'B1 · Суперсет с B2', tempo, 'На другом скриншоте заменено на Hack Squat Medium Stance, также 3×15. При замене задайте новый вариант и оборудование для отдельной истории.'),
      ex('DB Walking Lunges', twenty, 'Гантели', 'B2 · Суперсет с B1'),
      ex('Lying Leg Curl - Neutral (Dorsi…', ten, 'Тренажёр сгибания ног лёжа', 'C1 · Суперсет с C2', tempo, 'Название в источнике обрезано.'),
      ex('DB RDL', thirty, 'Гантели', 'C2 · Суперсет с C1'),
      ex('Standing Calf Raise Machine Me…', Array(10).fill('10').join(' / '), 'Тренажёр подъёма на носки', 'D', '', 'Название обрезано. 10 подходов; всего в тренировке 26.'),
    ]},
    { id: stable(5), name: 'Руки', exercises: [
      ex('Flat Bench DB Skull Crushers', pyramid, 'Гантели · горизонтальная скамья', 'A1 · Суперсет с A2', tempo),
      ex('Incline Supinated DB Curls', pyramid, 'Гантели · наклонная скамья', 'A2 · Суперсет с A1', tempo),
      ex('Cable Rope French Press', ten, 'Блок · канат', 'B1 · Суперсет с B2', tempo),
      ex('Cable Rope Tricep Pushdowns', twenty, 'Блок · канат', 'B2 · Суперсет с B1'),
      ex('Standing DB Hammer Curls', ten, 'Гантели', 'C1 · Суперсет с C2', tempo),
      ex('Cable Rope Hammer Curl', twenty, 'Блок · канат', 'C2 · Суперсет с C1'),
      ex('High Pulley Rope Cable Crunch', thirty, 'Верхний блок · канат', 'D'),
    ]},
    { id: stable(6), name: 'Плечи', exercises: [
      ex('Seated DB Shoulder Press', pyramid, 'Гантели · скамья', 'A', tempo),
      ex('Cable Rope Upright Row', ten, 'Блок · канат', 'B1 · Суперсет с B2', tempo),
      ex('Standing DB Side Lateral Raises', twenty, 'Гантели', 'B2 · Суперсет с B1'),
      ex('Cable Rope Face Pulls', twenty, 'Блок · канат', 'C'),
      ex('Band Pull Aparts', '∞ / ∞', 'Резинка · сопротивление укажите в заметке', 'D', '', 'Вес в кг не используется.', null, true),
    ]},
  ],
})
