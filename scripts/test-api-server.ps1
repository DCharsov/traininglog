$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runData = Join-Path $repo ('deploy/test-api-' + [guid]::NewGuid().ToString())
$testPassword = Join-Path $repo 'tests/e2e-password.txt'
dotnet run --project (Join-Path $repo 'apps/api') --no-launch-profile -- --urls http://127.0.0.1:5181 --environment Development --DataDirectory $runData --OwnerPasswordFile $testPassword
exit $LASTEXITCODE
