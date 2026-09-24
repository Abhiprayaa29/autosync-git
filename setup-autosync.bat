@echo off
rem Setup AutoSync Git (Windows) - klik dua kali file ini.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-autosync.ps1"
echo.
pause
