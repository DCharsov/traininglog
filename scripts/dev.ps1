$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../apps/web')
try {
    if (-not (Test-Path -LiteralPath 'node_modules')) { npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' } }
    npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
} finally { Pop-Location }
