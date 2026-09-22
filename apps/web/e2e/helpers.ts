import { expect, type Page } from '@playwright/test'
export async function finishWorkout(page:Page) {
 await page.getByRole('button',{name:'Завершить тренировку',exact:true}).click()
 await page.getByRole('button',{name:'Завершить',exact:true}).click()
 await expect(page.getByText('Тренировка завершена',{exact:true})).toBeVisible()
}
export async function exerciseMenu(page:Page,name:string) {await page.getByRole('button',{name:`Действия: ${name}`,exact:true}).click()}
export async function selectSet(page:Page,name:string,index:number) {
 await page.getByRole('button',{name:'Обзор тренировки',exact:true}).click()
 const section=page.locator('.workout-overview section').filter({has:page.getByRole('heading',{name,exact:true})})
 await section.getByRole('button').nth(index).click()
}
export async function openExercise(page:Page,name:string) {await selectSet(page,name,0)}
export async function lastExercise(page:Page) {
 await page.getByRole('button',{name:'Обзор тренировки',exact:true}).click()
 await page.locator('.workout-overview section').last().getByRole('button').first().click()
 return page.locator('.exercise').last()
}
export async function goTab(page:Page,name:string) {
 const collapse=page.getByRole('button',{name:'Свернуть',exact:true})
 if(await collapse.isVisible())await collapse.click()
 await page.getByRole('button',{name:name==='Программа'?'Программы':name,exact:true}).click()
}
export async function openProgramEditor(page:Page) {
 await goTab(page,'Программы')
 const edit=page.getByRole('button',{name:'Изменить программу',exact:true})
 if(await edit.isVisible())await edit.click()
 else if(!await page.getByLabel('Название программы',{exact:true}).isVisible())await page.getByRole('button',{name:'Создать программу',exact:true}).click()
}
export async function editExercise(page:Page,index:number) {
 const toggle=page.locator('.ex-toggle').nth(index)
 if(await toggle.getAttribute('aria-expanded')==='false')await toggle.click()
 const advanced=toggle.locator('..').locator('summary').filter({hasText:'Оборудование и дополнительные настройки'})
 if(await advanced.count()&&(await advanced.locator('..').getAttribute('open'))===null)await advanced.click()
}
export async function editAllExercises(page:Page) {
 const toggles=page.locator('.ex-toggle')
 for(let i=0;i<await toggles.count();i++)await editExercise(page,i)
}
export async function startDay(page:Page,name:RegExp) {
 await page.getByRole('button',{name}).click()
 await page.getByRole('button',{name:'Начать тренировку',exact:true}).click()
}
