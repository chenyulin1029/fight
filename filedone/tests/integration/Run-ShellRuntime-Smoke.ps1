$ErrorActionPreference='Stop'

$sourcePath = 'filedone/src/FileDoneShell.cpp'
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
if ($source -match 'FileDoneBridge\.exe') { throw 'Shell still targets FileDoneBridge.exe' }
if ($source -notmatch 'FileDoneRuntime\.exe') { throw 'Shell does not target FileDoneRuntime.exe' }

$dll = (Resolve-Path 'filedone/out/FileDoneShellNative.dll' -ErrorAction SilentlyContinue)
$runtime = (Resolve-Path 'filedone/out/FileDoneRuntime.exe' -ErrorAction SilentlyContinue)
$harness = (Resolve-Path 'filedone/out/shell_runtime_smoke.exe' -ErrorAction SilentlyContinue)
if (!$dll) { throw 'FileDoneShellNative.dll missing' }
if (!$runtime) { throw 'FileDoneRuntime.exe missing' }
if (!$harness) { throw 'shell_runtime_smoke.exe missing' }
if (Test-Path -LiteralPath 'filedone/out/FileDoneBridge.exe') { throw 'FileDoneBridge.exe must not be built' }

$exports = (& dumpbin.exe /exports $dll.Path) -join "`n"
if ($exports -notmatch '(?m)\bDllGetClassObject\b') { throw 'DllGetClassObject export missing' }
if ($exports -notmatch '(?m)\bDllCanUnloadNow\b') { throw 'DllCanUnloadNow export missing' }
$headers = (& dumpbin.exe /headers $dll.Path) -join "`n"
if ($headers -notmatch 'machine \(x64\)') { throw 'Shell DLL is not x64' }
$runtimeHeaders = (& dumpbin.exe /headers $runtime.Path) -join "`n"
if ($runtimeHeaders -notmatch 'machine \(x64\)') { throw 'Runtime EXE is not x64' }

function Require-Command([string]$name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (!$command) { throw "$name missing" }
    return $command.Source
}

function Invoke-Checked([string]$exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe command failed: $LASTEXITCODE" }
}

$root = Join-Path $env:TEMP ("FileDone_ShellRuntime_" + $PID)
$tools = Join-Path $root 'tools'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$tools | Out-Null

try {
    $magick = Require-Command 'magick.exe'
    $ffmpeg = Require-Command 'ffmpeg.exe'
    $ffprobe = Require-Command 'ffprobe.exe'

    $magickDir = Split-Path -Parent $magick
    Copy-Item -Path (Join-Path $magickDir '*') -Destination $tools -Recurse -Force
    Copy-Item -LiteralPath $ffmpeg -Destination (Join-Path $tools 'ffmpeg.exe') -Force
    Copy-Item -LiteralPath $ffprobe -Destination (Join-Path $tools 'ffprobe.exe') -Force

    $env:FILEDONE_TOOLS_DIR = $tools
    $env:FILEDONE_TEST_MODE = '1'

    $input = Join-Path $root 'shell 路徑 test.png'
    $output = Join-Path $root 'shell 路徑 test_smaller.jpg'
    Invoke-Checked $magick @('-size','1200x800','gradient:',$input)

    $process = [System.Diagnostics.ProcessStartInfo]::new()
    $process.FileName = $harness.Path
    $process.UseShellExecute = $false
    $process.CreateNoWindow = $true
    $null = $process.ArgumentList.Add($dll.Path)
    $null = $process.ArgumentList.Add($input)
    $null = $process.ArgumentList.Add($output)
    $running = [System.Diagnostics.Process]::Start($process)
    if (!$running) { throw 'shell runtime smoke harness failed to start' }
    $running.WaitForExit()
    if ($running.ExitCode -ne 0) { throw "shell runtime smoke harness exit=$($running.ExitCode)" }
    if (!(Test-Path -LiteralPath $output -PathType Leaf)) { throw 'shell runtime output missing' }
    if ((Get-Item -LiteralPath $output).Length -le 0) { throw 'shell runtime output empty' }

    Write-Host 'SHELL_RUNTIME_SMOKE_PASS'
}
finally {
    Remove-Item Env:FILEDONE_TOOLS_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:FILEDONE_TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
