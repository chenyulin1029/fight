param(
    [string]$RootCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Root.cer'),
    [string]$LeafCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-CodeSigning.cer')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Administrator rights are required to remove FileDone QA certificates.' }
$RootCertificatePath=(Resolve-Path -LiteralPath $RootCertificatePath -ErrorAction Stop).Path
$LeafCertificatePath=(Resolve-Path -LiteralPath $LeafCertificatePath -ErrorAction Stop).Path
$rootCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($RootCertificatePath)
$leafCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($LeafCertificatePath)
$rootThumb=$rootCert.Thumbprint.ToUpperInvariant()
$leafThumb=$leafCert.Thumbprint.ToUpperInvariant()
$rootStore=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::Root,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
try { @($rootStore.Certificates) | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $rootThumb } | ForEach-Object { $rootStore.Remove($_) } } finally { $rootStore.Close() }
$tpStore=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$tpStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
try { @($tpStore.Certificates) | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $leafThumb -or $_.Subject -eq 'CN=FileDone QA Test' } | ForEach-Object { $tpStore.Remove($_) } } finally { $tpStore.Close() }
Write-Host "FILEDONE_QA_CHAIN_CLEANUP_PASS ROOT=$rootThumb LEAF=$leafThumb"