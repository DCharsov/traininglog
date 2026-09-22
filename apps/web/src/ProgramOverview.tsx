import { exerciseName } from './exerciseLibrary'
import { modes, type Program } from './domain'
import './management.css'

type Props={program:Program;onEdit:()=>void;onArchive?:()=>void;onDelete?:()=>void;disabled?:boolean}
export default function ProgramOverview({program,onEdit,onArchive,onDelete,disabled=false}:Props) {
 return <section className="program-overview">
  <div className="card"><h2>{program.name}</h2><p>{program.days.length} тренировочных дней · {program.days.reduce((n,d)=>n+d.exercises.length,0)} упражнений</p><button className="primary" disabled={disabled} onClick={onEdit}>Изменить программу</button>{program.sourceNote&&<details><summary>Заметки программы</summary><p className="program-note">{program.sourceNote}</p></details>}</div>
  {program.days.map((day,i)=><section className="card" key={day.id}><span className="eyebrow">ДЕНЬ {i+1}</span><h3>{day.name}</h3><ol className="program-exercise-list">{day.exercises.map(ex=><li key={ex.id}><strong>{exerciseName(ex)}</strong><span>{ex.sets} подходов{ex.unilateral?' на сторону':''}{ex.target?` × ${ex.target}`:''}{ex.rest!=null?` · отдых ${ex.rest} сек`:''}</span><small>{ex.equipment} · {modes[ex.mode]}{ex.tracking==='duration'?' · запись в секундах':''}{ex.optionalWeekly?' · необязательный блок':''}</small></li>)}</ol></section>)}
  {(onArchive||onDelete)&&<details className="card"><summary>Действия с программой</summary><div className="actions">{onArchive&&<button disabled={disabled} onClick={onArchive}>В архив</button>}{onDelete&&<button disabled={disabled} onClick={onDelete}>В корзину</button>}</div></details>}
 </section>
}
