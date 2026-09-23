@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Administrator permission is required for this unsigned executable MSIX test.
echo [FileDone] Approve the Windows UAC prompt to continue.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Prepare-HumanExplorerGate.ps1"" -PackagePath ""%~dp0FileDone-P1.8B-Shipping-x64.msix""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
  echo.
  echo [FileDone] HUMAN GATE PREP FAILED
  pause
  exit /b 1
)
echo.
echo [FileDone] HUMAN GATE READY
pause
