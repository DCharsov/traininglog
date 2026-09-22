import { test, expect, type Page } from '@playwright/test'

async function connect(page: Page) {
 await page.getByRole('button', { name: 'Настройки', exact: true }).click()
 await page.getByRole('button', { name: 'Синхронизация', exact: true }).click()
 await page.getByLabel('Пароль', { exact: true }).fill('Test-only-password!123')
 await page.getByRole('button', { name: 'Войти и подключить синхронизацию' }).click()
 await expect(page.locator('.sync-panel').getByText('Синхронизировано', { exact: true })).toBeVisible()
}
async function seed(page: Page) {
 return page.evaluate(async () => {
  const dataPath = '/training/src/data.ts', domainPath = '/training/src/domain.ts', programPath = '/training/src/broSplit.ts'
  const { db } = await import(dataPath), { makeSession, emptySet, uid } = await import(domainPath), { broSplit } = await import(programPath)
  const program = structuredClone(broSplit)
  const session = makeSession(program, program.days[0])
  session.name = 'SYNC тренировка'; session.status = 'completed'; session.completedAt = new Date().toISOString()
  session.exercises = session.exercises.slice(0, 1)
  session.exercises[0].records = [{ ...emptySet(), status: 'completed', weight: '20', loadGrams: 20000, reps: '10', count: 10, completedAt: new Date().toISOString() }]
  const timed = { ...structuredClone(session.exercises[0]), id: uid(), name: 'SYNC секунды и стороны', mode: 'BodyweightOnly', tracking: 'duration', unilateral: true, sets: 1,
   records: ['left', 'right'].map((side, index) => ({ ...emptySet(), side, duration: index ? '35' : '40', durationSeconds: index ? 35 : 40, status: 'completed', completedAt: new Date().toISOString() })) }
  session.exercises.push(timed)
  const equipment = { id: uid(), name: 'SYNC стек', mode: 'MachineStack', stepGrams: 7000, availableGrams: [40000, 47000, 54000] }
  const calendar = { id: uid(), name: 'День отдыха', date: '2026-09-15', status: 'planned' }
  await db.programs.put(program); await db.sessions.put(session); await db.equipment.put(equipment); await db.calendar.put(calendar)
  return { sessionId: session.id, equipmentId: equipment.id, calendarId: calendar.id }
 })
}
async function snapshot(page: Page, id: string) {
 return page.evaluate(async sessionId => {
  const path = '/training/src/data.ts', { db } = await import(path)
  const session = await db.sessions.get(sessionId)
  return session ? { weight: session.exercises[0].records[0].weight, deleted: !!session.deletedAt, archived: !!session.archivedAt,
   timed: session.exercises[1].records.map((record: { side: string; durationSeconds: number }) => ({ side: record.side, seconds: record.durationSeconds })) } : null
 }, id)
}
async function updateWeight(page: Page, id: string, weight: string) {
 await page.evaluate(async ({ id, weight }) => {
  const path = '/training/src/data.ts', { change } = await import(path)
  await change(id, -1, (session: { exercises: { records: { weight: string; loadGrams: number }[] }[] }) => { session.exercises[0].records[0].weight = weight; session.exercises[0].records[0].loadGrams = Number(weight) * 1000 })
 }, { id, weight })
}
async function pending(page: Page) {
 return page.evaluate(async () => { const path = '/training/src/sync.ts', { pendingCount } = await import(path); return pendingCount() })
}

