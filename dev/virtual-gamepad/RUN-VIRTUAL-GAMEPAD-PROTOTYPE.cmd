@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Mugen-VirtualGamepad-Prototype.ps1" %*
pause
