param(
    [string]$RootCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Root.cer')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Administrator rights are required to remove the FileDone QA root certificate.' }
$RootCertificatePath=(Resolve-Path -LiteralPath $RootCertificatePath -ErrorAction Stop).Path
$rootCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($RootCertificatePath)
$thumb=$rootCert.Thumbprint.ToUpperInvariant()
$rootStore=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::Root,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
try { @($rootStore.Certificates) | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $thumb } | ForEach-Object { $rootStore.Remove($_) } } finally { $rootStore.Close() }
$tp=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$tp.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
try { @($tp.Certificates) | Where-Object { $_.Subject -eq 'CN=FileDone QA Test' -and $_.Issuer -eq 'CN=FileDone QA Test' } | ForEach-Object { $tp.Remove($_) } } finally { $tp.Close() }
$verify=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::Root,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$verify.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try { if($verify.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $thumb }){ throw 'QA root certificate remained in LocalMachine Root after cleanup' } } finally { $verify.Close() }
Write-Host "FILEDONE_QA_ROOT_CLEANUP_PASS THUMBPRINT=$thumb"