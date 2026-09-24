# Fix otomatis: pull fix terbaru, restart watcher, lalu diagnosa.
# Jalankan sekali dari folder repo:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\fix-sync.ps1
$ErrorActionPreference = 'Continue'

# Fail-fast: jangan pernah nunggu prompt login di tengah script.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE     = 'Never'
$env:GIT_ASKPASS         = 'echo'

$RepoDir   = $PSScriptRoot
$TaskName  = 'autosync-git'
$LogFile   = Join-Path $RepoDir '.autosync.log'

function Step($n, $msg) {
    Write-Host ''
    Write-Host ('=== {0}: {1} ===' -f $n, $msg) -ForegroundColor Cyan
}

try { Set-Location -LiteralPath $RepoDir } catch {
    Write-Host ('Gagal masuk folder: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
Write-Host ('Folder: {0}' -f $RepoDir) -ForegroundColor Yellow

Step '1/5' 'git pull --rebase'
$pull = & git pull --rebase 2>&1
$pull | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    Write-Host 'WARN: pull gagal / offline. Lanjut restart task saja.' -ForegroundColor Yellow
} else {
    Write-Host 'pull OK' -ForegroundColor Green
}

Step '2/5' ('stop task {0}' -f $TaskName)
try {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host 'stop OK' -ForegroundColor Green
} catch {
    Write-Host ('stop dilewati: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}
Start-Sleep -Seconds 1

Step '3/5' ('start task {0}' -f $TaskName)
try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host 'start OK' -ForegroundColor Green
} catch {
    Write-Host ('start GAGAL: {0}' -f $_.Exception.Message) -ForegroundColor Red
}
Write-Host 'tunggu 10 detik biar watcher jalan...' -ForegroundColor Yellow
Start-Sleep -Seconds 10

Step '4/5' 'status task'
try {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host ('State={0}' -f $t.State)
    $ti = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    if ($ti) {
        Write-Host ('LastRunTime={0}  LastTaskResult={1}  NumberOfMissedRuns={2}' -f $ti.LastRunTime, $ti.LastTaskResult, $ti.NumberOfMissedRuns)
    }
} catch {
    Write-Host ('gagal baca task: {0}' -f $_.Exception.Message) -ForegroundColor Red
}

Step '5/5' 'check-sync + log'
$cek = Join-Path $RepoDir 'check-sync.ps1'
if (Test-Path -LiteralPath $cek) {
    # Panggil in-process (bukan spawn powershell baru) supaya output langsung kelihatan.
    & $cek
} else {
    Write-Host 'check-sync.ps1 tidak ada, lewati' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '--- log terakhir (.autosync.log) ---' -ForegroundColor Cyan
if (Test-Path -LiteralPath $LogFile) {
    Get-Content -LiteralPath $LogFile -Tail 30
} else {
    Write-Host 'log belum ada' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== SELESAI - paste semua hasil di atas ke chat ===' -ForegroundColor Green
