@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Build-Release.ps1" %*
set "exitCode=%ERRORLEVEL%"

echo.
if not "%exitCode%"=="0" (
    echo Build failed with exit code %exitCode%.
) else (
    echo Build completed successfully.
)

echo.
pause
exit /b %exitCode%