test('automatic sync continues outside settings, reconnects, resolves readable conflicts and transfers v2 data', async ({ browser }) => {
 test.setTimeout(150000)
 const c1 = await browser.newContext(), c2 = await browser.newContext(), a = await c1.newPage(), b = await c2.newPage()
 try {
  await a.goto('/training/'); const ids = await seed(a); await connect(a)
  await a.getByRole('button', { name: 'Прогресс', exact: true }).click()
  await b.goto('/training/'); await connect(b); await b.getByRole('button', { name: 'История', exact: true }).click()
  await expect.poll(() => snapshot(b, ids.sessionId)).toMatchObject({ weight: '20', timed: [{ side: 'left', seconds: 40 }, { side: 'right', seconds: 35 }] })
  const catalogs = await b.evaluate(async ids => { const path = '/training/src/data.ts', { db } = await import(path); return { equipment: await db.equipment.get(ids.equipmentId), calendar: await db.calendar.get(ids.calendarId) } }, ids)
  expect(catalogs.equipment).toMatchObject({ name: 'SYNC стек', availableGrams: [40000, 47000, 54000] })
  expect(catalogs.calendar).toMatchObject({ date: '2026-09-15', status: 'planned' })

  // Both devices are in ordinary app sections. No manual synchronization command is used.
  await c2.setOffline(true); await updateWeight(a, ids.sessionId, '44')
  await expect.poll(() => pending(a), { timeout: 20000 }).toBe(0)
  await c2.setOffline(false)
  await expect.poll(async () => (await snapshot(b, ids.sessionId))?.weight, { timeout: 20000 }).toBe('44')
  await expect(a.getByRole('heading', { name: 'Прогресс', exact: true })).toBeVisible()
  await expect(b.getByRole('heading', { name: 'История', exact: true })).toBeVisible()

  await c2.setOffline(true)
  await updateWeight(b, ids.sessionId, '42'); await updateWeight(a, ids.sessionId, '46')
  await expect.poll(() => pending(a), { timeout: 20000 }).toBe(0)
  await c2.setOffline(false)
  await expect(b.getByRole('button', { name: 'Состояние сохранения и синхронизации' })).toContainText('Нужно выбрать версию: 1')
  await b.getByRole('button', { name: 'Состояние сохранения и синхронизации' }).click()
  const difference = b.locator('.conflict-differences > div').filter({ hasText: 'подход 1 · вес' })
  await expect(difference).toContainText('42 кг'); await expect(difference).toContainText('46 кг')
  await b.getByRole('button', { name: 'Оставить локальную', exact: true }).click()
  await expect.poll(() => pending(b), { timeout: 20000 }).toBe(0)
  await expect(b.locator('.conflict-card')).toHaveCount(0)
  const archivedVersions = await b.evaluate(async () => { const path = '/training/src/data.ts', { db } = await import(path); return db.conflictArchive.count() })
  expect(archivedVersions).toBeGreaterThan(0)
  await c1.setOffline(true); await c1.setOffline(false)
  await expect.poll(async () => (await snapshot(a, ids.sessionId))?.weight, { timeout: 20000 }).toBe('42')

  // A tombstone and restoration use the same wire contract and remain reversible.
  await a.evaluate(async id => { const path = '/training/src/data.ts', { lifecycleChange } = await import(path); await lifecycleChange('sessions', id, 'delete') }, ids.sessionId)
  await expect.poll(() => pending(a), { timeout: 20000 }).toBe(0)
  await c2.setOffline(true); await c2.setOffline(false)
  await expect.poll(async () => (await snapshot(b, ids.sessionId))?.deleted, { timeout: 20000 }).toBe(true)
  await b.getByRole('button', { name: 'Все настройки', exact: false }).click()
  await b.getByRole('button', { name: 'Архив и корзина', exact: true }).click()
  await b.getByLabel('Поиск в архиве и корзине').fill('SYNC тренировка')
  await expect(b.locator('.manage-row:visible')).toHaveCount(1)
  await b.getByRole('button', { name: 'Восстановить', exact: true }).click()
  await expect.poll(() => pending(b), { timeout: 20000 }).toBe(0)
  await c1.setOffline(true); await c1.setOffline(false)
  await expect.poll(async () => (await snapshot(a, ids.sessionId))?.deleted, { timeout: 20000 }).toBe(false)

  // A refreshed catalog must not overwrite a form already being edited.
  await b.getByRole('button', { name: 'Все настройки', exact: false }).click()
  await b.getByRole('button', { name: 'Оборудование', exact: true }).click()
  await b.locator('.manage-row:visible').filter({ hasText: 'SYNC стек' }).getByRole('button', { name: 'Изменить', exact: true }).click()
  await b.getByLabel('Название оборудования', { exact: true }).fill('Мой стек')
  await c2.setOffline(true)
  await a.evaluate(async id => { const path = '/training/src/data.ts', { db } = await import(path); await db.equipment.update(id, { name: 'Серверный стек' }) }, ids.equipmentId)
  await expect.poll(() => pending(a), { timeout: 20000 }).toBe(0)
  await c2.setOffline(false)
  await expect(b.locator('.manage-row:visible').filter({ hasText: 'Серверный стек' })).toBeVisible()
  await expect(b.getByLabel('Название оборудования', { exact: true })).toHaveValue('Мой стек')
  await b.getByRole('button', { name: 'Сохранить оборудование', exact: true }).click()
  await expect(b.getByRole('alert')).toContainText('Профиль обновился')
  await expect(b.getByLabel('Название оборудования', { exact: true })).toHaveValue('Мой стек')
  await b.getByRole('button', { name: 'Отмена', exact: true }).click()
  await b.locator('.manage-row:visible').filter({ hasText: 'Серверный стек' }).getByRole('button', { name: 'Изменить', exact: true }).click()
  await b.getByLabel('Название оборудования', { exact: true }).fill('Исправленный стек')
  await b.getByRole('button', { name: 'Сохранить оборудование', exact: true }).click()
  await expect(b.locator('.manage-row:visible')).toHaveCount(1)
  await expect(b.locator('.manage-row:visible')).toContainText('Исправленный стек')
  const renamed = await b.evaluate(async id => { const path = '/training/src/data.ts', { db } = await import(path); return db.equipment.get(id) }, ids.equipmentId)
  expect(renamed).toMatchObject({ id: ids.equipmentId, name: 'Исправленный стек', availableGrams: [40000, 47000, 54000] })
 } finally { await c1.close(); await c2.close() }
})
