import { test, expect } from '@playwright/test'

test('Back restores the edited program even after the selected program changes; remote archive preserves its draft', async ({ page }) => {
 await page.goto('/training/')
 const ids = await page.evaluate(async () => {
  const dataPath = '/training/src/data.ts', fixturePath = '/training/src/broSplit.ts'
  const { db } = await import(dataPath), { broSplit } = await import(fixturePath)
  const a = { ...structuredClone(broSplit), id: crypto.randomUUID(), name: 'Программа A', sourceNote: '', days: structuredClone(broSplit.days.slice(0, 1)) }
  a.days[0].exercises = a.days[0].exercises.slice(0, 1)
  const b = { ...structuredClone(a), id: crypto.randomUUID(), name: 'Программа B' }
  await db.programs.bulkPut([a, b]); return { a: a.id, b: b.id }
 })
 await page.getByRole('button', { name: 'Программы', exact: true }).click()
 await page.getByLabel('Текущая программа').selectOption(ids.a)
 await page.getByRole('button', { name: 'Изменить программу', exact: true }).click()
 await page.getByLabel('Название программы', { exact: true }).fill('Черновик программы A')
 await expect(page.locator('.editor-draft-status')).toContainText('Черновик сохранён')
 await page.getByRole('button', { name: 'Сегодня', exact: true }).click()
 await page.getByLabel('Текущая программа').selectOption(ids.b)
 await page.goBack()
 await expect(page.getByLabel('Название программы', { exact: true })).toHaveValue('Черновик программы A')

 // Models an accepted background update from another device while this editor is open.
 await page.evaluate(async id => { const path = '/training/src/data.ts', { db } = await import(path); await db.programs.update(id, { archivedAt: new Date().toISOString() }) }, ids.a)
 await expect(page.getByLabel('Название программы', { exact: true })).toHaveValue('Черновик программы A')
 await page.getByRole('button', { name: 'Сохранить программу', exact: true }).click()
 await expect(page.getByRole('alert')).toContainText('Программа обновилась')
 await expect(page.getByLabel('Название программы', { exact: true })).toHaveValue('Черновик программы A')
 const stored = await page.evaluate(async id => { const path = '/training/src/data.ts', { db } = await import(path); return db.programs.get(id) }, ids.a)
 expect(stored.name).toBe('Программа A'); expect(stored.archivedAt).toBeTruthy()
})
