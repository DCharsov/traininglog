$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$backupDir = Join-Path $repo '.secrets/backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$destination = Join-Path $backupDir ('traininglog-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.tar.gz')
$keyFile = Join-Path $env:USERPROFILE '.ssh/id_ed25519_vpnshop_np'
& ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i $keyFile root@cleargate.ru python3 /opt/traininglog/server-backup.py
if ($LASTEXITCODE -ne 0) { throw 'Server backup failed' }
& scp -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i $keyFile root@cleargate.ru:/var/backups/traininglog/latest.tar.gz $destination
if ($LASTEXITCODE -ne 0) { throw 'Backup download failed' }
Write-Output $destination
# Keep the latest 30 downloaded copies, within this explicit backup directory only.
$resolvedBackupDir = (Resolve-Path -LiteralPath $backupDir).Path
Get-ChildItem -LiteralPath $resolvedBackupDir -Filter 'traininglog-*.tar.gz' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 | ForEach-Object {
    $resolvedCopy = (Resolve-Path -LiteralPath $_.FullName).Path
    if ((Split-Path -Parent $resolvedCopy) -ne $resolvedBackupDir) { throw 'Backup path escaped target directory' }
    Remove-Item -LiteralPath $resolvedCopy
}
