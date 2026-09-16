$ErrorActionPreference='Stop'

$root = Join-Path $env:TEMP ("FileDone_ToolProbe_" + $PID)
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null

try {
    $ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
    $ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
    Write-Host "SYSTEM_FFMPEG=$ffmpeg"
    Write-Host "SYSTEM_FFPROBE=$ffprobe"
    Write-Host "SYSTEM_FFMPEG_BYTES=$((Get-Item -LiteralPath $ffmpeg).Length)"
    Write-Host "SYSTEM_FFPROBE_BYTES=$((Get-Item -LiteralPath $ffprobe).Length)"

    $copiedFfmpeg = Join-Path $root 'ffmpeg.exe'
    $copiedFfprobe = Join-Path $root 'ffprobe.exe'
    Copy-Item -LiteralPath $ffmpeg -Destination $copiedFfmpeg -Force
    Copy-Item -LiteralPath $ffprobe -Destination $copiedFfprobe -Force

    $ffmpegText = & $copiedFfmpeg -version 2>&1
    $ffmpegExit = $LASTEXITCODE
    Write-Host "RELOCATED_FFMPEG_EXIT=$ffmpegExit"
    Write-Host "RELOCATED_FFMPEG_FIRST=$($ffmpegText | Select-Object -First 1)"

    $ffprobeText = & $copiedFfprobe -version 2>&1
    $ffprobeExit = $LASTEXITCODE
    Write-Host "RELOCATED_FFPROBE_EXIT=$ffprobeExit"
    Write-Host "RELOCATED_FFPROBE_FIRST=$($ffprobeText | Select-Object -First 1)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
