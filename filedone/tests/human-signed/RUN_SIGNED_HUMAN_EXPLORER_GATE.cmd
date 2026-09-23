@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Step 1/3: atomically trust certificates and install signed QA MSIX.
echo [FileDone] Approve the Windows UAC prompt once.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Run-AtomicHumanExplorerGate.ps1"" -PackagePath ""%~dp0FileDone-P1.8B-QA-Signed.msix"" -RootCertificatePath ""%~dp0FileDone-QA-Root.cer"" -LeafCertificatePath ""%~dp0FileDone-QA-CodeSigning.cer"" -ExpectedUserSid ""'+$sid+'""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (echo [FileDone] ATOMIC TRUST/INSTALL FAILED&pause&exit /b 1)
if not exist "%~dp0HUMAN_TEST_FILES\_START_HERE.txt" (echo [FileDone] HUMAN_TEST_FILES missing&pause&exit /b 2)
if not exist "%~dp0ELEVATED_INSTALL_PROOF.json" (echo [FileDone] ELEVATED_INSTALL_PROOF.json missing&pause&exit /b 3)
echo.
echo [FileDone] Step 2/3: create Human Gate test files as your normal USER.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Prepare-SignedHumanExplorerGate.ps1" -PackagePath "%~dp0FileDone-P1.8B-QA-Signed.msix" -SkipInstall
if errorlevel 1 (echo [FileDone] HUMAN TEST FILE PREP FAILED&pause&exit /b 4)
if not exist "%~dp0HUMAN_TEST_FILES\_START_HERE.txt" (echo [FileDone] HUMAN_TEST_FILES missing after USER prep&pause&exit /b 5)
echo.
echo [FileDone] Step 3/3: restarting your Explorer to load FileDone.
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
start "" explorer.exe
timeout /t 2 /nobreak >nul
start "" explorer.exe "%~dp0HUMAN_TEST_FILES"
echo.
echo [FileDone] ATOMIC HUMAN GATE READY
echo [FileDone] Right-click 01_SINGLE_COMPATIBLE.bmp.
pause