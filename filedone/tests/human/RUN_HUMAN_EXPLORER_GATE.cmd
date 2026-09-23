@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Administrator permission is required for the unsigned executable MSIX test.
echo [FileDone] Approve the Windows UAC prompt to continue.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Prepare-HumanExplorerGate.ps1"" -PackagePath ""%~dp0FileDone-P1.8B-Shipping-x64.msix""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
  echo.
  echo [FileDone] HUMAN GATE PREP FAILED
  pause
  exit /b 1
)

if not exist "%~dp0HUMAN_TEST_FILES\_START_HERE.txt" (
  echo.
  echo [FileDone] HUMAN GATE PREP FAILED: HUMAN_TEST_FILES was not created.
  echo [FileDone] Expected: %~dp0HUMAN_TEST_FILES
  pause
  exit /b 2
)

echo.
echo [FileDone] Package installed and test files created.
echo [FileDone] Restarting your Windows Explorer so the new FileDone shell extension is loaded...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
start "" explorer.exe
timeout /t 2 /nobreak >nul
start "" explorer.exe "%~dp0HUMAN_TEST_FILES"

echo.
echo [FileDone] HUMAN GATE READY
echo [FileDone] Test folder: %~dp0HUMAN_TEST_FILES
echo [FileDone] Right-click 01_SINGLE_COMPATIBLE.bmp and look for FileDone in the FIRST Windows 11 menu.
pause
