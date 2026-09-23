param(
  [string]$PackagePath = (Join-Path $PSScriptRoot 'FileDone-P1.8B-QA-Signed.msix'),
  [string]$RootCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Root.cer'),
  [string]$LeafCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-CodeSigning.cer'),
  [Parameter(Mandatory=$true)][string]$ExpectedUserSid
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$pr=[Security.Principal.WindowsPrincipal]::new($id)
if(!$pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Atomic Human Gate must run elevated.' }
$sid=$id.User.Value
if($sid -ne $ExpectedUserSid){ throw "UAC identity mismatch expected=$ExpectedUserSid actual=$sid" }

& (Join-Path $PSScriptRoot 'Trust-TestCertificate.ps1') -RootCertificatePath $RootCertificatePath -LeafCertificatePath $LeafCertificatePath

$rootCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($RootCertificatePath)
$leafCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($LeafCertificatePath)
$rootThumb=$rootCert.Thumbprint.ToUpperInvariant()
$leafThumb=$leafCert.Thumbprint.ToUpperInvariant()

$rs=[System.Security.Cryptography.X509Certificates.X509Store]::new('Root','LocalMachine')
$ts=[System.Security.Cryptography.X509Certificates.X509Store]::new('TrustedPeople','LocalMachine')
$rs.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
$ts.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
  $rootFound=@($rs.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $rootThumb }).Count -gt 0
  $leafFound=@($ts.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $leafThumb }).Count -gt 0
} finally { $rs.Close(); $ts.Close() }
if(!$rootFound){ throw 'QA root is not visible in LocalMachine Root after elevated import.' }
if(!$leafFound){ throw 'QA leaf is not visible in LocalMachine TrustedPeople after elevated import.' }

$chain=New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chain.ChainPolicy.RevocationMode=[System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
$chain.ChainPolicy.VerificationFlags=[System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
$chainOk=$chain.Build($leafCert)
$chainStatus=@($chain.ChainStatus | ForEach-Object { $_.Status.ToString() + ':' + $_.StatusInformation.Trim() })
if(!$chainOk){ throw ('QA leaf chain build failed after elevated import: ' + ($chainStatus -join ' | ')) }

$sig=Get-AuthenticodeSignature -LiteralPath $PackagePath
if(!$sig.SignerCertificate){ throw 'MSIX signer certificate missing.' }
if($sig.SignerCertificate.Thumbprint.ToUpperInvariant() -ne $leafThumb){ throw 'MSIX signer does not match QA leaf.' }
if($sig.Status -ne [System.Management.Automation.SignatureStatus]::Valid){ throw "MSIX signature invalid after trust import: $($sig.Status) $($sig.StatusMessage)" }

$proof=Join-Path $PSScriptRoot 'ELEVATED_INSTALL_PROOF.json'
[ordered]@{timestamp=(Get-Date).ToString('o');user=$id.Name;sid=$sid;rootFound=$rootFound;leafFound=$leafFound;chainBuild=$chainOk;chainStatus=$chainStatus;authenticode=$sig.Status.ToString();stage='TRUST_VERIFIED'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $proof -Encoding utf8

Get-AppxPackage -Name FileDone.QATestSigned -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -Name FileDone.DevShell -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
Add-AppxPackage -Path $PackagePath -ForceApplicationShutdown -ErrorAction Stop

$pkg=Get-AppxPackage -Name FileDone.QATestSigned -ErrorAction Stop | Select-Object -First 1
if(!$pkg){ throw 'Package is not registered after atomic Add-AppxPackage.' }
$p=Get-Content -LiteralPath $proof -Raw | ConvertFrom-Json
$p.stage='PACKAGE_INSTALLED'
$p | Add-Member -NotePropertyName packageFullName -NotePropertyValue $pkg.PackageFullName -Force
$p | Add-Member -NotePropertyName installLocation -NotePropertyValue $pkg.InstallLocation -Force
$p | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $proof -Encoding utf8
Write-Host "FILEDONE_ATOMIC_ELEVATED_TRUST_INSTALL_PASS USER=$($id.Name) SID=$sid"