import { db } from './data'
import { visible, type Program } from './domain'
import { broSplit } from './broSplit'
import { hypertrophyAB, importHypertrophyAB } from './hypertrophyAB'
import { belovedSplit, importBelovedSplit } from './belovedSplit'

type Props={disabled:boolean;programs:Program[];program?:Program;run:(a:()=>Promise<unknown>,m?:string)=>Promise<boolean>;onSelectProgram:(id:string)=>void;refresh:()=>void}
export default function SeedPrograms({disabled,programs,program,run,onSelectProgram,refresh}:Props) {
 const hasBro=programs.some(p=>p.id===broSplit.id)
 const hasAB=programs.some(p=>p.seedKey===hypertrophyAB.seedKey)
 const hasBeloved=programs.some(p=>p.id===belovedSplit.id||p.seedKey===belovedSplit.seedKey)
 if(hasBro&&hasAB&&hasBeloved)return <p>Все готовые программы уже в дневнике.</p>
 return <div className="actions">
  {!hasBro&&<button disabled={disabled} onClick={()=>void run(async()=>{
   await db.transaction('rw',db.programs,async()=>{const old=await db.programs.get(broSplit.id);if(!old)await db.programs.add(structuredClone(broSplit));else if(!visible(old))await db.programs.put({...old,archivedAt:null,deletedAt:null,version:old.version+1})})
   onSelectProgram(broSplit.id);refresh()
  },'Bro Split добавлен')}>Добавить Bro Split в дневник</button>}
  {!hasAB&&<button disabled={disabled} onClick={()=>void run(async()=>{const current=program?.id??'new';await importHypertrophyAB();onSelectProgram(current)},'Шаблон добавлен. Выберите его в списке программ.')}>Добавить личный шаблон А/Б</button>}
  {!hasBeloved&&<button disabled={disabled} onClick={()=>void run(async()=>{
   const added=await importBelovedSplit()
   if(!visible(added))throw new Error('Программа «Для Любименькой» уже есть в архиве или корзине. Восстановите её в настройках.')
   onSelectProgram(added.id);refresh()
  },'Программа «Для Любименькой ❤️» добавлена и выбрана.')}>Добавить «Для Любименькой ❤️»</button>}
 </div>
}
