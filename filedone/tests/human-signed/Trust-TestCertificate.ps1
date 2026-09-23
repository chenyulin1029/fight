param(
    [string]$RootCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Root.cer'),
    [string]$LeafCertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-CodeSigning.cer')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Administrator rights are required to trust the FileDone QA certificates.' }
$authority=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SIGNED_GATE_AUTHORITY.json') -Raw | ConvertFrom-Json
$RootCertificatePath=(Resolve-Path -LiteralPath $RootCertificatePath -ErrorAction Stop).Path
$LeafCertificatePath=(Resolve-Path -LiteralPath $LeafCertificatePath -ErrorAction Stop).Path
$rootFileHash=(Get-FileHash -LiteralPath $RootCertificatePath -Algorithm SHA256).Hash.ToUpperInvariant()
$leafFileHash=(Get-FileHash -LiteralPath $LeafCertificatePath -Algorithm SHA256).Hash.ToUpperInvariant()
if($rootFileHash -ne ([string]$authority.rootCertificateFileSha256).ToUpperInvariant()){ throw 'root certificate file hash mismatch' }
if($leafFileHash -ne ([string]$authority.leafCertificateFileSha256).ToUpperInvariant()){ throw 'leaf certificate file hash mismatch' }
$rootCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($RootCertificatePath)
$leafCert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($LeafCertificatePath)
$rootThumb=$rootCert.Thumbprint.ToUpperInvariant()
$leafThumb=$leafCert.Thumbprint.ToUpperInvariant()
if($rootThumb -ne ([string]$authority.rootCertificateThumbprint).ToUpperInvariant()){ throw 'root certificate thumbprint mismatch' }
if($leafThumb -ne ([string]$authority.leafCertificateThumbprint).ToUpperInvariant()){ throw 'leaf certificate thumbprint mismatch' }
& certutil.exe -addStore -f Root $RootCertificatePath | Out-Host
if($LASTEXITCODE -ne 0){ throw "certutil Root import failed: $LASTEXITCODE" }
& certutil.exe -addStore -f TrustedPeople $LeafCertificatePath | Out-Host
if($LASTEXITCODE -ne 0){ throw "certutil TrustedPeople leaf import failed: $LASTEXITCODE" }
Write-Host "FILEDONE_QA_CHAIN_TRUST_PASS ROOT=$rootThumb LEAF=$leafThumb"