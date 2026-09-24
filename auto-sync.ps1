# Auto-commit + auto-push + auto-pull setiap ada perubahan di folder ini.
# Untuk Windows. Dijalankan oleh Scheduled Task: autosync-git
# Jalankan: powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-sync.ps1 [-Once]
#   -Once = mode sekali-jalan (commit/pull/push sekali, lalu keluar; tanpa loop)
param([switch]$Once)
$ErrorActionPreference = 'Continue'

# Jangan pernah menunggu prompt di jendela Hidden Scheduled Task:
# gagal cepat + masuk log, bukan hang tanpa jejak.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE     = 'Never'
$env:GIT_ASKPASS         = 'echo'

$RepoDir   = $PSScriptRoot
$LogFile   = Join-Path $RepoDir '.autosync.log'
$IntervalSec = 2
$SettleSec   = 1
$GitTimeoutSec = 45
# Setelah konflik rebase: jeda dulu biar tidak spam abort + notifikasi tiap interval.
$ConflictCooldownSec = 120

$mutex = New-Object System.Threading.Mutex($false, 'Local\autosync-git')
if (-not $mutex.WaitOne(0)) {
    exit 0
}

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Invoke-Git {
    # PS 5.1: jangan campur ValueFromRemainingArguments + param typed lain
    # (argumen positional seperti "pull" bisa salah diikat ke param typed).
    # Semua argumen git masuk lewat named -GitArgs; timeout via -Timeout (opsional).
    # Pakai $GitArgs (bukan $Args) supaya tidak bentrok dengan automatic $args di PS.
    param(
        [Parameter(Mandatory = $true)][string[]]$GitArgs,
        [int]$Timeout = 0
    )
    $TimeoutSec = if ($Timeout -gt 0) { $Timeout } else { $GitTimeoutSec }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $argLine = ($GitArgs | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $RepoDir

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        return [pscustomobject]@{ Code = -1; Out = ''; Err = ("gagal start git: {0}" -f $_.Exception.Message) }
    }
    if (-not $proc) {
        return [pscustomobject]@{ Code = -1; Out = ''; Err = 'gagal start git' }
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        $null = $proc.WaitForExit(3000)
        try { $proc.Dispose() } catch { }
        return [pscustomobject]@{
            Code = -1
            Out  = ''
            Err  = ("timeout after {0}s (proses git di-kill)" -f $TimeoutSec)
        }
    }

    $null = $outTask.Wait(2000)
    $null = $errTask.Wait(2000)

    $out = ''
    $err = ''
    try { if ($outTask.IsCompleted) { $out = $outTask.Result } } catch { }
    try { if ($errTask.IsCompleted) { $err = $errTask.Result } } catch { }

    $code = $proc.ExitCode
    try { $proc.Dispose() } catch { }

    if ($out) { $out = $out.Trim() }
    if ($err) { $err = $err.Trim() }
    [pscustomobject]@{ Code = $code; Out = $out; Err = $err }
}

function Get-Head {
    $r = Invoke-Git -GitArgs @('rev-parse', 'HEAD') -Timeout 15
    if ($r.Code -eq 0 -and $r.Out) { $r.Out } else { $null }
}

function Get-AheadCount {
    $r = Invoke-Git -GitArgs @('rev-list', '--count', 'origin/main..HEAD') -Timeout 15
    if ($r.Code -eq 0 -and $r.Out -match '^\d+$') { [int]$r.Out } else { 0 }
}

function Get-Status { @(git status --porcelain 2>$null) }

function Write-FailOnce {
    <# Log galat hanya saat pesan berubah atau tiap ~30 kegagalan (~1 menit). #>
    param(
        [string]$Kind,
        [string]$Message,
        [ref]$LastMsg,
        [ref]$Count
    )
    $Count.Value = [int]$Count.Value + 1
    $msg = if ($Message) { $Message } else { 'galat tidak diketahui' }
    $short = ($msg -split "`r?`n" | Select-Object -First 3) -join ' | '
    if ($short.Length -gt 400) { $short = $short.Substring(0, 400) }
    if ($Count.Value -eq 1 -or $short -ne $LastMsg.Value -or ($Count.Value % 30) -eq 0) {
        Write-Log ("{0} FAIL (x{1}): {2}" -f $Kind, $Count.Value, $short)
        $LastMsg.Value = $short
    }
}

$script:lastPullErr = ''
$script:lastPushErr = ''
$script:pullFailN   = 0
$script:pushFailN   = 0
# Penanda rentetan konflik: 0 = tidak sedang konflik.
$script:conflictStreak  = 0
$script:lastConflictLog = ''
$script:conflictHasStash = $false

function Test-RebaseInProgress {
    $r = Invoke-Git -GitArgs @('rev-parse', '--git-dir') -Timeout 10
    $gitDir = if ($r.Code -eq 0 -and $r.Out) { $r.Out } else { '.git' }
    if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
        $gitDir = Join-Path $RepoDir $gitDir
    }
    return (Test-Path -LiteralPath (Join-Path $gitDir 'rebase-merge')) -or
           (Test-Path -LiteralPath (Join-Path $gitDir 'rebase-apply'))
}

