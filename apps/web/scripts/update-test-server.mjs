// Local-only server for real service-worker upgrades. Never used for publishing.
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { resolve, sep, extname } from 'node:path'

const root = fileURLToPath(new URL('../dist/', import.meta.url))
let version = 'one'
const types = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.css': 'text/css', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.jpg': 'image/jpeg' }
const server = createServer(async (request, response) => {
 try {
  const url = new URL(request.url, 'http://127.0.0.1:5187')
  response.setHeader('Cache-Control', 'no-store')
  if (url.pathname === '/__update-test__/release') {
   if (request.method === 'POST') {
    const next = url.searchParams.get('version')
    if (!['one', 'two'].includes(next)) { response.writeHead(400).end(); return }
    version = next
   }
   response.setHeader('Content-Type', 'application/json')
   response.end(JSON.stringify({ version })); return
  }
  if (url.pathname.startsWith('/training/api/')) {
   response.writeHead(401, { 'Content-Type': 'application/json' }).end('{"error":"unauthenticated test context"}'); return
  }
  if (!url.pathname.startsWith('/training/')) { response.writeHead(404).end(); return }
  const relative = decodeURIComponent(url.pathname.slice('/training/'.length)) || 'index.html'
  const path = resolve(root, relative)
  if (!path.startsWith(resolve(root) + sep)) { response.writeHead(403).end(); return }
  let bytes = await readFile(path)
  if (relative === 'index.html') bytes = Buffer.from(bytes.toString().replace('<head>', `<head><meta name="test-release" content="${version}">`))
  if (relative === 'sw.js') bytes = Buffer.from(bytes.toString().replace(/const CACHE = 'traininglog-shell-[^']+';/, `const CACHE = 'traininglog-shell-update-test-${version}';`))
  response.writeHead(200, { 'Content-Type': types[extname(path)] ?? 'application/octet-stream' }).end(bytes)
 } catch (error) {
  response.writeHead(error?.code === 'ENOENT' ? 404 : 500).end()
 }
})
server.listen(5187, '127.0.0.1', () => console.log('Update test server: http://127.0.0.1:5187/training/'))
