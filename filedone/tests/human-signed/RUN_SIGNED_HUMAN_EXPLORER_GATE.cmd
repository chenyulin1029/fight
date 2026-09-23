@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Step 1/3: trust the QA signing certificate.
echo [FileDone] Approve the Windows UAC prompt once.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Trust-TestCertificate.ps1"" -CertificatePath ""%~dp0FileDone-QA-Test.cer""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (echo [FileDone] CERTIFICATE TRUST FAILED&pause&exit /b 1)
echo.
echo [FileDone] Step 2/3: install signed QA MSIX for your current Windows user.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Prepare-SignedHumanExplorerGate.ps1" -PackagePath "%~dp0FileDone-P1.8B-QA-Signed.msix"
if errorlevel 1 (echo [FileDone] SIGNED HUMAN GATE PREP FAILED&pause&exit /b 2)
if not exist "%~dp0HUMAN_TEST_FILES\_START_HERE.txt" (echo [FileDone] HUMAN_TEST_FILES missing&pause&exit /b 3)
echo.
echo [FileDone] Step 3/3: restarting your Explorer to load FileDone.
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
start "" explorer.exe
timeout /t 2 /nobreak >nul
start "" explorer.exe "%~dp0HUMAN_TEST_FILES"
echo.
echo [FileDone] SIGNED HUMAN GATE READY
echo [FileDone] Right-click 01_SINGLE_COMPATIBLE.bmp.
pause