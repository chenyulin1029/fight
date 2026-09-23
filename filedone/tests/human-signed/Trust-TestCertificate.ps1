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

$authorityPath=Join-Path $PSScriptRoot 'SIGNED_GATE_AUTHORITY.json'
$authority=Get-Content -LiteralPath $authorityPath -Raw | ConvertFrom-Json
$CertificatePath=(Resolve-Path -LiteralPath $CertificatePath -ErrorAction Stop).Path
$certFileHash=(Get-FileHash -LiteralPath $CertificatePath -Algorithm SHA256).Hash.ToUpperInvariant()
if($certFileHash -ne ([string]$authority.certificateFileSha256).ToUpperInvariant()){ throw "certificate file hash mismatch expected=$($authority.certificateFileSha256) actual=$certFileHash" }
$cert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
if($cert.Thumbprint.ToUpperInvariant() -ne ([string]$authority.certificateThumbprint).ToUpperInvariant()){ throw "certificate thumbprint mismatch expected=$($authority.certificateThumbprint) actual=$($cert.Thumbprint)" }
$existing=Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint } | Select-Object -First 1
if(!$existing){ Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null }
$verify=Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint } | Select-Object -First 1
if(!$verify){ throw 'QA signing certificate was not found in LocalMachine TrustedPeople after import' }
Write-Host "FILEDONE_QA_CERT_TRUST_PASS THUMBPRINT=$($cert.Thumbprint)"