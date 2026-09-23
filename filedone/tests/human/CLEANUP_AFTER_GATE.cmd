@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Administrator permission is required to clean up the unsigned executable MSIX test package.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Cleanup-HumanExplorerGate.ps1""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
  echo.
  echo [FileDone] CLEANUP FAILED
  pause
  exit /b 1
)
echo.
echo [FileDone] PACKAGE REMOVED. Test files were kept on Desktop.
pause
