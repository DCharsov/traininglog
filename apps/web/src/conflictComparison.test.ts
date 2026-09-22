import { expect, it } from 'vitest'
import { broSplit } from './broSplit'
import { makeSession } from './domain'
import { conflictDifferences } from './conflictComparison'

it('shows the changed exercise result and side in human-readable conflict fields', () => {
  const local = makeSession(broSplit, broSplit.days[0]), remote = structuredClone(local)
  local.exercises[0].records[0].weight = '42'
  remote.exercises[0].records[0].weight = '44'
  remote.exercises[0].records[0].side = 'left'
  const differences = conflictDifferences('sessions', local, remote)
  expect(differences).toContainEqual({ label: `${local.exercises[0].name} · подход 1 · вес`, local: '42 кг', remote: '44 кг' })
  expect(differences).toContainEqual({ label: `${local.exercises[0].name} · подход 1 · сторона`, local: 'Обе стороны', remote: 'Левая' })
  expect(differences).toHaveLength(2)
})

it('aligns exercise results by id when exercises are reordered', () => {
  const local = makeSession(broSplit, broSplit.days[0]), remote = structuredClone(local)
  remote.exercises.reverse()
  const differences = conflictDifferences('sessions', local, remote)
  expect(differences.length).toBeGreaterThan(0)
  expect(differences.every(row => row.label.endsWith(' · порядок'))).toBe(true)
})

it('shows added exercises and archive state without exposing raw JSON', () => {
  const local = structuredClone(broSplit), remote = structuredClone(local)
  remote.days[0].exercises.pop(); remote.archivedAt = new Date().toISOString()
  const differences = conflictDifferences('programs', local, remote)
  expect(differences).toContainEqual({ label: 'Расположение', local: 'В дневнике', remote: 'В архиве' })
  expect(differences.some(row => row.remote === 'Нет в этой версии')).toBe(true)
})
