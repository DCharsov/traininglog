/** Короткий тактильный отклик. Молча ничего не делает там, где вибрации нет. */
const buzz=(pattern:number|number[])=>{try{navigator.vibrate?.(pattern)}catch{/* вибрация необязательна */}}
/** Подход записан. */
export const setSaved=()=>buzz(20)
/** Подход стал рекордом. */
export const recordHit=()=>buzz([25,60,25,60,90])
/** Отдых закончился. */
export const restOver=()=>buzz([120,80,120])
