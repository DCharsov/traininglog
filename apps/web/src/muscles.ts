import { guideFor } from './exerciseLibrary'
import type { Exercise, MuscleId } from './domain'

export const MUSCLE_NAMES:Record<MuscleId,string>={
 chest:'Грудь',back:'Спина',shoulders:'Плечи',biceps:'Бицепс',triceps:'Трицепс',forearms:'Предплечья',
 quads:'Квадрицепс',hamstrings:'Бицепс бедра',glutes:'Ягодицы',calves:'Икры',abs:'Пресс',
}
export type MuscleMap={primary:MuscleId;secondary:MuscleId[]}
export const normalizeName=(name:string)=>name.toLocaleLowerCase('ru').replace(/ё/g,'е').replace(/[^\p{L}\p{N}]+/gu,' ').trim()

/** Первая мышца — основная, остальные получают половину подхода. Ключ — название из справочника. */
const table:Record<string,[MuscleId,...MuscleId[]]>={
 'Incline Pronated DB Bench Press':['chest','shoulders','triceps'],
 'Flat Pronated DB Bench Press':['chest','triceps','shoulders'],
 'Hammer Strength Decline Chest Press':['chest','triceps'],
 'Pec Deck':['chest'],
 'Push Ups':['chest','triceps','shoulders'],
 'Lat Pulldown Lean Away Medium':['back','biceps'],
 'Hammer Strength Overhand Row':['back','biceps'],
 'Chest Supported Incline Neut':['back','biceps'],
 'DB Pullover':['back','chest'],
 'Seated Rear Delt Flys':['shoulders','back'],
 'Barbell Deadlift':['back','hamstrings','glutes'],
 'Cybex Medium Stance Leg Press':['quads','glutes'],
 'DB Walking Lunges':['quads','glutes','hamstrings'],
 'Lying Leg Curl - Neutral (Dorsi':['hamstrings'],
 'DB RDL':['hamstrings','glutes','back'],
 'Standing Calf Raise Machine Me':['calves'],
 'Flat Bench DB Skull Crushers':['triceps'],
 'Incline Supinated DB Curls':['biceps','forearms'],
 'Cable Rope French Press':['triceps'],
 'Cable Rope Tricep Pushdowns':['triceps'],
 'Standing DB Hammer Curls':['biceps','forearms'],
 'Cable Rope Hammer Curl':['biceps','forearms'],
 'High Pulley Rope Cable Crunch':['abs'],
 'Seated DB Shoulder Press':['shoulders','triceps'],
 'Cable Rope Upright Row':['shoulders','back'],
 'Standing DB Side Lateral Raises':['shoulders'],
 'Cable Rope Face Pulls':['shoulders','back'],
 'Band Pull Aparts':['shoulders','back'],
 'Присед в Смите':['quads','glutes'],
 'Жим ногами':['quads','glutes'],
 'Жим гантелей лёжа на горизонтальной скамье':['chest','triceps','shoulders'],
 'Жим гантелей на небольшом наклоне скамьи':['chest','triceps','shoulders'],
 'Горизонтальная тяга блока':['back','biceps'],
 'Тяга верхнего блока к груди':['back','biceps'],
 'Сгибание ног сидя в тренажёре':['hamstrings'],
 'Подъёмы гантелей через стороны':['shoulders'],
 'Разгибание рук с канатом на трицепс':['triceps'],
 'Сгибания рук с гантелями на бицепс':['biceps','forearms'],
 'Подъёмы на носки стоя с опорой руками':['calves'],
 'Face pull — тяга каната к лицу':['shoulders','back'],
 'Dead bug':['abs'],
 'Bird dog':['abs'],
}
const byName=new Map(Object.entries(table).map(([name,ids])=>[normalizeName(name),ids]))

/** Группы мышц упражнения: выбор пользователя важнее справочника. */
export function musclesFor(exercise:Pick<Exercise,'name'|'muscle'>):MuscleMap|null {
 if(exercise.muscle)return {primary:exercise.muscle,secondary:[]}
 const found=byName.get(normalizeName(guideFor(exercise)?.english??exercise.name))??byName.get(normalizeName(exercise.name))
 return found?{primary:found[0],secondary:found.slice(1) as MuscleId[]}:null
}