function Handle-RebaseConflict {
    # $1 = output git pull yang gagal.
    # return $true = ini konflik rebase (rebase sudah diabort); $false = galat lain.
    param([string]$ErrText)
    $inRebase = Test-RebaseInProgress
    if (-not $inRebase -and $ErrText -notmatch 'CONFLICT' -and $ErrText -notmatch 'could not be applied') {
        return $false
    }
    if ($inRebase) {
        $null = Invoke-Git -GitArgs @('rebase', '--abort') -Timeout 15
    }
    # Autostash dari --autostash: JANGAN pop otomatis (bisa membuat conflict marker
    # di working tree). Tandai saja, user pop manual via 'git stash pop'.
    $script:conflictHasStash = $false
    $stash = Invoke-Git -GitArgs @('stash', 'list') -Timeout 10
    if ($stash.Code -eq 0 -and $stash.Out -match 'autostash') {
        $script:conflictHasStash = $true
    }
    return $true
}

function Show-ConflictNotify {
    # Balloon notification best-effort: gagal = diam (session headless tanpa tray).
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Warning
        $ni.Visible = $true
        $msg = "Konflik git di $RepoDir - rebase diabort, sinkronisasi dijeda ${ConflictCooldownSec}s. Selesaikan konflik manual, lalu watcher lanjut sendiri."
        $ni.ShowBalloonTip(10000, 'AutoSync Git', $msg, [System.Windows.Forms.ToolTipIcon]::Warning)
        Start-Sleep -Seconds 3
        $ni.Dispose()
    } catch { }
}

Set-Location -LiteralPath $RepoDir
if ($Once) {
    Write-Log 'once run (mode sekali-jalan)'
} else {
    Write-Log ("watcher started (pid {0})" -f $PID)
}

while ($true) {
    try {
        $status = Get-Status
        $dirty  = $status.Count -gt 0

        if ($dirty) {
            Start-Sleep -Seconds $SettleSec
            $status = Get-Status
            $dirty  = $status.Count -gt 0
        }

        $changed = ''
        if ($dirty) {
            $changed = (($status | Select-Object -First 20) -join '; ')
            git add -A 2>$null | Out-Null

            $name = git config user.name 2>$null
            if (-not $name) { $name = 'unknown' }

            $msg = 'auto-sync: {0} [{1}]' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $name
            git commit -m $msg 2>$null | Out-Null
        }

        $before = Get-Head

        $pull = Invoke-Git -GitArgs @('pull', '--rebase', '--autostash')
        $isConflict = $false
        if ($pull.Code -ne 0) {
            $errText = ('{0}{1}{2}' -f $pull.Err, "`n", $pull.Out)
            if (Handle-RebaseConflict -ErrText $errText) {
                $isConflict = $true
            } else {
                $script:conflictStreak = 0
                Write-FailOnce -Kind 'PULL' -Message $pull.Err -LastMsg ([ref]$script:lastPullErr) -Count ([ref]$script:pullFailN)
            }
        } else {
            $script:pullFailN   = 0
            $script:lastPullErr = ''
            $script:conflictStreak = 0
        }

        if ($isConflict) {
            # Konflik rebase: rebase sudah diabort. Tahan push dulu (biar konflik
            # tidak ikut ter-upload ke remote), jeda panjang, notifikasi rate-limited.
            $script:conflictStreak++
            $n = $script:conflictStreak
            if ($n -eq 1 -or ($n % 30) -eq 0) {
                Write-Log ("CONFLICT (x{0}): rebase diabort - sinkronisasi dijeda {1}s" -f $n, $ConflictCooldownSec)
                if ($script:conflictHasStash) {
                    Write-Log "CONFLICT: ada perubahan autostash - jalankan 'git stash pop' manual"
                }
            }
            if ($n -eq 1) { Show-ConflictNotify }
            if ($dirty) { Write-Log "COMMIT_OK_KONFLIK: $changed" }
            if ($Once) { break }
            Start-Sleep -Seconds $ConflictCooldownSec
            continue
        }

        # Hitung ahead SEBELUM push: dipakai untuk log push yang sukses
        # padahal tree bersih (tanpa ini, push no-op/commit lokal tidak pernah muncul di log).
        $aheadBefore = Get-AheadCount

        $push = Invoke-Git -GitArgs @('push')
        $pushOk = ($push.Code -eq 0)
        if (-not $pushOk) {
            Write-FailOnce -Kind 'PUSH' -Message $push.Err -LastMsg ([ref]$script:lastPushErr) -Count ([ref]$script:pushFailN)
        } else {
            $script:pushFailN   = 0
            $script:lastPushErr = ''
        }

        $after = Get-Head

        if ($dirty) {
            if ($pushOk) {
                Write-Log "PUSHED: $changed"
            } else {
                Write-Log "COMMIT_OK_PUSH_FAIL: $changed"
            }
        }
        elseif ($before -and $after -and $before -ne $after) {
            Write-Log 'PULLED: update dari GitHub'
        }
        elseif ($aheadBefore -gt 0 -and $pushOk) {
            Write-Log ("PUSHED: push {0} commit lokal (tree bersih)" -f $aheadBefore)
        }
    }
    catch {
        Write-Log ("ERROR: {0}" -f $_.Exception.Message)
    }

    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSec
}
