param(
  [string]$PackagePath = (Join-Path $PSScriptRoot 'FileDone-Store-RC-x64.msix'),
  [string]$CertificatePath = (Join-Path $PSScriptRoot 'FileDone-Store-RC-Signer.cer'),
  [string]$OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($id)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'WACK gate must run elevated in the active interactive user session.' }

$PackagePath=(Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
$CertificatePath=(Resolve-Path -LiteralPath $CertificatePath -ErrorAction Stop).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$cert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
$thumb=$cert.Thumbprint.ToUpperInvariant()
$sigBefore=Get-AuthenticodeSignature -LiteralPath $PackagePath
if(!$sigBefore.SignerCertificate){ throw 'Store RC package has no Authenticode signer.' }
if($sigBefore.SignerCertificate.Thumbprint.ToUpperInvariant() -ne $thumb){ throw 'Store RC package signer does not match bundled validation certificate.' }

$rootStore=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::Root,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$tpStore=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$addedRoot=$false; $addedTp=$false
try {
  $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
  if(-not ($rootStore.Certificates | Where-Object Thumbprint -eq $thumb)){ $rootStore.Add($cert); $addedRoot=$true }
  $rootStore.Close()
  $tpStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
  if(-not ($tpStore.Certificates | Where-Object Thumbprint -eq $thumb)){ $tpStore.Add($cert); $addedTp=$true }
  $tpStore.Close()

  $sig=Get-AuthenticodeSignature -LiteralPath $PackagePath
  if($sig.Status -ne [System.Management.Automation.SignatureStatus]::Valid){ throw "Store RC signature is not valid after temporary trust: $($sig.Status) $($sig.StatusMessage)" }

  $appcert='C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe'
  if(!(Test-Path -LiteralPath $appcert -PathType Leaf)){
    $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
    if(!$winget){ throw 'Windows App Certification Kit is missing and WinGet is unavailable for automatic Windows SDK installation.' }
    Write-Host '[FileDone] Windows App Certification Kit is missing. Installing Microsoft Windows SDK through WinGet...'
    & $winget.Source install --id Microsoft.WindowsSDK.10.0.26100 -e --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if($LASTEXITCODE -ne 0){ throw "Windows SDK WinGet install failed: $LASTEXITCODE" }
    if(!(Test-Path -LiteralPath $appcert -PathType Leaf)){ throw 'Windows SDK installation completed but appcert.exe is still missing.' }
  }
  $report=Join-Path $OutputDirectory 'WACK-report.xml'
  Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue
  & $appcert reset | Out-Host
  if($LASTEXITCODE -ne 0){ throw "WACK reset failed: $LASTEXITCODE" }
  & $appcert test -appxpackagepath $PackagePath -reportoutputpath $report | Out-Host
  if($LASTEXITCODE -ne 0){ throw "WACK package test process failed: $LASTEXITCODE" }
  if(!(Test-Path -LiteralPath $report -PathType Leaf) -or (Get-Item -LiteralPath $report).Length -le 0){ throw 'WACK XML report missing or empty.' }
  [xml]$rx=Get-Content -LiteralPath $report -Raw
  if(!$rx.REPORT){ throw 'WACK report root REPORT element missing.' }
  $overall=[string]$rx.REPORT.OVERALL_RESULT
  if($overall.ToUpperInvariant() -ne 'PASS'){ throw "WACK OVERALL_RESULT is $overall, not PASS. Review WACK-report.xml." }

  $cpu=(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
  $cs=Get-CimInstance Win32_ComputerSystem
  $os=Get-CimInstance Win32_OperatingSystem
  $pkgHash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $reportHash=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash.ToUpperInvariant()
  $evidence=Join-Path $OutputDirectory 'WACK-machine-evidence.json'
  [ordered]@{
    status='PASS'; gate='FILEDONE_STORE_WACK_ACTIVE_USER_MACHINE'; timestamp=(Get-Date).ToString('o');
    user=$id.Name; sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;
    computer=$env:COMPUTERNAME; cpu=$cpu; ramBytes=[int64]$cs.TotalPhysicalMemory;
    osCaption=$os.Caption; osVersion=$os.Version; osBuild=$os.BuildNumber;
    package=(Split-Path -Leaf $PackagePath); packageSha256=$pkgHash; signerThumbprint=$thumb;
    wackOverallResult=$overall; wackReportSha256=$reportHash
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidence -Encoding utf8

  $zip=Join-Path $OutputDirectory 'FileDone-Store-WACK-Evidence.zip'
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
  Compress-Archive -LiteralPath $report,$evidence -DestinationPath $zip -CompressionLevel Optimal
  Write-Host "FILEDONE_STORE_WACK_ACTIVE_USER_MACHINE_PASS PACKAGE_SHA256=$pkgHash REPORT_SHA256=$reportHash"
} finally {
  try {
    try { $rootStore.Close() } catch {}
    $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    if($addedRoot){ @($rootStore.Certificates) | Where-Object Thumbprint -eq $thumb | ForEach-Object { $rootStore.Remove($_) } }
    $rootStore.Close()
  } catch {}
  try {
    try { $tpStore.Close() } catch {}
    $tpStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    if($addedTp){ @($tpStore.Certificates) | Where-Object Thumbprint -eq $thumb | ForEach-Object { $tpStore.Remove($_) } }
    $tpStore.Close()
  } catch {}
}