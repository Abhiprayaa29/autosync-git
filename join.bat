@echo off
rem ============================================
rem  AutoSync Git - setup plug & play (Windows)
rem  klik dua kali: pakai join.ps1 yang sudah
rem  ada di folder yang SAMA dengan file ini
rem ============================================
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0join-local.ps1"
echo.
pause
