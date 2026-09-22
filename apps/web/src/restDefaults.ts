import { guideFor } from './exerciseLibrary'
import { musclesFor, normalizeName } from './muscles'
import type { Exercise, MuscleId } from './domain'

/** Отдых, когда об упражнении ничего не известно. */
export const DEFAULT_REST=90
/** Крупные мышцы: подход тяжелее и восстановление дольше. */
const BIG=new Set<MuscleId>(['chest','back','quads','hamstrings','glutes'])
/** Мелкие группы: подход почти не мешает следующему. */
const SMALL=new Set<MuscleId>(['calves','abs'])
/** Упражнения, где правило по группе мышц даёт заведомо много. */
const overrides:Record<string,number>={'Band Pull Aparts':60,'Cable Rope Face Pulls':90,'Lying Leg Curl - Neutral (Dorsi':90}
const byName=new Map(Object.entries(overrides).map(([name,rest])=>[normalizeName(name),rest]))
const label=(exercise:Pick<Exercise,'sourceNote'>)=>/^([A-Z])(\d)\s*·\s*Суперсет/.exec(exercise.sourceNote??'')

/** Отдых по нагрузке упражнения, без учёта суперсетов. */
function byLoad(exercise:Pick<Exercise,'name'|'muscle'>):number {
 const override=byName.get(normalizeName(guideFor(exercise)?.english??exercise.name))
 if(override!==undefined)return override
 const muscles=musclesFor(exercise)
 if(!muscles)return DEFAULT_REST
 // Предплечья в сгибаниях рук не делают упражнение многосуставным.
 const compound=muscles.secondary.some(id=>id!=='forearms')
 if(BIG.has(muscles.primary))return !compound?120:muscles.secondary.some(id=>BIG.has(id))?180:150
 if(SMALL.has(muscles.primary))return 60
 return compound?120:90
}

/**
 * Отдых по умолчанию, когда в программе он не задан.
 * Два крупных массива в работе — три минуты, одно крупное — две с половиной, изоляция крупной
 * мышцы — две, мелкая изоляция — полторы, икры и пресс — минута.
 * В суперсете переход к партнёру занимает полминуты, а после последнего упражнения связки
 * идёт обычный отдых, но не дольше двух минут.
 */
export function defaultRest(exercise:Pick<Exercise,'name'|'muscle'|'supersetGroup'|'sourceNote'>):number {
 const base=byLoad(exercise),order=label(exercise)
 const grouped=!!order||(typeof exercise.supersetGroup==='string'&&exercise.supersetGroup.trim()!=='')
 if(!grouped)return base
 return order&&order[2]!=='1'?Math.min(base,120):30
}
/** Отдых упражнения: заданный в программе важнее рассчитанного. */
export const restOf=(exercise:Pick<Exercise,'rest'|'name'|'muscle'|'supersetGroup'|'sourceNote'>)=>exercise.rest??defaultRest(exercise)
