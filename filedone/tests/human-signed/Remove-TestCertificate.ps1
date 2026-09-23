param(
    [string]$CertificatePath = (Join-Path $PSScriptRoot 'FileDone-QA-Test.cer')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Administrator rights are required to remove the FileDone QA test certificate.' }
$CertificatePath=(Resolve-Path -LiteralPath $CertificatePath -ErrorAction Stop).Path
$cert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
$matches=@(Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })
foreach($m in $matches){ Remove-Item -LiteralPath $m.PSPath -Force }
$left=Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint } | Select-Object -First 1
if($left){ throw 'QA signing certificate remained in LocalMachine TrustedPeople after cleanup' }
Write-Host "FILEDONE_QA_CERT_CLEANUP_PASS THUMBPRINT=$($cert.Thumbprint)"