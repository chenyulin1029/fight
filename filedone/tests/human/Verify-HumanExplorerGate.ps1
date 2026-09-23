param(
    [string]$GateFolder
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

if([string]::IsNullOrWhiteSpace($GateFolder)){
    $GateFolder=Join-Path $PSScriptRoot 'HUMAN_TEST_FILES'
}
$GateFolder=(Resolve-Path -LiteralPath $GateFolder -ErrorAction Stop).Path

$checks=[ordered]@{}
function Find-One([string]$Pattern,[string]$Label){
    $items=@(Get-ChildItem -LiteralPath $GateFolder -File -Filter $Pattern -ErrorAction SilentlyContinue)
    $items=@($items | Where-Object { $_.Length -gt 0 })
    $checks[$Label]=($items.Count -ge 1)
    if($items.Count -ge 1){ return $items[0].FullName }
    return $null
}

$compatible=Find-One '01_SINGLE_COMPATIBLE_compatible*' 'Make Compatible output'
$smaller=Find-One '02_SINGLE_SMALLER_smaller*' 'Make Smaller output'
$safe=Find-One '03_SAFE_SHARE_safe*' 'Safe to Share output'
$fit=Find-One '04_FIT_UNDER_under_1MB*.mp4' 'Fit Under output'
$pdf=Find-One '05_PDF_*_document*.pdf' 'Make PDF output'

if($fit){
    $fitBytes=(Get-Item -LiteralPath $fit).Length
    $checks['Fit Under <= 1 MiB']=($fitBytes -le 1MB)

    $installed=Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction SilentlyContinue | Select-Object -First 1
    if($installed){
        $ffprobe=Join-Path $installed.InstallLocation 'tools\ffprobe.exe'
        if(Test-Path -LiteralPath $ffprobe){
            $v=([string](& $ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $fit 2>$null | Select-Object -First 1)).Trim()
            $a=([string](& $ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $fit 2>$null | Select-Object -First 1)).Trim()
            $checks['Fit Under H.264']=($v -eq 'h264')
            $checks['Fit Under AAC']=($a -eq 'aac')
        }
    }
}

if($pdf){ $checks['Make PDF non-empty']=((Get-Item -LiteralPath $pdf).Length -gt 0) }

$allPass=($checks.Values -notcontains $false)
$report=[ordered]@{
    timestamp=(Get-Date).ToString('o')
    status=if($allPass){'PASS'}else{'FAIL'}
    gate='P1.8B_HUMAN_EXPLORER_GATE_MACHINE_OUTPUT_CHECK'
    folder=$GateFolder
    checks=$checks
}
$reportPath=Join-Path $GateFolder '_MACHINE_RESULT.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8

$checks.GetEnumerator() | ForEach-Object {
    Write-Host ("{0}={1}" -f $_.Key, $(if($_.Value){'PASS'}else{'FAIL'}))
}
if($allPass){
    Write-Host 'FILEDONE_HUMAN_GATE_MACHINE_OUTPUTS_PASS'
    exit 0
}
Write-Host 'FILEDONE_HUMAN_GATE_MACHINE_OUTPUTS_FAIL'
exit 1
