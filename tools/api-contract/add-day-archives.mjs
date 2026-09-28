import { readFileSync, writeFileSync } from 'node:fs'
const path = new URL('../../apps/api/openapi.json', import.meta.url)
const doc = JSON.parse(readFileSync(path, 'utf8'))
function update(schema) {
  if (!schema || typeof schema !== 'object') return
  const p = schema.properties
  if (p?.id && p?.name && p?.exercises && !p.programId && !p.variantId) {
    p.archivedAt = { anyOf: [{ type: 'string', format: 'date-time' }, { type: 'null' }] }
  }
  for (const child of Object.values(schema)) update(child)
}
update(doc.components.schemas)
writeFileSync(path, JSON.stringify(doc, null, 2) + '\n')
