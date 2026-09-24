@echo off
rem Jalankan auto-sync sekali (tanpa Scheduled Task). Biarkan jendela ini terbuka.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-sync.ps1"
