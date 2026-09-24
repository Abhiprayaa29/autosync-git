# Diagnosa cepat auto-sync (Windows) - jalankan dari folder repo:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\check-sync.ps1
# Output bisa di-copy ke chat grup kalau sync bermasalah.
$ErrorActionPreference = 'Continue'
# Fail-fast di jendela Hidden / non-interaktif: jangan hang nunggu popup login.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE     = 'Never'
$env:GIT_ASKPASS         = 'echo'
$RepoDir  = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$TaskName = 'autosync-git'
$fail = 0

function OK($m)  { Write-Host "[OK]   $m" -ForegroundColor Green }
function BAD($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; $script:fail++ }
function WARN($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function SEP($m) { Write-Host ''; Write-Host "=== $m ===" -ForegroundColor Cyan }

SEP 'check-sync: AutoSync Git'
Write-Host "Repo : $RepoDir"
Write-Host "Waktu: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

SEP '1. Git terpasang'
if (Get-Command git -ErrorAction SilentlyContinue) {
    OK ("git " + (git --version))
} else {
    BAD 'git tidak ditemukan di PATH'
}

SEP '2. Identitas git'
$n = git config --global user.name
$e = git config --global user.email
if ($n -and $e) { OK "$n <$e>" } else { BAD 'user.name / user.email belum diisi' }

SEP '3. Folder repo'
if (Test-Path (Join-Path $RepoDir '.git')) { OK 'folder ini adalah clone git' }
else { BAD "bukan folder repo git: $RepoDir" }

SEP '4. Remote + otorisasi (git ls-remote)'
$remote = git remote get-url origin 2>&1
Write-Host "origin = $remote"
$ls = & git ls-remote origin HEAD 2>&1
$lsCode = $LASTEXITCODE
if ($lsCode -eq 0) {
    OK 'bisa baca remote (auth/pull path jalan)'
} else {
    BAD ("ls-remote gagal (exit $lsCode): " + (($ls | Out-String).Trim()))
    WARN 'Kemungkinan: belum login GitHub. Jalankan sekali: git push  (popup login), atau gh auth login'
}

SEP '5. Scheduled Task'
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    BAD "task '$TaskName' tidak ada - jalankan setup-autosync.ps1 / join.ps1 lagi"
} else {
    Write-Host ("State    : {0}" -f $task.State)
    if ($task.State -eq 'Running') { OK 'task Running' }
    else { WARN "task state = $($task.State) - Start-ScheduledTask -TaskName $TaskName" }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($info) {
        Write-Host ("LastRun  : {0}" -f $info.LastRunTime)
        Write-Host ("LastRes  : {0}" -f $info.LastTaskResult)
        if ($info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267009) {
            WARN ("LastTaskResult tidak 0: {0}" -f $info.LastTaskResult)
        }
    }
}

SEP '6. git status / unpushed'
Push-Location -LiteralPath $RepoDir
try {
    git status -sb
    $ahead = git rev-list --count origin/main..HEAD 2>$null
    Write-Host "commits belum ke remote: $ahead"
    if ($ahead -and [int]$ahead -gt 0) { WARN 'ada commit lokal yang belum push' }

    SEP '7. Log auto-sync (.autosync.log) - 30 baris terakhir'
    $logPath = Join-Path $RepoDir '.autosync.log'
    if (Test-Path $logPath) {
        Get-Content $logPath -Tail 30
        $bad = Select-String -Path $logPath -Pattern 'FAIL|ERROR' -ErrorAction SilentlyContinue
        if ($bad) {
            BAD ("ada {0} baris FAIL/ERROR di log - lihat pesan auth/conflict di atas" -f @($bad).Count)
        } else {
            OK 'tidak ada FAIL/ERROR di log'
        }
        $pushed = Select-String -Path $logPath -Pattern 'PUSHED:' -ErrorAction SilentlyContinue
        if ($pushed) { OK ("pernah PUSHED (" + @($pushed).Count + "x)") }
        else { WARN 'belum pernah ada baris PUSHED' }
    } else {
        BAD '.autosync.log belum ada - watcher belum pernah jalan'
    }

    SEP '8. Push percobaan (sekali; aman kalau tidak ada perubahan)'
    $st = @(git status --porcelain)
    if ($st.Count -eq 0) {
        # push tanpa perubahan = no-op kalau sudah sync; tetap membuktikan auth
        $p = & git push 2>&1
        if ($LASTEXITCODE -eq 0) { OK 'git push OK (auth remote lolos)' }
        else { BAD ("git push gagal: " + (($p | Out-String).Trim())) }
    } else {
        WARN 'ada perubahan lokal - biarkan auto-sync yang push, atau git push manual setelah login'
    }
}
finally {
    Pop-Location
}

SEP 'Ringkasan'
if ($fail -eq 0) {
    Write-Host 'SEMUA CHECK LOLOS - kalau file teman tetap tidak masuk, kirim screenshot log ini.' -ForegroundColor Green
} else {
    Write-Host ("{0} CHECK GAGAL - copy seluruh output jendela ini ke chat." -f $fail) -ForegroundColor Red
    Write-Host 'Fix paling umum: jalankan `git push` sekali di jendela PowerShell biasa, login GitHub, centang remember.'
}
exit $fail
