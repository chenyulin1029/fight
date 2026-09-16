$ErrorActionPreference='Stop'

$runtime = (Resolve-Path 'filedone/out/FileDoneRuntime.exe' -ErrorAction SilentlyContinue)
if (!$runtime) { throw 'FileDoneRuntime.exe missing' }

$reports = 'filedone/out/reports'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$root = Join-Path $env:TEMP ("FileDone_Round2_" + $PID)
$tools = Join-Path $root 'tools'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$tools | Out-Null
$results = [System.Collections.Generic.List[object]]::new()

function Require-Command([string]$name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (!$command) { throw "$name missing" }
    return $command.Source
}

function Resolve-RealMediaTool([string]$name) {
    $source = Require-Command $name
    $chocoBin = if ($env:ChocolateyInstall) { Join-Path $env:ChocolateyInstall 'bin' } else { $null }
    if ($chocoBin -and $source.StartsWith($chocoBin,[StringComparison]::OrdinalIgnoreCase)) {
        $ffRoot = Join-Path $env:ChocolateyInstall 'lib\ffmpeg\tools'
        $real = Get-ChildItem -LiteralPath $ffRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 1
        if (!$real) { throw "real $name missing under Chocolatey ffmpeg tools" }
        return $real.FullName
    }
    return $source
}

function Invoke-Checked([string]$exe, [string[]]$toolArguments) {
    & $exe @toolArguments
    if ($LASTEXITCODE -ne 0) { throw "$exe fixture command failed: $LASTEXITCODE" }
}

function Write-Request([string]$path, [string]$action, [string[]]$paths) {
    $encoding = [System.Text.UnicodeEncoding]::new($false,$true,$true)
    [System.IO.File]::WriteAllLines($path,@($action) + $paths,$encoding)
}

function Start-FileDone([string]$action, [string[]]$paths, [object]$targetMb = $null) {
    $request = Join-Path $root (([Guid]::NewGuid().ToString('N')) + '.fdreq')
    Write-Request $request $action $paths
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $runtime.Path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $null = $start.ArgumentList.Add($request)
    if ($null -ne $targetMb) {
        $null = $start.ArgumentList.Add('--target-mb')
        $targetValue = [Convert]::ToDouble($targetMb,[Globalization.CultureInfo]::InvariantCulture)
        $null = $start.ArgumentList.Add($targetValue.ToString([Globalization.CultureInfo]::InvariantCulture))
    }
    $process = [System.Diagnostics.Process]::Start($start)
    if (!$process) { throw 'FileDoneRuntime.exe failed to start' }
    return [pscustomobject]@{ Process=$process; Request=$request }
}

function Invoke-FileDone([string]$action, [string[]]$paths, [object]$targetMb = $null) {
    $run = Start-FileDone $action $paths $targetMb
    $run.Process.WaitForExit()
    return $run.Process.ExitCode
}

function Require-File([string]$path) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "expected file missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "expected file empty: $path" }
}

function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

function Probe-VideoCodec([string]$ffprobe,[string]$path) {
    $value = & $ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $path
    if ($LASTEXITCODE -ne 0) { throw 'video codec probe failed' }
    return (($value -join '').Trim())
}

function Probe-AudioCodec([string]$ffprobe,[string]$path) {
    $value = & $ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $path
    if ($LASTEXITCODE -ne 0) { throw 'audio codec probe failed' }
    return (($value -join '').Trim())
}

function Probe-VideoWidth([string]$ffprobe,[string]$path) {
    $value = & $ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $path
    if ($LASTEXITCODE -ne 0) { throw 'video width probe failed' }
    return [int](($value -join '').Trim())
}

function Run-Case([string]$id, [scriptblock]$body) {
    try {
        & $body
        $results.Add([pscustomobject]@{ Id=$id; Pass=$true; Detail='PASS' })
        Write-Host "$id PASS"
    }
    catch {
        $detail = $_.Exception.Message
        $results.Add([pscustomobject]@{ Id=$id; Pass=$false; Detail=$detail })
        Write-Host "$id FAIL: $detail"
    }
}

