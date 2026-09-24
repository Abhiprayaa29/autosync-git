# Wrapper lokal untuk join.bat - pakai join.ps1 yang ada di folder ini.
# (join.ps1 asli di-clone/download bareng repo; file ini hanya launcher.)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$join = Join-Path $here 'join.ps1'
if (-not (Test-Path $join)) {
    # Kalau join.ps1 belum ada (mis. baru download ZIP parsial), tarik dari GitHub.
    # GANTI URL di bawah kalau toolkit ini dipakai di repo lain.
    $url = 'https://raw.githubusercontent.com/Abhiprayaa29/autosync-git/main/join.ps1'
    $join = Join-Path $env:TEMP 'autosync-git-join.ps1'
    Invoke-WebRequest -Uri $url -OutFile $join -UseBasicParsing
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $join
