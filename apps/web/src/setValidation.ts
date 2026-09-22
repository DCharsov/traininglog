import { parseWeight, type Session } from './domain'

export type SetField='weight'|'reps'|'duration'|'rir'|'side'|'equipment'
export type SetConfirmResult={ok:true}|{ok:false;field?:SetField;message:string}
export function validateSet(session:Session,exerciseId:string,setId:string):SetConfirmResult {
 const exercise=session.exercises.find(e=>e.id===exerciseId),record=exercise?.records.find(r=>r.id===setId)
 if(!exercise||!record)return {ok:false,message:'Подход уже изменился. Откройте его заново.'}
 if(record.status==='completed')return {ok:true}
 if(exercise.requiresEquipment&&exercise.mode==='Unspecified')return {ok:false,field:'equipment',message:'Выберите оборудование и способ учёта веса.'}
 if(exercise.mode!=='BodyweightOnly')try{parseWeight(record.weight)}catch(e){return {ok:false,field:'weight',message:(e as Error).message}}
 if(exercise.tracking==='duration'){
  if(!/^\d{1,5}$/.test(record.duration??'')||Number(record.duration)<1||Number(record.duration)>86400)return {ok:false,field:'duration',message:'Введите длительность от 1 до 86400 секунд.'}
 }else if(!/^\d{1,4}$/.test(record.reps)||Number(record.reps)<1||Number(record.reps)>1000)return {ok:false,field:'reps',message:'Введите число повторений от 1 до 1000.'}
 if(record.rir!==''&&(!/^\d{1,2}$/.test(record.rir)||Number(record.rir)>10))return {ok:false,field:'rir',message:'RIR — от 0 до 10, либо оставьте поле пустым.'}
 if(exercise.unilateral&&record.side!=='left'&&record.side!=='right')return {ok:false,field:'side',message:'Выберите левую или правую сторону.'}
 return {ok:true}
}
