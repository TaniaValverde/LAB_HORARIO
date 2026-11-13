$ErrorActionPreference = 'Stop'
$functionsPath = Split-Path $PSScriptRoot -Parent
$repoPath = Split-Path $functionsPath -Parent
$backupsPath = Join-Path $functionsPath 'firebase-export-backups'
$latest = Get-ChildItem -LiteralPath $backupsPath -Directory -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName 'COMPLETE') } |
  Sort-Object Name -Descending | Select-Object -First 1
if (!$latest) { throw 'No verified automatic backup. Run npm.cmd --prefix functions run backup while emulators are running first.' }
Set-Location $repoPath
Write-Host "Importing $($latest.FullName)"
& firebase.cmd emulators:start --project demo-declara-horario --only auth,firestore,functions,storage --import=$($latest.FullName)
exit $LASTEXITCODE
