# Run only after closing Firebase Emulator Suite and completing a backup.
$ErrorActionPreference = 'Stop'
$ports = Get-NetTCPConnection -State Listen -LocalPort 8180,9151 -ErrorAction SilentlyContinue
foreach ($processNumber in ($ports.OwningProcess | Sort-Object -Unique)) {
  $candidate = Get-CimInstance Win32_Process -Filter "ProcessId=$processNumber"
  if (!$candidate) { continue }
  if ($candidate.CommandLine -notmatch 'cloud-firestore-emulator.*--project_id demo-declara-horario') {
    throw "Port belongs to another application (PID $processNumber). No process stopped."
  }
  if (Get-Process -Id $candidate.ParentProcessId -ErrorAction SilentlyContinue) {
    throw "Firebase parent process is still active. Close its terminal session first."
  }
  $backupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'firebase-export-backups'
  $complete = Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'COMPLETE') } |
    Sort-Object Name -Descending | Select-Object -First 1
  if (!$complete) { throw 'No complete backup found. No process stopped.' }
  Write-Host "Last verified backup: $($complete.FullName)"
  $answer = Read-Host "Confirm that your final changes were backed up before closing Firebase. Stop orphan PID $processNumber? (S/N)"
  if ($answer -ne 'S') { throw 'Cancelled; no process stopped.' }
  # Recheck identity immediately before stopping; do not stop all Java processes.
  $current = Get-CimInstance Win32_Process -Filter "ProcessId=$processNumber"
  if ($current.CreationDate -ne $candidate.CreationDate -or $current.CommandLine -ne $candidate.CommandLine) {
    throw 'Process changed. No process stopped.'
  }
  Stop-Process -Id $processNumber
}
Write-Host 'Check complete. You can retry emulators:restore.'
