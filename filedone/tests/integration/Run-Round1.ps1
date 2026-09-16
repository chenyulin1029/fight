$ErrorActionPreference='Stop'

$runtime = (Resolve-Path 'filedone/out/FileDoneRuntime.exe' -ErrorAction SilentlyContinue)
if (!$runtime) { throw 'FileDoneRuntime.exe missing' }

$reports = 'filedone/out/reports'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$root = Join-Path $env:TEMP ("FileDone_Round1_" + $PID)
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

function Probe-VideoTitle([string]$ffprobe,[string]$path) {
    $value = & $ffprobe -v error -show_entries format_tags=title -of default=nw=1:nk=1 $path
    if ($LASTEXITCODE -ne 0) { throw 'video metadata probe failed' }
    return (($value -join '').Trim())
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

    Run-Case 'R1-01' {
        $input = Join-Path $root '中文 空格 原圖.png'
        Invoke-Checked $magick @('-size','1200x800','gradient:',$input)
        $before = Hash $input
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root '中文 空格 原圖_smaller.jpg'
        Require-File $output
        if ((Hash $input) -ne $before) { throw 'original changed' }
    }

    Run-Case 'R1-02' {
        $input = Join-Path $root '日本語_😀_alpha.webp'
        Invoke-Checked $magick @('-size','320x240','xc:none','-fill','red','-draw','rectangle 30,30 290,210',$input)
        $code = Invoke-FileDone 'compatible' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root '日本語_😀_alpha_compatible.png'
        Require-File $output
    }

    Run-Case 'R1-03' {
        $input = Join-Path $root 'fit strict.png'
        Invoke-Checked $magick @('-size','1800x1200','plasma:fractal',$input)
        [double]$target = 0.12
        $code = Invoke-FileDone 'fitunder' @($input) $target
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'fit strict_under.jpg'
        Require-File $output
        $limit = [math]::Floor($target * 1024 * 1024)
        if ((Get-Item -LiteralPath $output).Length -gt $limit) { throw 'output exceeds target' }
    }

    Run-Case 'R1-04' {
        $input = Join-Path $root 'metadata seeded.jpg'
        Invoke-Checked $magick @('-size','640x480','xc:orange','-set','comment','FileDoneSecret',$input)
        $seeded = (& $magick identify -quiet -format '%[comment]' $input) -join ''
        if ($LASTEXITCODE -ne 0 -or $seeded -notmatch 'FileDoneSecret') { throw 'fixture metadata missing' }
        $code = Invoke-FileDone 'safeshare' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'metadata seeded_safe.jpg'
        Require-File $output
        $after = (& $magick identify -quiet -format '%[comment]' $output) -join ''
        if ($LASTEXITCODE -ne 0) { throw 'output metadata probe failed' }
        if ($after -match 'FileDoneSecret') { throw 'metadata was not removed' }
    }

    Run-Case 'R1-05' {
        $input = Join-Path $root 'readonly source.png'
        Invoke-Checked $magick @('-size','900x700','gradient:',$input)
        $before = Hash $input
        $item = Get-Item -LiteralPath $input
        $item.IsReadOnly = $true
        try {
            $code = Invoke-FileDone 'smaller' @($input)
            if ($code -ne 0) { throw "exit=$code" }
            Require-File (Join-Path $root 'readonly source_smaller.jpg')
            if ((Hash $input) -ne $before) { throw 'read-only original changed' }
        }
        finally {
            (Get-Item -LiteralPath $input).IsReadOnly = $false
        }
    }

    Run-Case 'R1-06' {
        $input = Join-Path $root 'duplicate.png'
        Invoke-Checked $magick @('-size','800x600','gradient:',$input)
        $sentinel = Join-Path $root 'duplicate_smaller.jpg'
        [IO.File]::WriteAllText($sentinel,'SENTINEL',[Text.UTF8Encoding]::new($false))
        $sentinelHash = Hash $sentinel
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        if ((Hash $sentinel) -ne $sentinelHash) { throw 'existing output overwritten' }
        Require-File (Join-Path $root 'duplicate_smaller_2.jpg')
    }

    Run-Case 'R1-07' {
        $input = Join-Path $root 'corrupt.png'
        [IO.File]::WriteAllText($input,'not an image',[Text.UTF8Encoding]::new($false))
        $beforeFiles = @(Get-ChildItem -LiteralPath $root -File | Select-Object -ExpandProperty Name)
        $code = Invoke-FileDone 'smaller' @($input)
        if ($code -eq 0) { throw 'corrupt input reported success' }
        if (Test-Path -LiteralPath (Join-Path $root 'corrupt_smaller.jpg')) { throw 'fake success artifact created' }
        $afterFiles = @(Get-ChildItem -LiteralPath $root -File | Select-Object -ExpandProperty Name)
        $extras = @($afterFiles | Where-Object { $_ -notin $beforeFiles })
        if ($extras.Count -ne 0) { throw "unexpected artifact: $($extras -join ',')" }
    }

    Run-Case 'R1-08' {
        $a = Join-Path $root 'PDF_01_中文.png'
        $b = Join-Path $root 'PDF_02_日本語.png'
        $c = Join-Path $root 'PDF_03_😀.png'
        Invoke-Checked $magick @('-size','120x80','xc:red',$a)
        Invoke-Checked $magick @('-size','120x80','xc:green',$b)
        Invoke-Checked $magick @('-size','120x80','xc:blue',$c)
        $code = Invoke-FileDone 'makepdf' @($a,$b,$c)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'PDF_01_中文_document.pdf'
        Require-File $output
        $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($output))
        $pages = ([regex]::Matches($text,'/Type\s*/Page(?!s)')).Count
        if ($pages -ne 3) { throw "page count=$pages" }
    }

    Run-Case 'R1-09' {
        $input = Join-Path $root 'legacy video.avi'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=640x360:rate=30','-f','lavfi','-i','sine=frequency=1000:sample_rate=44100','-t','1','-c:v','mpeg4','-q:v','5','-c:a','pcm_s16le',$input)
        $code = Invoke-FileDone 'compatible' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'legacy video_compatible.mp4'
        Require-File $output
        if ((Probe-VideoCodec $ffprobe $output) -ne 'h264') { throw 'video codec is not h264' }
        if ((Probe-AudioCodec $ffprobe $output) -ne 'aac') { throw 'audio codec is not aac' }
    }

    Run-Case 'R1-10' {
        $input = Join-Path $root 'share video.mp4'
        Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=480x270:rate=24','-f','lavfi','-i','sine=frequency=700:sample_rate=44100','-t','1','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-metadata','title=FileDoneSecret',$input)
        if ((Probe-VideoTitle $ffprobe $input) -ne 'FileDoneSecret') { throw 'fixture title metadata missing' }
        $code = Invoke-FileDone 'safeshare' @($input)
        if ($code -ne 0) { throw "exit=$code" }
        $output = Join-Path $root 'share video_safe.mp4'
        Require-File $output
        if ((Probe-VideoTitle $ffprobe $output) -eq 'FileDoneSecret') { throw 'video metadata was not removed' }
    }
}
finally {
    Remove-Item Env:FILEDONE_TOOLS_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:FILEDONE_TEST_MODE -ErrorAction SilentlyContinue

    $passed = @($results | Where-Object Pass).Count
    $report = [pscustomobject]@{
        gate = 'ROUND1'
        total = 10
        passed = $passed
        status = $(if ($passed -eq 10) { 'PASS' } else { 'FAIL' })
        cases = $results
    }
    $jsonPath = Join-Path $reports 'round1.json'
    $htmlPath = Join-Path $reports 'round1.html'
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $rows = $results | Select-Object Id,Pass,Detail | ConvertTo-Html -Fragment
    @("<!doctype html><meta charset='utf-8'><title>FileDone Round 1</title><h1>Round 1: $passed/10</h1>",$rows) | Set-Content -LiteralPath $htmlPath -Encoding utf8

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if (@($results | Where-Object Pass).Count -ne 10) { throw "Round 1 failed: $(@($results | Where-Object Pass).Count)/10" }
Write-Host 'ROUND1_10_OF_10_PASS'
