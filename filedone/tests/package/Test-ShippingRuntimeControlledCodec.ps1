$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

param(
    [Parameter(Mandatory=$true)][string]$RuntimePath,
    [Parameter(Mandatory=$true)][string]$ToolsDir,
    [string]$EvidencePath='artifacts/evidence/shipping-runtime-controlled-codec.json'
)

function Resolve-RequiredFile([string]$Path,[string]$Label) {
    $resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if(!(Test-Path -LiteralPath $resolved -PathType Leaf)){ throw "$Label missing: $resolved" }
    return $resolved
}

function Probe-Codec([string]$Ffprobe,[string]$Path,[string]$Selector) {
    $value=(& $Ffprobe -v error -select_streams $Selector -show_entries stream=codec_name -of default=nw=1:nk=1 $Path 2>&1 | Select-Object -First 1)
    if($LASTEXITCODE -ne 0){ throw "ffprobe failed for $Path selector=$Selector" }
    return ([string]$value).Trim()
}

function Invoke-Checked([string]$Exe,[string[]]$Arguments,[string]$Label) {
    $output=@(& $Exe @Arguments 2>&1)
    if($LASTEXITCODE -ne 0){
        throw "$Label failed exit=$LASTEXITCODE`n$($output -join "`n")"
    }
    return $output
}

function Write-Request([string]$Path,[string]$Action,[string]$InputPath) {
    $text="$Action`r`n$InputPath`r`n"
    $payload=[Text.Encoding]::Unicode.GetBytes($text)
    $bom=[byte[]](0xFF,0xFE)
    $bytes=New-Object byte[] ($bom.Length+$payload.Length)
    [Array]::Copy($bom,0,$bytes,0,$bom.Length)
    [Array]::Copy($payload,0,$bytes,$bom.Length,$payload.Length)
    [IO.File]::WriteAllBytes($Path,$bytes)
}

function Invoke-FileDoneAction(
    [string]$Runtime,
    [string]$Action,
    [string]$InputPath,
    [string]$RequestPath,
    [Nullable[double]]$TargetMb=$null) {

    Write-Request -Path $RequestPath -Action $Action -InputPath $InputPath
    if($null -ne $TargetMb) {
        & $Runtime $RequestPath '--target-mb' ([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',[double]$TargetMb))
    } else {
        & $Runtime $RequestPath
    }
    if($LASTEXITCODE -ne 0){ throw "FileDoneRuntime action=$Action failed exit=$LASTEXITCODE" }
    if(Test-Path -LiteralPath $RequestPath){ throw "runtime did not clean request file: $RequestPath" }
}

$runtime=Resolve-RequiredFile $RuntimePath 'FileDoneRuntime'
$tools=(Resolve-Path -LiteralPath $ToolsDir -ErrorAction Stop).Path
$ffmpeg=Resolve-RequiredFile (Join-Path $tools 'ffmpeg.exe') 'controlled ffmpeg'
$ffprobe=Resolve-RequiredFile (Join-Path $tools 'ffprobe.exe') 'controlled ffprobe'
$magick=Resolve-RequiredFile (Join-Path $tools 'magick.exe') 'shipping magick'

$encoders=(@(& $ffmpeg -hide_banner -encoders 2>&1)) -join "`n"
foreach($required in @('h264_mf','mp3_mf')) {
    if($encoders -notmatch ('\b'+[regex]::Escape($required)+'\b')) {
        throw "shipping toolchain missing required encoder: $required"
    }
}
if($encoders -match '\blibx264\b'){ throw 'shipping codec gate requires the non-GPL controlled FFmpeg, but libx264 is present' }
if($encoders -match '\blibmp3lame\b'){ throw 'shipping codec gate requires the non-GPL controlled FFmpeg, but libmp3lame is present' }

$oldTools=$env:FILEDONE_TOOLS_DIR
$oldTestMode=$env:FILEDONE_TEST_MODE
$env:FILEDONE_TOOLS_DIR=$tools
$env:FILEDONE_TEST_MODE='1'

$root=Join-Path $env:TEMP ("FileDone Shipping Codec 測試 " + $PID)
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null

try {
    $source=Join-Path $root '來源 video.mkv'
    Invoke-Checked $ffmpeg @(
        '-hide_banner','-loglevel','error','-y',
        '-f','lavfi','-i','testsrc2=size=1280x720:rate=30:duration=4',
        '-f','lavfi','-i','sine=frequency=880:sample_rate=48000:duration=4',
        '-c:v','ffv1','-level','3',
        '-c:a','pcm_s16le','-shortest',$source
    ) 'create video fixture' | Out-Null

    $audio=Join-Path $root '來源 audio.wav'
    Invoke-Checked $ffmpeg @(
        '-hide_banner','-loglevel','error','-y',
        '-f','lavfi','-i','sine=frequency=523:sample_rate=44100:duration=2',
        '-c:a','pcm_s16le',$audio
    ) 'create audio fixture' | Out-Null

    $request=Join-Path $root 'request.fdreq'

    Invoke-FileDoneAction -Runtime $runtime -Action 'compatible' -InputPath $source -RequestPath $request
    $compatible=Join-Path $root '來源 video_compatible.mp4'
    if(!(Test-Path -LiteralPath $compatible -PathType Leaf)){ throw 'Make Compatible output missing' }
    if((Probe-Codec $ffprobe $compatible 'v:0') -ne 'h264'){ throw 'Make Compatible did not produce H.264' }
    if((Probe-Codec $ffprobe $compatible 'a:0') -ne 'aac'){ throw 'Make Compatible did not produce AAC' }

    Invoke-FileDoneAction -Runtime $runtime -Action 'smaller' -InputPath $source -RequestPath $request
    $smaller=Join-Path $root '來源 video_smaller.mp4'
    if(!(Test-Path -LiteralPath $smaller -PathType Leaf)){ throw 'Make Smaller video output missing' }
    if((Probe-Codec $ffprobe $smaller 'v:0') -ne 'h264'){ throw 'Make Smaller did not produce H.264' }
    if((Probe-Codec $ffprobe $smaller 'a:0') -ne 'aac'){ throw 'Make Smaller did not produce AAC' }

    Invoke-FileDoneAction -Runtime $runtime -Action 'compatible' -InputPath $audio -RequestPath $request
    $audioCompatible=Join-Path $root '來源 audio_compatible.mp3'
    if(!(Test-Path -LiteralPath $audioCompatible -PathType Leaf)){ throw 'audio Make Compatible output missing' }
    if((Probe-Codec $ffprobe $audioCompatible 'a:0') -ne 'mp3'){ throw 'audio Make Compatible did not produce MP3' }

    [double]$targetMb=0.55
    Invoke-FileDoneAction -Runtime $runtime -Action 'fitunder' -InputPath $source -RequestPath $request -TargetMb $targetMb
    $fit=Join-Path $root '來源 video_under_0.55MB.mp4'
    if(!(Test-Path -LiteralPath $fit -PathType Leaf)){ throw 'Fit Under output missing' }
    $targetBytes=[uint64][Math]::Floor($targetMb*1024*1024)
    $fitBytes=(Get-Item -LiteralPath $fit).Length
    if($fitBytes -gt $targetBytes){ throw "Fit Under exceeded target: bytes=$fitBytes target=$targetBytes" }
    if((Probe-Codec $ffprobe $fit 'v:0') -ne 'h264'){ throw 'Fit Under did not produce H.264' }
    if((Probe-Codec $ffprobe $fit 'a:0') -ne 'aac'){ throw 'Fit Under did not produce AAC' }

    $evidence=[ordered]@{
        status='PASS'
        gate='P1.8B_SHIPPING_RUNTIME_CONTROLLED_CODEC'
        runtimeSha256=(Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash.ToUpperInvariant()
        ffmpegSha256=(Get-FileHash -LiteralPath $ffmpeg -Algorithm SHA256).Hash.ToUpperInvariant()
        ffprobeSha256=(Get-FileHash -LiteralPath $ffprobe -Algorithm SHA256).Hash.ToUpperInvariant()
        magickSha256=(Get-FileHash -LiteralPath $magick -Algorithm SHA256).Hash.ToUpperInvariant()
        makeCompatibleVideo=[ordered]@{codec='h264';audio='aac';bytes=(Get-Item -LiteralPath $compatible).Length}
        makeSmallerVideo=[ordered]@{codec='h264';audio='aac';bytes=(Get-Item -LiteralPath $smaller).Length}
        makeCompatibleAudio=[ordered]@{codec='mp3';bytes=(Get-Item -LiteralPath $audioCompatible).Length}
        fitUnder=[ordered]@{targetMb=$targetMb;targetBytes=$targetBytes;actualBytes=$fitBytes;videoCodec='h264';audioCodec='aac'}
    }

    $parent=Split-Path -Parent $EvidencePath
    if($parent){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

    Write-Host "FILEDONE_SHIPPING_RUNTIME_CONTROLLED_CODEC_PASS FIT_BYTES=$fitBytes TARGET_BYTES=$targetBytes"
    $evidence | ConvertTo-Json -Depth 8 | Write-Host
}
finally {
    if($null -eq $oldTools){ Remove-Item Env:FILEDONE_TOOLS_DIR -ErrorAction SilentlyContinue } else { $env:FILEDONE_TOOLS_DIR=$oldTools }
    if($null -eq $oldTestMode){ Remove-Item Env:FILEDONE_TEST_MODE -ErrorAction SilentlyContinue } else { $env:FILEDONE_TEST_MODE=$oldTestMode }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
