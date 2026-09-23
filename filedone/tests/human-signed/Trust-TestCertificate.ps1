param(
    [string]$RootCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Root.cer')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Administrator rights are required to trust the FileDone QA root certificate.' }
$authority=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SIGNED_GATE_AUTHORITY.json') -Raw | ConvertFrom-Json
$RootCertificatePath=(Resolve-Path -LiteralPath $RootCertificatePath -ErrorAction Stop).Path
$fileHash=(Get-FileHash -LiteralPath $RootCertificatePath -Algorithm SHA256).Hash.ToUpperInvariant()
if($fileHash -ne ([string]$authority.rootCertificateFileSha256).ToUpperInvariant()){ throw "root certificate file hash mismatch expected=$($authority.rootCertificateFileSha256) actual=$fileHash" }
$rootCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($RootCertificatePath)
$thumb=$rootCert.Thumbprint.ToUpperInvariant()
if($thumb -ne ([string]$authority.rootCertificateThumbprint).ToUpperInvariant()){ throw "root certificate thumbprint mismatch expected=$($authority.rootCertificateThumbprint) actual=$thumb" }
if($rootCert.Subject -ne 'CN=FileDone QA Root 2026'){ throw "unexpected QA root subject: $($rootCert.Subject)" }

# Remove stale FileDone self-signed leaf trust left by superseded Human Gate bundles.
$tp=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$tp.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
try {
  @($tp.Certificates) | Where-Object { $_.Subject -eq 'CN=FileDone QA Test' -and $_.Issuer -eq 'CN=FileDone QA Test' } | ForEach-Object { $tp.Remove($_) }
} finally { $tp.Close() }

& certutil.exe -addStore -f Root $RootCertificatePath | Out-Host
if($LASTEXITCODE -ne 0){ throw "certutil Root import failed: $LASTEXITCODE" }
$store=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::Root,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
  $match=$store.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $thumb } | Select-Object -First 1
  if(!$match){ throw 'QA root certificate was not found in LocalMachine Root after certutil import' }
} finally { $store.Close() }
Write-Host "FILEDONE_QA_ROOT_TRUST_PASS THUMBPRINT=$thumb"