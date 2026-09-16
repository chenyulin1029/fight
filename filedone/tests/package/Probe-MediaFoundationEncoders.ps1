$ErrorActionPreference='Stop'

function Require-Command([string]$name) {
    $cmd=Get-Command $name -ErrorAction SilentlyContinue
    if(!$cmd){ throw "$name missing" }
    return $cmd.Source
}

function Invoke-Checked([string]$exe,[string[]]$arguments) {
    $text=@(& $exe @arguments 2>&1)
    if($LASTEXITCODE -ne 0){
        throw "$exe failed exit=$LASTEXITCODE`n$($text -join "`n")"
    }
    return $text
}

function Probe-Codec([string]$ffprobe,[string]$path,[string]$selector) {
    $value=(& $ffprobe -v error -select_streams $selector -show_entries stream=codec_name -of default=nw=1:nk=1 $path 2>&1 | Select-Object -First 1)
    if($LASTEXITCODE -ne 0){ throw "ffprobe failed for $path" }
    return [string]$value
}

function Probe-Bitrate([string]$ffprobe,[string]$path,[string]$selector) {
    $value=(& $ffprobe -v error -select_streams $selector -show_entries stream=bit_rate -of default=nw=1:nk=1 $path 2>&1 | Select-Object -First 1)
    if($LASTEXITCODE -ne 0){ throw "ffprobe bitrate failed for $path" }
    return [string]$value
}

$root=Join-Path $env:TEMP ("FileDone_MFCodecProof_" + $PID)
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null

try {
    $ffmpeg=Require-Command 'ffmpeg.exe'
    $ffprobe=Require-Command 'ffprobe.exe'

    $buildConf=(Invoke-Checked $ffmpeg @('-hide_banner','-buildconf')) -join "`n"
    if($buildConf -notmatch 'enable-mediafoundation'){
        throw 'test FFmpeg does not expose Media Foundation support'
    }

    $encoders=(Invoke-Checked $ffmpeg @('-hide_banner','-encoders')) -join "`n"
    foreach($encoder in @('h264_mf','mp3_mf')){
        if($encoders -notmatch ('\b' + [regex]::Escape($encoder) + '\b')){
            throw "required Media Foundation encoder missing: $encoder"
        }
    }

    $mp3=Join-Path $root 'mf-audio.mp3'
    Invoke-Checked $ffmpeg @(
        '-hide_banner','-loglevel','error','-y',
        '-f','lavfi','-i','sine=frequency=523:sample_rate=44100:duration=2',
        '-c:a','mp3_mf','-b:a','128k',$mp3
    ) | Out-Null
    if((Probe-Codec $ffprobe $mp3 'a:0') -ne 'mp3'){ throw 'mp3_mf did not create MP3' }
    Write-Host "MF_MP3_BYTES=$((Get-Item -LiteralPath $mp3).Length)"
    Write-Host "MF_MP3_REPORTED_BPS=$(Probe-Bitrate $ffprobe $mp3 'a:0')"

    $source=Join-Path $root 'source.mkv'
    Invoke-Checked $ffmpeg @(
        '-hide_banner','-loglevel','error','-y',
        '-f','lavfi','-i','testsrc2=size=1280x720:rate=30:duration=4',
        '-f','lavfi','-i','sine=frequency=880:sample_rate=48000:duration=4',
        '-c:v','ffv1','-level','3','-c:a','pcm_s16le','-shortest',$source
    ) | Out-Null

    $compatible=Join-Path $root 'compatible.mp4'
    Invoke-Checked $ffmpeg @(
        '-hide_banner','-loglevel','error','-y','-i',$source,
        '-map','0:v:0','-map','0:a?',
        '-vf','format=nv12',
        '-c:v','h264_mf','-hw_encoding','0','-rate_control','cbr','-b:v','2500k',
        '-pix_fmt','nv12',
        '-c:a','aac','-b:a','160k','-movflags','+faststart',$compatible
    ) | Out-Null
    if((Probe-Codec $ffprobe $compatible 'v:0') -ne 'h264'){ throw 'h264_mf did not create H.264' }
    if((Probe-Codec $ffprobe $compatible 'a:0') -ne 'aac'){ throw 'native AAC path failed' }
    Write-Host "MF_H264_2500K_BYTES=$((Get-Item -LiteralPath $compatible).Length)"
    Write-Host "MF_H264_2500K_REPORTED_BPS=$(Probe-Bitrate $ffprobe $compatible 'v:0')"

    # Single-variable hypothesis test: Global VBR instead of CBR.
    [double]$targetMb=0.55
    $targetBytes=[uint64][math]::Floor($targetMb*1024*1024)
    [double]$duration=4.0
    [int64]$audioBps=96000
    [int64]$minimumVideoBps=140000
    [int64]$videoBps=[math]::Floor(($targetBytes*8*0.94/$duration)-$audioBps)
    if($videoBps -lt $minimumVideoBps){ throw 'proof target too small' }
    Write-Host "MF_FIT_MODE=g_vbr"
    Write-Host "MF_FIT_TARGET_BYTES=$targetBytes"
    Write-Host "MF_FIT_INITIAL_VIDEO_BPS=$videoBps"

    $fit=Join-Path $root 'fit-under.mp4'
    $attempt=0
    $fitOk=$false
    while($videoBps -ge $minimumVideoBps -and $attempt -lt 8){
        $attempt++
        $requestedBps=$videoBps
        Remove-Item -LiteralPath $fit -Force -ErrorAction SilentlyContinue
        Invoke-Checked $ffmpeg @(
            '-hide_banner','-loglevel','error','-y','-i',$source,
            '-map','0:v:0','-map','0:a?',
            '-vf','scale=1920:-2:force_original_aspect_ratio=decrease,format=nv12',
            '-c:v','h264_mf','-hw_encoding','0','-rate_control','g_vbr','-b:v',([string]$requestedBps),
            '-pix_fmt','nv12',
            '-c:a','aac','-b:a','96k','-movflags','+faststart',$fit
        ) | Out-Null
        if(!(Test-Path -LiteralPath $fit -PathType Leaf)){ throw 'Fit Under proof output missing' }
        $actualBytes=(Get-Item -LiteralPath $fit).Length
        $reportedVideoBps=Probe-Bitrate $ffprobe $fit 'v:0'
        $reportedAudioBps=Probe-Bitrate $ffprobe $fit 'a:0'
        Write-Host "MF_FIT_ATTEMPT=$attempt REQUESTED_VIDEO_BPS=$requestedBps ACTUAL_BYTES=$actualBytes REPORTED_VIDEO_BPS=$reportedVideoBps REPORTED_AUDIO_BPS=$reportedAudioBps"
        if($actualBytes -le $targetBytes){ $fitOk=$true; break }
        $videoBps=[math]::Floor($videoBps*0.85)
    }
    if(!$fitOk){ throw "Media Foundation Fit Under proof exceeded target after $attempt attempts" }
    if((Probe-Codec $ffprobe $fit 'v:0') -ne 'h264'){ throw 'Fit Under output is not H.264' }
    if((Probe-Codec $ffprobe $fit 'a:0') -ne 'aac'){ throw 'Fit Under output is not AAC' }

    [ordered]@{
        status='PASS'
        mediaFoundationBuildFlag=$true
        h264Encoder='h264_mf'
        mp3Encoder='mp3_mf'
        h264SoftwareEncoding=$true
        fitUnderRateControl='g_vbr'
        fitUnderTargetMb=$targetMb
        fitUnderBytes=(Get-Item -LiteralPath $fit).Length
        fitUnderAttempts=$attempt
        fitUnderVideoBps=$videoBps
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'mf-codec-proof.json') -Encoding utf8

    Write-Host 'MEDIA_FOUNDATION_CODEC_PROOF_PASS'
    Get-Content -LiteralPath (Join-Path $root 'mf-codec-proof.json') -Raw
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
