# Setup sekali jalan (Windows):
#   1. cek prasyarat (git + identitas git)
#   2. daftarkan Scheduled Task auto-sync (jalan tiap login)
#   3. jalankan auto-sync sekarang juga
# Jalankan dari folder repo:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-autosync.ps1
# Atau klik dua kali setup-autosync.bat
$ErrorActionPreference = 'Stop'

$RepoDir   = $PSScriptRoot
$TaskName  = 'autosync-git'
$ScriptPs1 = Join-Path $RepoDir 'auto-sync.ps1'

Write-Host '== Setup AutoSync Git (Windows) =='
Write-Host "Repo: $RepoDir"
Write-Host ''

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'ERROR: git belum terpasang.' -ForegroundColor Red
    Write-Host 'Install dulu: https://git-scm.com/download/win  (Git for Windows)'
    exit 1
}

$userName  = git config --global user.name
$userEmail = git config --global user.email
if (-not $userName -or -not $userEmail) {
    # Auto-fill - jangan minta input (plug & play).
    if (-not $userName)  { $userName  = [Environment]::UserName }
    if (-not $userEmail) { $userEmail = ($userName.ToLower() -replace '[^a-z0-9-]', '') + '@users.noreply.github.com' }
    git config --global user.name  $userName
    git config --global user.email $userEmail
}

if (-not (Test-Path -LiteralPath $ScriptPs1)) {
    Write-Host "ERROR: file tidak ditemukan: $ScriptPs1" -ForegroundColor Red
    exit 1
}

# Hentikan task lama kalau ada, supaya bisa di-update.
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPs1)

# Mulai otomatis setiap user login.
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'AutoSync Git: auto-commit + auto-pull + auto-push (GitHub)' `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2

# Warmup auth di jendela INTERAKTIF ini - popup Git Credential Manager
# tidak muncul dari Scheduled Task yang window-nya Hidden.
Write-Host 'Cek akses GitHub (popup login mungkin muncul sekali)...' -ForegroundColor Cyan
$null = & git ls-remote origin HEAD 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Belum bisa akses remote. Jalankan SEKALI di jendela ini:' -ForegroundColor Yellow
    Write-Host '  git push' -ForegroundColor Yellow
    Write-Host 'lalu login GitHub di popup, centang remember, tutup, jalankan ulang setup ini.' -ForegroundColor Yellow
} else {
    Write-Host 'Akses GitHub OK.' -ForegroundColor Green
}

$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ''
Write-Host ('Task "{0}" state: {1}' -f $TaskName, $task.State) -ForegroundColor Green
Write-Host ''
Write-Host 'Selesai! Cara pakai:'
Write-Host '  1. Buka folder ini di VS Code:  code .'
Write-Host '  2. Simpan file (Ctrl+S) -> otomatis ke-push / ke-pull (~2 detik)'
Write-Host "  3. Log: $RepoDir\.autosync.log"
Write-Host ''
Write-Host 'Stop sementara : Stop-ScheduledTask -TaskName' $TaskName
Write-Host 'Hapus total    : Unregister-ScheduledTask -TaskName' $TaskName '-Confirm:$false'