try {
    $magick = Require-Command 'magick.exe'
    $ffmpeg = Resolve-RealMediaTool 'ffmpeg.exe'
    $ffprobe = Resolve-RealMediaTool 'ffprobe.exe'
    $magickDir = Split-Path -Parent $magick
    Copy-Item -Path (Join-Path $magickDir '*') -Destination $tools -Recurse -Force
    Copy-Item -LiteralPath $ffmpeg -Destination (Join-Path $tools 'ffmpeg.exe') -Force
    Copy-Item -LiteralPath $ffprobe -Destination (Join-Path $tools 'ffprobe.exe') -Force
    $env:FILEDONE_TOOLS_DIR = $tools
    $env:FILEDONE_TEST_MODE = '1'

    Run-Case 'R2-01' {
        $longDir = Join-Path $root '長路徑 起點'
        while ((Join-Path $longDir 'Unicode 空格 圖像.png').Length -lt 235) {
            $longDir = Join-Path $longDir '段落_1234567890_空格'
        }
        $input = Join-Path $longDir 'Unicode 空格 圖像.png'
        if ($input.Length -ge 260) { throw "fixture path too long: $($input.Length)" }
        New-Item -ItemType Directory -Force -Path $longDir | Out-Null
        Invoke-Checked $magick @('-size','900x600','gradient:',$input)
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        Require-File (Join-Path $longDir 'Unicode 空格 圖像_smaller.jpg')
    }

    Run-Case 'R2-02' {
        $input = Join-Path $root 'alpha source.tiff'
        Invoke-Checked $magick @('-size','500x350','xc:none','-fill','blue','-draw','rectangle 40,40 460,310',$input)
        $code = Invoke-FileDone 'compatible' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        Require-File (Join-Path $root 'alpha source_compatible.png')
    }

    Run-Case 'R2-03' {
        $input = Join-Path $root 'modern image.avif'
        Invoke-Checked $magick @('-size','640x480','gradient:',$input)
        $code = Invoke-FileDone 'compatible' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'modern image_compatible.jpg'
        Require-File $output
        $format = (& $magick identify -quiet -format '%m' $output) -join ''
        if ($LASTEXITCODE -ne 0 -or $format.Trim().ToUpperInvariant() -ne 'JPEG') { throw "unexpected output format: $format" }
    }

    Run-Case 'R2-04' {
        $input = Join-Path $root 'audio source.flac'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','sine=frequency=440:sample_rate=44100','-t','1','-c:a','flac',$input)
        $code = Invoke-FileDone 'compatible' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'audio source_compatible.mp3'
        Require-File $output
        if ((Probe-AudioCodec $ffprobe $output) -ne 'mp3') { throw 'compatible audio codec is not mp3' }
    }

    Run-Case 'R2-05' {
        $input = Join-Path $root 'wave source.wav'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','sine=frequency=550:sample_rate=44100','-t','1','-c:a','pcm_s16le',$input)
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'wave source_smaller.mp3'
        Require-File $output
        if ((Probe-AudioCodec $ffprobe $output) -ne 'mp3') { throw 'smaller audio codec is not mp3' }
    }

    Run-Case 'R2-06' {
        $input = Join-Path $root 'large video.mp4'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=2000x1000:rate=12','-f','lavfi','-i','sine=frequency=620:sample_rate=44100','-t','1','-c:v','mpeg4','-q:v','5','-c:a','aac',$input)
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'large video_smaller.mp4'
        Require-File $output
        if ((Probe-VideoCodec $ffprobe $output) -ne 'h264') { throw 'smaller video codec is not h264' }
        if ((Probe-AudioCodec $ffprobe $output) -ne 'aac') { throw 'smaller audio codec is not aac' }
        if ((Probe-VideoWidth $ffprobe $output) -gt 1920) { throw 'smaller video width exceeds 1920' }
    }

    Run-Case 'R2-07' {
        $input = Join-Path $root 'fit video.mp4'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=1280x720:rate=24','-f','lavfi','-i','sine=frequency=880:sample_rate=44100','-t','2','-c:v','mpeg4','-q:v','4','-c:a','aac',$input)
        [double]$target = 0.30
        $code = Invoke-FileDone 'fitunder' @($input) $target
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'fit video_under.mp4'
        Require-File $output
        $limit = [math]::Floor($target * 1024 * 1024)
        if ((Get-Item -LiteralPath $output).Length -gt $limit) { throw 'fit-under video exceeds target' }
    }

    Run-Case 'R2-08' {
        $input = Join-Path $root 'already compatible.mp4'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=640x360:rate=24','-f','lavfi','-i','sine=frequency=900:sample_rate=44100','-t','1','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac',$input)
        $before = Hash $input
        $code = Invoke-FileDone 'compatible' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        if ((Hash $input) -ne $before) { throw 'NOOP source changed' }
        if (Test-Path -LiteralPath (Join-Path $root 'already compatible_compatible.mp4')) { throw 'NOOP created an output' }
    }

    Run-Case 'R2-09' {
        $input = Join-Path $root 'concurrent.png'
        Invoke-Checked $magick @('-size','1600x1000','plasma:fractal',$input)
        $before = Hash $input
        $run1 = Start-FileDone 'smaller' @($input)
        $run2 = Start-FileDone 'smaller' @($input)
        $run1.Process.WaitForExit()
        $run2.Process.WaitForExit()
        if ($run1.Process.ExitCode -ne 0 -or $run2.Process.ExitCode -ne 0) {
            throw "concurrent exits=$($run1.Process.ExitCode),$($run2.Process.ExitCode)"
        }
        Require-File (Join-Path $root 'concurrent_smaller.jpg')
        Require-File (Join-Path $root 'concurrent_smaller_2.jpg')
        if ((Hash $input) -ne $before) { throw 'concurrent source changed' }
    }

    Run-Case 'R2-10' {
        $input = Join-Path $root 'unsupported.txt'
        [IO.File]::WriteAllText($input,'unsupported',[Text.UTF8Encoding]::new($false))
        $beforeFiles = @(Get-ChildItem -LiteralPath $root -File | Select-Object -ExpandProperty Name)
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -eq 0) { throw 'unsupported input reported success' }
        $afterFiles = @(Get-ChildItem -LiteralPath $root -File | Select-Object -ExpandProperty Name)
        $extras = @($afterFiles | Where-Object { $_ -notin $beforeFiles })
        if ($extras.Count -ne 0) { throw "unexpected artifact: $($extras -join ',')" }
    }
}
finally {
    Remove-Item Env:FILEDONE_TOOLS_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:FILEDONE_TEST_MODE -ErrorAction SilentlyContinue

    $passed = @($results | Where-Object Pass).Count
    $report = [pscustomobject]@{
        gate = 'ROUND2'
        total = 10
        passed = $passed
        status = $(if ($passed -eq 10) { 'PASS' } else { 'FAIL' })
        cases = $results
    }
    $jsonPath = Join-Path $reports 'round2.json'
    $htmlPath = Join-Path $reports 'round2.html'
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $rows = $results | Select-Object Id,Pass,Detail | ConvertTo-Html -Fragment
    @("<!doctype html><meta charset='utf-8'><title>FileDone Round 2</title><h1>Round 2: $passed/10</h1>",$rows) | Set-Content -LiteralPath $htmlPath -Encoding utf8

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if (@($results | Where-Object Pass).Count -ne 10) { throw "Round 2 failed: $(@($results | Where-Object Pass).Count)/10" }
Write-Host 'ROUND2_10_OF_10_PASS'
