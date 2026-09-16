$ErrorActionPreference='Stop'

$version='7.1.2-31'
$archiveName="ImageMagick-$version-portable-Q16-HDRI-x64.7z"
$url="https://github.com/ImageMagick/ImageMagick/releases/download/$version/$archiveName"
$expected='A6A83A77A5284A2CAE5CA4A81D95E5FAD21ECD56CDB647EE99F970E233504FFF'
$root=Join-Path $env:TEMP ("FileDone_ImageMagickTrim_" + $PID)
$extract=Join-Path $root 'portable'
$work=Join-Path $root 'work'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$extract,$work | Out-Null

function Run-Magick([string]$exe,[string[]]$arguments) {
    $text=@(& $exe @arguments 2>&1)
    if($LASTEXITCODE -ne 0){ throw "magick failed exit=$LASTEXITCODE args=$($arguments -join ' ')`n$($text -join "`n")" }
    return $text
}

function Require-File([string]$path) {
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){ throw "missing output: $path" }
    if((Get-Item -LiteralPath $path).Length -le 0){ throw "empty output: $path" }
}

try {
    $archive=Join-Path $root $archiveName
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    $actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){ throw "ImageMagick archive SHA drift: $actual" }

    $sevenZip=(Get-Command 7z.exe -ErrorAction SilentlyContinue)
    if(!$sevenZip){ $sevenZip=(Get-Command 7z -ErrorAction Stop) }
    & $sevenZip.Source x $archive "-o$extract" -y | Out-Null
    if($LASTEXITCODE -ne 0){ throw "7z extraction failed: $LASTEXITCODE" }

    $magick=(Get-ChildItem -LiteralPath $extract -Filter 'magick.exe' -File -Recurse | Select-Object -First 1).FullName
    if(!$magick){ throw 'magick.exe missing' }

    $openh264=@(Get-ChildItem -LiteralPath $extract -Recurse -File | Where-Object { $_.Name -match 'openh264' })
    Write-Host "OPENH264_FILE_COUNT=$($openh264.Count)"
    $openh264 | ForEach-Object { Write-Host "OPENH264_FILE=$($_.FullName.Substring($extract.Length).TrimStart('\'))" }
    if($openh264.Count -lt 1){ throw 'SBOM lists OpenH264 but no OpenH264 file was found' }

    # Seed fixtures before trimming so the post-trim checks exercise decode/convert paths.
    $png=Join-Path $work 'source.png'
    $tiff=Join-Path $work 'source.tiff'
    $avif=Join-Path $work 'source.avif'
    $page1=Join-Path $work 'page1.png'
    $page2=Join-Path $work 'page2.png'
    Run-Magick $magick @('-size','800x600','gradient:',$png) | Out-Null
    Run-Magick $magick @('-size','500x350','xc:none','-fill','blue','-draw','rectangle 40,40 460,310',$tiff) | Out-Null
    Run-Magick $magick @('-size','640x480','gradient:',$avif) | Out-Null
    Run-Magick $magick @('-size','120x80','xc:red',$page1) | Out-Null
    Run-Magick $magick @('-size','120x80','xc:blue',$page2) | Out-Null

    # Remove only the OpenH264 payload; leave all other official portable components untouched.
    foreach($file in $openh264){ Remove-Item -LiteralPath $file.FullName -Force }
    $remaining=@(Get-ChildItem -LiteralPath $extract -Recurse -File | Where-Object { $_.Name -match 'openh264' })
    if($remaining.Count -ne 0){ throw 'OpenH264 trim incomplete' }

    $versionText=Run-Magick $magick @('-version')
    Write-Host '=== TRIMMED IMAGEMAGICK VERSION ==='
    $versionText | ForEach-Object { Write-Host $_ }

    $jpg=Join-Path $work 'from-avif.jpg'
    $pngFromTiff=Join-Path $work 'from-tiff.png'
    $webp=Join-Path $work 'from-png.webp'
    $pdf=Join-Path $work 'document.pdf'
    Run-Magick $magick @($avif,'-auto-orient','-quality','90',$jpg) | Out-Null
    Run-Magick $magick @($tiff,'-auto-orient',$pngFromTiff) | Out-Null
    Run-Magick $magick @($png,'-auto-orient','-strip','-quality','82',$webp) | Out-Null
    Run-Magick $magick @($page1,$page2,'-auto-orient','-units','PixelsPerInch','-density','150',$pdf) | Out-Null
    Require-File $jpg
    Require-File $pngFromTiff
    Require-File $webp
    Require-File $pdf

    $pdfBytes=[IO.File]::ReadAllBytes($pdf)
    $pdfText=[Text.Encoding]::ASCII.GetString($pdfBytes)
    $pages=([regex]::Matches($pdfText,'/Type\s*/Page(?!s)')).Count
    if($pages -ne 2){ throw "trimmed ImageMagick PDF page count mismatch: $pages" }

    Write-Host 'IMAGEMAGICK_OPENH264_TRIM_PROOF_PASS'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
