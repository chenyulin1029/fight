$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$installed=Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction SilentlyContinue | Select-Object -First 1
if($installed){ $installed | Remove-AppxPackage -ErrorAction Stop }

$deadline=[DateTime]::UtcNow.AddSeconds(30)
while([DateTime]::UtcNow -lt $deadline -and (Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction SilentlyContinue)){
    Start-Sleep -Milliseconds 500
}
if(Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction SilentlyContinue){
    throw 'FileDone.QAUnsigned remained registered after uninstall'
}
Write-Host 'FILEDONE_HUMAN_GATE_CLEANUP_PASS'
