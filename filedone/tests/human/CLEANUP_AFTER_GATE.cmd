@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Cleanup-HumanExplorerGate.ps1"
if errorlevel 1 (
  echo.
  echo [FileDone] CLEANUP FAILED
  pause
  exit /b 1
)
echo.
echo [FileDone] PACKAGE REMOVED. Test files were kept on Desktop.
pause
