$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../apps/web')
try {
    foreach ($check in @('test', 'test:e2e', 'test:sync', 'build', 'test:offline', 'lint')) {
        npm run $check
        if ($LASTEXITCODE -ne 0) { throw "Failed: $check" }
    }
} finally { Pop-Location }

dotnet test (Join-Path $PSScriptRoot '../tests/api')
if ($LASTEXITCODE -ne 0) { throw 'API tests failed' }
