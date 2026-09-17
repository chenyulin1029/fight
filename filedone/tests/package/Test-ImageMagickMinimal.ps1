param(
    [Parameter(Mandatory=$true)][string]$MagickDir,
    [string]$EvidencePath=''
)

$ErrorActionPreference='Stop'
$expectedVersion='7.1.2-31'
$expectedFlavor='Q16-HDRI'
$allowedModules=@('JPEG','PNG','GIF','TIFF','WEBP','HEIC','PDF')
$requiredRw=@('JPEG','PNG','GIF','TIFF','WEBP','HEIC','AVIF')
$forbiddenFormats=@('BMP','SVG','JP2','JXL','EXR','DNG')

function Assert-True([bool]$condition,[string]$message) {
    if(-not $condition){ throw $message }
}

function Invoke-Magick([string[]]$Arguments) {
    $lines=@(& $script:magick @Arguments 2>&1)
    $exit=$LASTEXITCODE
    if($exit -ne 0){
        throw "magick failed exit=$exit args=$($Arguments -join ' ')`n$($lines -join "`n")"
    }
    return @($lines | ForEach-Object { $_.ToString() })
}

$resolved=(Resolve-Path -LiteralPath $MagickDir).Path
$script:magick=Join-Path $resolved 'magick.exe'
Assert-True (Test-Path -LiteralPath $script:magick -PathType Leaf) "magick.exe missing: $script:magick"

$versionLines=Invoke-Magick @('-version')
$versionText=$versionLines -join "`n"
Assert-True ($versionText -match [regex]::Escape("ImageMagick $expectedVersion")) "unexpected ImageMagick version`n$versionText"
Assert-True ($versionText -match [regex]::Escape($expectedFlavor)) "unexpected ImageMagick flavor; expected $expectedFlavor`n$versionText"

$formatLines=Invoke-Magick @('-list','format')
$rows=@()
foreach($line in $formatLines){
    $trim=$line.Trim()
    if(!$trim -or $trim.StartsWith('Format') -or $trim.StartsWith('-')){ continue }
    $parts=@($trim -split '\s+',4)
    if($parts.Count -lt 3){ continue }
    $mode=[string]$parts[2]
    if($mode -notmatch '^[r-][w-][+-]$'){ continue }
    $rows += [pscustomobject]@{
        format=([string]$parts[0]).TrimEnd('*').ToUpperInvariant()
        module=([string]$parts[1]).ToUpperInvariant()
        mode=$mode
    }
}
if($rows.Count -eq 0){
    Write-Host '=== RAW FORMAT LIST ==='
    $formatLines | ForEach-Object { Write-Host $_ }
    throw 'unable to parse ImageMagick format list'
}

foreach($name in $requiredRw){
    $row=$rows | Where-Object { $_.format -eq $name } | Select-Object -First 1
    Assert-True ($null -ne $row) "required format missing: $name"
    Assert-True ($row.mode[0] -eq 'r' -and $row.mode[1] -eq 'w') "required format is not read/write: $name mode=$($row.mode)"
}
$pdf=$rows | Where-Object { $_.format -eq 'PDF' } | Select-Object -First 1
Assert-True ($null -ne $pdf) 'required format missing: PDF'
Assert-True ($pdf.mode[1] -eq 'w') "PDF is not writable: mode=$($pdf.mode)"

foreach($name in $forbiddenFormats){
    $present=@($rows | Where-Object { $_.format -eq $name })
    Assert-True ($present.Count -eq 0) "forbidden non-FileDone coder still registered: $name"
}
$unexpectedModules=@($rows.module | Sort-Object -Unique | Where-Object { $_ -notin $allowedModules })
Assert-True ($unexpectedModules.Count -eq 0) "unexpected coder modules registered: $($unexpectedModules -join ', ')"

$work=Join-Path $env:TEMP ("FileDone_IM_Min_Test_" + $PID)
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    $source=Join-Path $work 'source.png'
    [IO.File]::WriteAllBytes($source,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC'))

    $roundTrips=[ordered]@{}
    foreach($ext in @('png','jpg','gif','tiff','webp','heic','avif')){
        $encoded=Join-Path $work ("encoded.$ext")
        $decoded=Join-Path $work ("decoded-$ext.png")
        [void](Invoke-Magick @($source,$encoded))
        Assert-True ((Test-Path -LiteralPath $encoded) -and ((Get-Item -LiteralPath $encoded).Length -gt 0)) "encode produced no output: $ext"
        [void](Invoke-Magick @($encoded,$decoded))
        Assert-True ((Test-Path -LiteralPath $decoded) -and ((Get-Item -LiteralPath $decoded).Length -gt 0)) "decode produced no output: $ext"
        $roundTrips[$ext]=[ordered]@{
            encodedBytes=(Get-Item -LiteralPath $encoded).Length
            decodedBytes=(Get-Item -LiteralPath $decoded).Length
        }
    }

    $page2=Join-Path $work 'page2.png'
    Copy-Item -LiteralPath $source -Destination $page2
    $pdfOut=Join-Path $work 'two-pages.pdf'
    [void](Invoke-Magick @($source,$page2,$pdfOut))
    Assert-True ((Test-Path -LiteralPath $pdfOut) -and ((Get-Item -LiteralPath $pdfOut).Length -gt 8)) 'PDF write produced no output'
    $pdfHeader=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pdfOut)[0..4])
    Assert-True ($pdfHeader -eq '%PDF-') "PDF header invalid: $pdfHeader"

    $relocationRoot=Join-Path $env:TEMP ("FileDone 中文 路徑 $PID")
    $relocated=Join-Path $relocationRoot 'ImageMagick Minimal'
    Remove-Item -LiteralPath $relocationRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $relocated | Out-Null
    Get-ChildItem -LiteralPath $resolved -Force | Copy-Item -Destination $relocated -Recurse -Force
    $relocatedMagick=Join-Path $relocated 'magick.exe'
    $relocatedVersion=@(& $relocatedMagick -version 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "relocated magick.exe failed`n$($relocatedVersion -join "`n")"
    $relocOut=Join-Path $work 'relocated.webp'
    @(& $relocatedMagick $source $relocOut 2>&1) | Out-Null
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $relocOut)) 'Chinese+space relocation conversion failed'
    Remove-Item -LiteralPath $relocationRoot -Recurse -Force -ErrorAction SilentlyContinue

    $evidence=[ordered]@{
        status='PASS'
        version=$expectedVersion
        flavor=$expectedFlavor
        magickExeSha256=(Get-FileHash -LiteralPath $script:magick -Algorithm SHA256).Hash.ToUpperInvariant()
        magickExeBytes=(Get-Item -LiteralPath $script:magick).Length
        registeredModules=@($rows.module | Sort-Object -Unique)
        requiredFormats=$requiredRw
        pdfWrite=$true
        forbiddenFormatsAbsent=$forbiddenFormats
        roundTrips=$roundTrips
        relocationChineseSpace=$true
        formatRowCount=$rows.Count
    }
    if($EvidencePath){
        $parent=Split-Path -Parent $EvidencePath
        if($parent){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
    }
    Write-Host 'FILEDONE_IMAGEMAGICK_MINIMAL_GATE_PASS'
    $evidence | ConvertTo-Json -Depth 8 | Write-Host
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
