import guides from './exerciseGuides.json'
import type { Exercise } from './domain'
const key=(name:string)=>name.trim().toLocaleLowerCase('en-US')
const byName=new Map(guides.flatMap(g=>[[key(g.english),g],[key(g.ru),g]] as const))
export function guideFor(exercise:Pick<Exercise,'name'>) {return byName.get(key(exercise.name))}
export function exerciseName(exercise:Pick<Exercise,'name'>) {return guideFor(exercise)?.ru??exercise.name}
export { guides }
