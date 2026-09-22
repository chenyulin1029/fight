@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Prepare-HumanExplorerGate.ps1" -PackagePath "%~dp0FileDone-P1.8B-Shipping-x64.msix"
if errorlevel 1 (
  echo.
  echo [FileDone] HUMAN GATE PREP FAILED
  pause
  exit /b 1
)
echo.
echo [FileDone] HUMAN GATE READY
pause
