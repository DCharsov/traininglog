import { readFile, mkdir, copyFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
const root = new URL('../', import.meta.url)
const destination = new URL('apps/watch/iPhone App/Catalog/', root)
const guides = new URL('apps/web/src/exerciseGuides.json', root)
await mkdir(destination, { recursive: true })
await copyFile(guides, new URL('exerciseGuides.json', destination))
for (const guide of JSON.parse(await readFile(guides, 'utf8'))) {
  for (const image of guide.images) {
    if (!/^[\w-]+\.jpg$/.test(image)) throw new Error(`Unexpected catalog asset: ${image}`)
    await copyFile(new URL(`apps/web/src/assets/exercises/${image}`, root), new URL(image, destination))
  }
}
console.log(`Synced native catalog into ${fileURLToPath(destination)}`)
