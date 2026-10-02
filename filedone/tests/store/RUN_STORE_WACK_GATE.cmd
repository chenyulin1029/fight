@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Microsoft Store WACK Gate
echo [FileDone] Approve the Windows UAC prompt once.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Run-StoreWackGate.ps1"" -PackagePath ""%~dp0FileDone-Store-RC-x64.msix"" -CertificatePath ""%~dp0FileDone-Store-RC-Signer.cer"" -OutputDirectory ""%~dp0""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
  echo.
  echo [FileDone] STORE WACK GATE FAILED
  echo [FileDone] Keep WACK-report.xml if one was created.
  pause
  exit /b 1
)
echo.
echo [FileDone] STORE WACK GATE PASS
echo [FileDone] Evidence: FileDone-Store-WACK-Evidence.zip
pause