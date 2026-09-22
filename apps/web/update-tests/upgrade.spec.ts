import { test, expect, type Page } from '@playwright/test'
import { selectSet, startDay } from '../e2e/helpers'

const release = (page: Page) => page.locator('meta[name="test-release"]')
const updateButton = (page: Page) => page.getByRole('button', { name: 'Обновить приложение', exact: true })

test.beforeEach(async ({ request }) => {
 const response = await request.post('/__update-test__/release?version=one')
 expect(response.ok()).toBe(true)
})

async function ready(page: Page) {
 await page.goto('/training/')
 await page.evaluate(async () => { await navigator.serviceWorker.ready })
 await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true)
 await expect(release(page)).toHaveAttribute('content', 'one')
}

async function workout(page: Page) {
 await ready(page)
 await page.getByRole('button', { name: 'Создать программу', exact: true }).click()
 await page.getByLabel('Название дня', { exact: true }).fill('Проверка обновления')
 await page.getByLabel('Название и вариант').fill('Тестовый жим')
 await page.getByLabel('Тренажёр / оборудование').fill('Тестовый тренажёр')
 await page.getByRole('button', { name: 'Сохранить программу', exact: true }).click()
 await expect(page.getByText('Программа сохранена.', { exact: false })).toBeVisible()
 await page.getByRole('button', { name: 'Сегодня', exact: true }).click()
 await startDay(page, /Проверка обновления/)
}

async function downloadUpdate(page: Page) {
 await page.evaluate(async () => { await (await navigator.serviceWorker.getRegistration())!.update() })
 await expect.poll(() => page.evaluate(async () => !!(await navigator.serviceWorker.getRegistration())?.waiting)).toBe(true)
 await expect(updateButton(page)).toBeVisible()
}

test('explicit update keeps completed and draft sets and leaves other tabs alone', async ({ page, context, request }, info) => {
 await workout(page)
 await page.getByLabel('Вес подхода 1', { exact: true }).fill('47')
 await page.getByLabel('Повторения подхода 1', { exact: true }).fill('10')
 await page.getByRole('button', { name: 'Готово', exact: true }).click()
 await expect(page.getByRole('button', { name: 'Обзор тренировки', exact: true })).toContainText('1 из 3 подходов выполнено')
 const other = await context.newPage()
 await ready(other)
 await request.post('/__update-test__/release?version=two')
 await downloadUpdate(page)
 await expect(release(page)).toHaveAttribute('content', 'one')
 await page.getByLabel('Вес подхода 2', { exact: true }).fill('42')
 await page.getByLabel('Повторения подхода 2', { exact: true }).fill('11')
 await page.screenshot({ path: info.outputPath('update-workout.png'), fullPage: true })
 await updateButton(page).click()
 await expect(release(page)).toHaveAttribute('content', 'two')
 await expect(page.getByLabel('Вес подхода 2', { exact: true })).toHaveValue('42')
 await expect(page.getByLabel('Повторения подхода 2', { exact: true })).toHaveValue('11')
 await selectSet(page, 'Тестовый жим', 0)
 await expect(page.getByLabel('Вес подхода 1', { exact: true })).toHaveValue('47')
 await expect(page.getByLabel('Повторения подхода 1', { exact: true })).toHaveValue('10')
 await expect(release(other)).toHaveAttribute('content', 'one')
 await updateButton(other).click()
 await expect(release(other)).toHaveAttribute('content', 'two')
 await other.close()
 const cacheNames = await page.evaluate(() => caches.keys())
 expect(cacheNames.filter(name => name.startsWith('traininglog-shell-'))).toEqual(['traininglog-shell-update-test-two'])
})

