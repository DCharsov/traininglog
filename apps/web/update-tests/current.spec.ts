import { test, expect } from '@playwright/test'

test('settings update button checks the current release and recovers after going offline', async ({ page, context }, info) => {
 const errors: string[] = []
 page.on('pageerror', error => errors.push(error.message))
 await page.goto('/training/')
 await page.evaluate(async () => { await navigator.serviceWorker.ready })
 await page.getByRole('button', { name: 'Настройки', exact: true }).click()
 const update = page.getByRole('button', { name: 'Обновить приложение', exact: true })
 await expect(update).toBeVisible()
 await update.click()
 await expect(page.getByText('Установлена последняя версия', { exact: true })).toBeVisible()
 await page.screenshot({ path: info.outputPath('update-settings.png'), fullPage: true })
 await context.setOffline(true)
 await update.click()
 await expect(page.getByText(/Нет интернета|Не удалось проверить обновление/)).toBeVisible()
 await expect(update).toBeEnabled()
 await context.setOffline(false)
 await update.click()
 await expect(page.getByText('Установлена последняя версия', { exact: true })).toBeVisible()
 expect(errors).toEqual([])
})
