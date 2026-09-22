import type { Session } from './domain'
import { nextSet, scrollToSet } from './workoutFlow'
import { exerciseName } from './exerciseLibrary'
export default function WorkoutFlow({session}:{session:Session}) {
 const next=nextSet(session)
 return <section className="card workout-flow"><span className="eyebrow">{next?.superset?'СУПЕРСЕТ · ПО ОЧЕРЕДИ':'ПОРЯДОК ПОДХОДОВ'}</span>{next?<><strong className="flow-exercise">{exerciseName(next.exercise)}</strong><p>Подход {next.index+1} из {next.exercise.records.length}{next.superset?' · после него переход к следующему упражнению группы':''}</p><button className="primary" onClick={()=>scrollToSet(next.record.id)}>К следующему подходу</button></>:<p>Все подходы выполнены или пропущены. Можно завершить тренировку.</p>}<details><summary>Как работает порядок</summary><p>В суперсете чередуются упражнения: первый подход каждого, затем второй. Пропущенные и выполненные подходы не предлагаются снова. Можно записывать подходы в другом порядке. Отдых берётся из настроек упражнения; неуказанный отдых не придумывается.</p></details></section>
}