test('cold offline restart after an update preserves the workout', async ({ page, context, request, browserName }) => {
 test.skip(browserName === 'webkit', 'WebKit offline navigation also fails on the unchanged previous production build; see deploy/update-webkit-offline-baseline.json. Physical iPhone verification remains separate.')
 await workout(page)
 await page.getByLabel('Вес подхода 1', { exact: true }).fill('47')
 await page.getByLabel('Повторения подхода 1', { exact: true }).fill('10')
 await page.getByRole('button', { name: 'Готово', exact: true }).click()
 await page.getByLabel('Вес подхода 2', { exact: true }).fill('42')
 await page.getByLabel('Повторения подхода 2', { exact: true }).fill('11')
 await request.post('/__update-test__/release?version=two')
 await downloadUpdate(page)
 await updateButton(page).click()
 await expect(release(page)).toHaveAttribute('content', 'two')
 await context.setOffline(true)
 await page.close()
 const reopened = await context.newPage()
 await reopened.goto('/training/')
 await expect(release(reopened)).toHaveAttribute('content', 'two')
 await selectSet(reopened, 'Тестовый жим', 1)
 await expect(reopened.getByLabel('Вес подхода 2', { exact: true })).toHaveValue('42')
 await expect(reopened.getByLabel('Повторения подхода 2', { exact: true })).toHaveValue('11')
 await reopened.getByRole('button', { name: 'Готово', exact: true }).click()
 await expect(reopened.getByRole('button', { name: 'Обзор тренировки', exact: true })).toContainText('2 из 3 подходов выполнено')
})

test('failed local save prevents activation and reload until the input is saved', async ({ page, request }) => {
 await workout(page)
 await request.post('/__update-test__/release?version=two')
 await downloadUpdate(page)
 await page.evaluate(() => {
  const original = IDBObjectStore.prototype.put
  IDBObjectStore.prototype.put = function (...args: Parameters<typeof original>) {
   if (this.name === 'sessions') throw new DOMException('Simulated full storage', 'QuotaExceededError')
   return original.apply(this, args)
  }
  Object.assign(window, { restoreTestStorage: () => { IDBObjectStore.prototype.put = original } })
 })
 await page.getByLabel('Вес подхода 1', { exact: true }).fill('60')
 await expect(page.getByText('Ошибка локального сохранения. Ввод остался на экране.', { exact: true })).toBeVisible()
 await updateButton(page).click()
 await expect(page.getByText('Ввод не сохранён. Повторите изменение подхода перед обновлением.', { exact: true })).toBeVisible()
 await expect(release(page)).toHaveAttribute('content', 'one')
 await expect(page.getByLabel('Вес подхода 1', { exact: true })).toHaveValue('60')
 expect(await page.evaluate(async () => !!(await navigator.serviceWorker.getRegistration())?.waiting)).toBe(true)
 await page.evaluate(() => (window as unknown as { restoreTestStorage: () => void }).restoreTestStorage())
 await page.getByLabel('Вес подхода 1', { exact: true }).fill('61')
 await page.getByLabel('Повторения подхода 1', { exact: true }).fill('9')
 await updateButton(page).click()
 await expect(release(page)).toHaveAttribute('content', 'two')
 await expect(page.getByLabel('Вес подхода 1', { exact: true })).toHaveValue('61')
 await expect(page.getByLabel('Повторения подхода 1', { exact: true })).toHaveValue('9')
})

test('program editor blocks updates until the program is saved', async ({ page, request }) => {
 await ready(page)
 await page.getByRole('button', { name: 'Создать программу', exact: true }).click()
 await page.getByLabel('Название программы', { exact: true }).fill('Сохранить перед обновлением')
 await page.getByLabel('Название дня', { exact: true }).fill('Тестовый день')
 await page.getByLabel('Название и вариант').fill('Тестовый жим')
 await page.getByLabel('Тренажёр / оборудование').fill('Тестовый тренажёр')
 await request.post('/__update-test__/release?version=two')
 await downloadUpdate(page)
 await expect(updateButton(page)).toBeDisabled()
 await expect(page.getByText('Сохраните или закройте редактор перед обновлением.', { exact: true })).toBeVisible()
 await page.getByRole('button', { name: 'Сохранить программу', exact: true }).click()
 await expect(updateButton(page)).toBeEnabled()
 await updateButton(page).click()
 await expect(release(page)).toHaveAttribute('content', 'two')
 await expect(page.getByRole('heading', { name: 'Сохранить перед обновлением', exact: true })).toBeVisible()
})

test('one click checks, downloads and applies a release that was not already waiting', async ({ page, request }) => {
 await ready(page)
 await page.getByRole('button', { name: 'Настройки', exact: true }).click()
 await request.post('/__update-test__/release?version=two')
 await updateButton(page).click()
 await expect(release(page)).toHaveAttribute('content', 'two')
 await expect(updateButton(page)).toBeEnabled()
})
