$ErrorActionPreference='Stop'

$runtime = (Resolve-Path 'filedone/out/FileDoneRuntime.exe' -ErrorAction SilentlyContinue)
if (!$runtime) { throw 'FileDoneRuntime.exe missing' }

$root = Join-Path $env:TEMP ("FileDone_RuntimeDispatcher_" + $PID)
$tools = Join-Path $root 'tools'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$tools | Out-Null

function Require-Command([string]$name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (!$command) { throw "$name missing" }
    return $command.Source
}

function Invoke-Checked([string]$exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe fixture command failed: $LASTEXITCODE" }
}

function Write-Request([string]$path, [string[]]$lines) {
    $encoding = [System.Text.UnicodeEncoding]::new($false,$true,$true)
    [System.IO.File]::WriteAllLines($path,$lines,$encoding)
}

function Invoke-Runtime([string]$request, [string[]]$extra = @()) {
    & $runtime.Path $request @extra
    return $LASTEXITCODE
}

function Require-File([string]$path) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "expected file missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "expected file empty: $path" }
}

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

    # Smaller routing + request cleanup.
    $smallerInput = Join-Path $root '路徑 with space.png'
    Invoke-Checked $magick @('-size','1200x800','gradient:',$smallerInput)
    $smallerRequest = Join-Path $root 'smaller.fdreq'
    Write-Request $smallerRequest @('smaller',$smallerInput)
    $code = Invoke-Runtime $smallerRequest
    if ($code -ne 0) { throw "smaller dispatcher exit=$code" }
    if (Test-Path -LiteralPath $smallerRequest) { throw 'successful request was not deleted' }
    Require-File (Join-Path $root '路徑 with space_smaller.jpg')

    # Make PDF must preserve passed order and use the first selected image for output name.
    $pdfA = Join-Path $root '01 第一張.png'
    $pdfB = Join-Path $root '02 第二張.png'
    $pdfC = Join-Path $root '03 第三張.png'
    Invoke-Checked $magick @('-size','120x80','xc:red',$pdfA)
    Invoke-Checked $magick @('-size','120x80','xc:green',$pdfB)
    Invoke-Checked $magick @('-size','120x80','xc:blue',$pdfC)
    $pdfRequest = Join-Path $root 'pdf.fdreq'
    Write-Request $pdfRequest @('makepdf',$pdfB,$pdfA,$pdfC)
    $code = Invoke-Runtime $pdfRequest
    if ($code -ne 0) { throw "pdf dispatcher exit=$code" }
    $pdfOutput = Join-Path $root '02 第二張_document.pdf'
    Require-File $pdfOutput
    $pdfBytes = [System.IO.File]::ReadAllBytes($pdfOutput)
    $pdfText = [System.Text.Encoding]::ASCII.GetString($pdfBytes)
    $pages = ([regex]::Matches($pdfText,'/Type\s*/Page(?!s)')).Count
    if ($pages -ne 3) { throw "PDF page count mismatch: $pages" }

    # Fit Under explicit target override is test-only and must stay strict.
    $fitInput = Join-Path $root 'fit target.png'
    Invoke-Checked $magick @('-size','1800x1200','plasma:fractal',$fitInput)
    $fitRequest = Join-Path $root 'fit.fdreq'
    Write-Request $fitRequest @('fitunder',$fitInput)
    $code = Invoke-Runtime $fitRequest @('--target-mb','0.12')
    if ($code -ne 0) { throw "fit-under dispatcher exit=$code" }
    $fitOutput = Join-Path $root 'fit target_under.jpg'
    Require-File $fitOutput
    if ((Get-Item -LiteralPath $fitOutput).Length -gt [math]::Floor(0.12 * 1024 * 1024)) {
        throw 'fit-under dispatcher exceeded target'
    }

    # Invalid request has the contract exit code and must not be reported as success.
    $badRequest = Join-Path $root 'bad.fdreq'
    Write-Request $badRequest @('not-an-action',$smallerInput)
    $code = Invoke-Runtime $badRequest
    if ($code -ne 2) { throw "invalid request exit code mismatch: $code" }

    Write-Host 'RUNTIME_DISPATCHER_PASS'
}
finally {
    Remove-Item Env:FILEDONE_TOOLS_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:FILEDONE_TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
