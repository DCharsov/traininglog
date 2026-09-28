import { spawn, spawnSync } from 'node:child_process'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const dotnet = process.env.TRAINING_DOTNET ?? 'dotnet'
const build = spawnSync(dotnet, ['build', join(repo, 'apps/api/api.csproj'), '-p:RestoreLockedMode=true', '-p:RuntimeIdentifiers=linux-x64', '--verbosity', 'quiet'], { stdio: 'inherit' })
if (build.error || build.status !== 0) { console.error(build.error ?? 'API build failed'); process.exit(1) }
const runData = await mkdtemp(join(tmpdir(), 'traininglog-api-test-'))
const child = spawn(dotnet, [join(repo, 'apps/api/bin/Debug/net10.0/api.dll'), '--urls', 'http://127.0.0.1:5181', '--environment', 'Development', '--DataDirectory', runData, '--OwnerPasswordFile', join(repo, 'tests/e2e-password.txt'), '--Watch:Enabled', 'true'], { stdio: 'inherit', cwd: repo })
let stopping = false
const stop = () => { if (!stopping) { stopping = true; child.kill('SIGTERM') } }
process.on('SIGTERM', stop); process.on('SIGINT', stop)
child.on('error', async error => { console.error(error); await rm(runData, { recursive: true, force: true }); process.exit(1) })
child.on('exit', async code => {
 await rm(runData, { recursive: true, force: true }) // Only our mkdtemp directory, never a configured data directory.
 process.exit(stopping ? 0 : code ?? 1)
})
