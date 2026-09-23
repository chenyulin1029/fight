@echo off
setlocal
cd /d "%~dp0"
echo [FileDone] Removing signed QA package from your current user...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$p=Get-AppxPackage -Name FileDone.QATestSigned -ErrorAction SilentlyContinue | Select-Object -First 1; if($p){$p | Remove-AppxPackage -ErrorAction Stop}"
if errorlevel 1 (echo [FileDone] PACKAGE CLEANUP FAILED&pause&exit /b 1)
echo [FileDone] Removing FileDone QA root + code-signing certificate. Approve UAC.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$arg='-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Remove-TestCertificate.ps1"" -RootCertificatePath ""%~dp0FileDone-QA-Root.cer"" -LeafCertificatePath ""%~dp0FileDone-QA-CodeSigning.cer""'; try { $p=Start-Process powershell.exe -Verb RunAs -ArgumentList $arg -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (echo [FileDone] CERTIFICATE CLEANUP FAILED&pause&exit /b 2)
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
start "" explorer.exe
echo [FileDone] SIGNED QA PACKAGE AND QA CERTIFICATE CHAIN REMOVED
pause