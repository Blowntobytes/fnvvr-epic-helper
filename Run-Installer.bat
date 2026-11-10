@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-FNVVR-Epic.ps1" %*
echo.
pause
