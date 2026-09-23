param(
    [string]$CertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Test.cer')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    throw 'Administrator rights are required only to trust the FileDone QA test certificate.'
}

$authority=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SIGNED_GATE_AUTHORITY.json') -Raw | ConvertFrom-Json
$CertificatePath=(Resolve-Path -LiteralPath $CertificatePath -ErrorAction Stop).Path
$certFileHash=(Get-FileHash -LiteralPath $CertificatePath -Algorithm SHA256).Hash.ToUpperInvariant()
if($certFileHash -ne ([string]$authority.certificateFileSha256).ToUpperInvariant()){ throw "certificate file hash mismatch expected=$($authority.certificateFileSha256) actual=$certFileHash" }
$cert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
$thumb=$cert.Thumbprint.ToUpperInvariant()
if($thumb -ne ([string]$authority.certificateThumbprint).ToUpperInvariant()){ throw "certificate thumbprint mismatch expected=$($authority.certificateThumbprint) actual=$thumb" }

& certutil.exe -addStore -f TrustedPeople $CertificatePath | Out-Host
if($LASTEXITCODE -ne 0){ throw "certutil TrustedPeople import failed: $LASTEXITCODE" }

$store=[System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
    $match=$store.Certificates | Where-Object { $_.Thumbprint.ToUpperInvariant() -eq $thumb } | Select-Object -First 1
    if(!$match){ throw 'QA signing certificate was not found in LocalMachine TrustedPeople after certutil import' }
} finally {
    $store.Close()
}

Write-Host "FILEDONE_QA_CERT_TRUST_PASS THUMBPRINT=$thumb"