import { readdir, readFile, writeFile } from 'node:fs/promises'
import { createHash } from 'node:crypto'
const files = ['index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', ...(await readdir('dist/assets')).map(f => `assets/${f}`)]
const hash = createHash('sha256')
// Changes to the worker itself must also create a distinct offline cache.
hash.update(await readFile(new URL(import.meta.url)))
for (const file of files) hash.update(await readFile(`dist/${file}`))
const version = hash.digest('hex').slice(0,16)
const source = `
const CACHE = 'traininglog-shell-${version}';
const URLS = ${JSON.stringify(files.map(f=>'/training/'+f))};
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(URLS)));
});
// Activate early only after an explicit click in the application.
self.addEventListener('message', event => {
  if (event.data?.type !== 'TRAININGLOG_APPLY_UPDATE' || !event.source?.url) return;
  const source = new URL(event.source.url);
  if (source.origin !== self.location.origin || !source.pathname.startsWith('/training/')) return;
  event.waitUntil(self.skipWaiting());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) if (key.startsWith('traininglog-shell-') && key !== CACHE) await caches.delete(key);
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  const path = url.pathname;
  const isDocument = event.request.mode === 'navigate' && (path === '/training/' || path === '/training/index.html');
  if (!isDocument && !URLS.includes(path)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    return (await cache.match(isDocument ? '/training/index.html' : path)) || fetch(event.request);
  })());
});
`
await writeFile('dist/sw.js',source)
console.log(`Offline app shell: ${files.length} files, ${version}`)
