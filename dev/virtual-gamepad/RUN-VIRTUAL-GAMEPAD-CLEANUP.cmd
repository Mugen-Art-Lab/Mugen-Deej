@echo off
setlocal
cd /d "%~dp0"
set "HOST=%~dp0host\MugenDeej.VirtualGamepadHost.exe"

if not exist "%HOST%" (
  echo Virtual gamepad host not found:
  echo %HOST%
  pause
  exit /b 1
)

echo Mugen Deej Virtual Gamepad Cleanup
echo ----------------------------------
echo This removes HIDMaestro virtual controllers while keeping the installed backend.
echo Accept the UAC prompt.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Start-Process -FilePath '%HOST%' -ArgumentList 'cleanup' -Verb RunAs -Wait -PassThru; exit $p.ExitCode"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo Cleanup command finished successfully.
) else (
  echo Cleanup command failed with exit code %RC%.
  echo Host log: %TEMP%\MugenDeej-VirtualGamepadHost.log
)
pause
exit /b %RC%
