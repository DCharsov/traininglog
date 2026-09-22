import { useState } from 'react'
import type { Exercise } from './domain'
import { guideFor } from './exerciseLibrary'
const photos=import.meta.glob<string>('./assets/exercises/*.jpg',{eager:true,query:'?url',import:'default'})
export default function ExerciseGuide({exercise}:{exercise:Pick<Exercise,'name'>}) {
 const guide=guideFor(exercise),[frame,setFrame]=useState(0)
 if(!guide)return null
 const src=(index:number)=>photos[`./assets/exercises/${guide.images[index]}`]
 return <details className="exercise-guide"><summary><img src={src(0)} alt="" loading="lazy" width="72" height="54"/><span>Как выполнять<small>Фото и короткая подсказка</small></span><span aria-hidden="true">⌄</span></summary><div className="guide-content"><div className="guide-frames" role="group" aria-label="Положения упражнения">{guide.images.map((_,i)=><button type="button" key={i} aria-pressed={frame===i} onClick={()=>setFrame(i)}>Фото {i+1}</button>)}</div><img className="guide-photo" src={src(frame)} alt={`${guide.ru} — положение ${frame+1}`} loading="lazy" width="850" height="567"/><p>{guide.cue}</p>{guide.note&&<p className="guide-note">{guide.note}</p>}<small>В оригинале: {guide.english}</small><a className="guide-source" href={`https://github.com/yuhonas/free-exercise-db/tree/a859101d633a01c4a1a920d6a8ce41dabba0705f/exercises/${guide.source}`} target="_blank" rel="noreferrer">Источник фото: Free Exercise DB</a></div></details>
}
