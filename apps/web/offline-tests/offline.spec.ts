import { test, expect } from '@playwright/test'
import { selectSet, startDay } from '../e2e/helpers'
async function ready(page:import('@playwright/test').Page){
 await page.goto('/training/')
 await page.evaluate(async()=>{await navigator.serviceWorker.ready})
}
test('cold offline restart keeps confirmed sets and confines worker to training',async({page,context})=>{
 await ready(page);await page.getByRole('button',{name:'Создать программу',exact:true}).click()
 await page.getByLabel('Название дня',{exact:true}).fill('Офлайн-тест')
 await page.getByLabel('Название и вариант').fill('Тестовый жим');await page.getByLabel('Тренажёр / оборудование').fill('Тестовый тренажёр')
 await page.getByRole('button',{name:'Сохранить программу'}).click();await expect(page.getByText('Программа сохранена.',{exact:false})).toBeVisible()
 await page.getByRole('button',{name:'Сегодня',exact:true}).click();await startDay(page,/Офлайн-тест/)
 await page.getByLabel('Вес подхода 1',{exact:true}).fill('47');await page.getByLabel('Повторения подхода 1',{exact:true}).fill('10')
 await page.getByRole('button',{name:'Готово',exact:true}).click()
 await expect(page.getByRole('button',{name:'Обзор тренировки'})).toContainText('1 из 3 подходов выполнено')
 expect(await page.evaluate(async()=>(await navigator.serviceWorker.ready).scope)).toBe(new URL('/training/',page.url()).href)
 await context.setOffline(true);await page.close()
 const reopened=await context.newPage();await reopened.goto('/training/');await selectSet(reopened,'Тестовый жим',0)
 await expect(reopened.getByLabel('Вес подхода 1',{exact:true})).toHaveValue('47')
 await selectSet(reopened,'Тестовый жим',1)
 await reopened.getByLabel('Вес подхода 2',{exact:true}).fill('40');await reopened.getByLabel('Повторения подхода 2',{exact:true}).fill('12')
 await reopened.getByRole('button',{name:'Готово',exact:true}).click()
 await expect(reopened.getByRole('button',{name:'Обзор тренировки'})).toContainText('2 из 3 подходов выполнено')
 const cacheKeys=await reopened.evaluate(async()=>{const keys=await caches.keys();const cache=await caches.open(keys.find(k=>k.startsWith('traininglog-shell-'))!);return (await cache.keys()).map(r=>new URL(r.url).pathname)})
 expect(cacheKeys.every(p=>p.startsWith('/training/')&&!p.includes('/api/'))).toBe(true)
 expect(await reopened.evaluate(async()=>{try{await fetch('/api/health');return false}catch{return true}})).toBe(true)
})
test('exercise photos are available after a cold offline restart',async({page,context})=>{
 await ready(page);await page.getByRole('button',{name:'Добавить Bro Split в дневник'}).click();await startDay(page,/Грудь.*5 упражнений/)
 await context.setOffline(true);await page.close()
 const reopened=await context.newPage();await reopened.goto('/training/');await reopened.getByRole('button',{name:'Как выполнять',exact:true}).click()
 const guide=reopened.locator('.exercise-guide').first()
 for(const frame of ['Фото 1','Фото 2']){await guide.getByRole('button',{name:frame,exact:true}).click();await expect.poll(()=>guide.locator('.guide-photo').evaluate((el:HTMLImageElement)=>el.complete&&el.naturalWidth>0)).toBe(true)}
 const count=await reopened.evaluate(async()=>{const keys=await caches.keys();const c=await caches.open(keys.find(k=>k.startsWith('traininglog-shell-'))!);return (await c.keys()).filter(r=>new URL(r.url).pathname.endsWith('.jpg')).length})
 expect(count).toBe(56)
})
