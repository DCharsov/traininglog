import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readdir, readFile } from 'node:fs/promises'
async function sources(dir) {
  const files = await readdir(dir, { withFileTypes: true })
  return (await Promise.all(files.map(async f => f.isDirectory() ? sources(`${dir}/${f.name}`) : f.name.endsWith('.swift') ? [await readFile(`${dir}/${f.name}`, 'utf8')] : []))).flat()
}
test('shipping apps cannot create or save HealthKit workouts or request write access', async () => {
  const code = (await Promise.all(['apps/watch/iPhone App', 'apps/watch/TrainingLogWatch Watch App', 'apps/watch/Shared'].map(sources))).flat().join('\n')
  assert.doesNotMatch(code, /\.finishWorkout\s*\(|HKWorkoutSession\s*\(|\.beginCollection\s*\(|\.startActivity\s*\(|\.addSamples\s*\(/)
  const authorizations = [...code.matchAll(/requestAuthorization\(toShare:\s*([^,]+),/g)]
  assert.ok(authorizations.length > 0, 'Read authorization remains available')
  for (const match of authorizations) assert.equal(match[1].trim(), '[]')
  assert.doesNotMatch(code, /\b(?:health|store|healthStore)\.(?:save|delete)\s*\(/)
})
test('legacy watch collection is discarded, never saved', async () => {
  const code = await readFile('apps/watch/TrainingLogWatch Watch App/WatchHealth.swift', 'utf8')
  assert.match(code, /\.discardWorkout\(\)/)
  assert.match(code, /\.closeWithoutSave\(/)
  const config = await readFile('apps/watch/Config/Signing.xcconfig', 'utf8')
  assert.doesNotMatch(config, /NSHealthUpdateUsageDescription/)
})
