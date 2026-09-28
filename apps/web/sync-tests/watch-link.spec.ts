import {test,expect} from '@playwright/test'
import {randomBytes,randomUUID} from 'node:crypto'

test('connect watch by phone confirmation without entering a code',async({page,playwright})=>{
 await page.goto('/training/')
 await page.getByRole('button',{name:'Настройки',exact:true}).click()
 await page.getByRole('button',{name:'Синхронизация',exact:true}).click()
 await page.getByLabel('Пароль',{exact:true}).fill('Test-only-password!123')
 await page.getByRole('button',{name:'Войти и подключить синхронизацию'}).click()
 await expect(page.locator('.sync-panel').getByText('Синхронизировано',{exact:true})).toBeVisible()
 await expect(page.getByRole('button',{name:'Создать код подключения'})).toHaveCount(0)
 await page.getByRole('button',{name:'Подключить часы',exact:true}).click()
 await expect(page.getByText('Теперь нажмите «Подключить» на часах.',{exact:false})).toBeVisible()
 const request={id:randomUUID(),token:randomBytes(32).toString('hex'),name:'E2E No Code Watch'}
 const watch=await playwright.request.newContext({baseURL:'http://127.0.0.1:5181'})
 try {
  const response=await watch.post('/training/api/watch/link/request',{data:request})
  expect(response.ok()).toBeTruthy();const pending=await response.json()
  await expect(page.getByText(pending.label,{exact:true})).toBeVisible()
  const before=await watch.post('/training/api/watch/link/status',{data:request});expect((await before.json()).state).toBe('pending')
  await page.getByRole('button',{name:'Это мои часы',exact:true}).click()
  await expect(page.getByText('E2E No Code Watch · последняя связь',{exact:false})).toBeVisible()
  const after=await watch.post('/training/api/watch/link/status',{data:request});expect((await after.json()).state).toBe('approved')
  const owned=await watch.get('/training/api/watch/v1/session',{headers:{Authorization:`Bearer ${request.token}`}})
  expect(owned.ok()).toBeTruthy()
 } finally {await watch.dispose()}
})
