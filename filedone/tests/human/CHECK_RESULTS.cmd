@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verify-HumanExplorerGate.ps1"
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo [FileDone] MACHINE OUTPUT CHECK FAILED
if "%RC%"=="0" echo [FileDone] MACHINE OUTPUT CHECK PASSED
pause
exit /b %RC%
