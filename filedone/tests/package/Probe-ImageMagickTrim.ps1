$ErrorActionPreference='Stop'

$version='7.1.2-31'
$archiveName="ImageMagick-$version-portable-Q16-HDRI-x64.7z"
$url="https://github.com/ImageMagick/ImageMagick/releases/download/$version/$archiveName"
$expected='A6A83A77A5284A2CAE5CA4A81D95E5FAD21ECD56CDB647EE99F970E233504FFF'
$root=Join-Path $env:TEMP ("FileDone_ImageMagickProvenance_" + $PID)
$extract=Join-Path $root 'portable'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$extract | Out-Null

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

    Write-Host '=== RELEVANT PORTABLE FILES ==='
    $relevant=@(Get-ChildItem -LiteralPath $extract -Recurse -File | Where-Object { $_.Name -match '(?i)heif|heic|de265|aom|h264' })
    $relevant | Sort-Object FullName | ForEach-Object {
        Write-Host ("PORTABLE_FILE=" + $_.FullName.Substring($extract.Length).TrimStart('\'))
    }
    $looseOpenH264=@($relevant | Where-Object { $_.Name -match '(?i)openh264' })
    Write-Host "OPENH264_LOOSE_FILE_COUNT=$($looseOpenH264.Count)"

    $heifConfigUrl='https://raw.githubusercontent.com/ImageMagick/heif/main/.ImageMagick/Config.txt'
    $openh264ConfigUrl='https://raw.githubusercontent.com/ImageMagick/openh264/main/.ImageMagick/Config.txt'
    $heifConfig=(Invoke-WebRequest -Uri $heifConfigUrl -UseBasicParsing).Content
    $openh264Config=(Invoke-WebRequest -Uri $openh264ConfigUrl -UseBasicParsing).Content

    if($heifConfig -notmatch '(?m)^HAVE_OpenH264_DECODER\s*$'){
        throw 'ImageMagick libheif build config no longer enables OpenH264 decoder'
    }
    if($heifConfig -notmatch '(?ms)^\[REFERENCES\].*?^openh264\s*$'){
        throw 'ImageMagick libheif build config no longer references OpenH264'
    }
    if($openh264Config -notmatch '(?m)^\[STATIC_LIBRARY\]\s*$'){
        throw 'ImageMagick OpenH264 build is no longer declared STATIC_LIBRARY'
    }

    Write-Host 'HEIF_CONFIG_OPENH264_DECODER=ENABLED'
    Write-Host 'HEIF_CONFIG_OPENH264_REFERENCE=PRESENT'
    Write-Host 'OPENH264_BUILD_KIND=STATIC_LIBRARY'

    $vswhere='C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    if(Test-Path -LiteralPath $vswhere){
        $dumpbinPath=& $vswhere -latest -products * -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' | Select-Object -First 1
        if($dumpbinPath -and (Test-Path -LiteralPath $dumpbinPath)){
            Write-Host '=== RELEVANT PE DEPENDENCIES ==='
            $peFiles=@(Get-ChildItem -LiteralPath $extract -Recurse -File | Where-Object { $_.Extension -in '.exe','.dll' })
            foreach($file in $peFiles){
                $deps=@(& $dumpbinPath /nologo /dependents $file.FullName 2>$null)
                $hits=@($deps | Where-Object { $_ -match '(?i)heif|heic|de265|aom|h264' })
                if($hits.Count -gt 0){
                    Write-Host ("PE=" + $file.FullName.Substring($extract.Length).TrimStart('\'))
                    $hits | ForEach-Object { Write-Host ("  DEP=" + $_.Trim()) }
                }
            }
        } else {
            Write-Host 'DUMPBIN=NOT_FOUND'
        }
    } else {
        Write-Host 'VSWHERE=NOT_FOUND'
    }

    if($looseOpenH264.Count -ne 0){
        Write-Host 'OPENH264_PACKAGING=LOOSE_PAYLOAD_PRESENT'
    } else {
        Write-Host 'OPENH264_PACKAGING=NO_LOOSE_FILE__STATIC_BUILD_REFERENCE_CONFIRMED'
    }

    Write-Host 'OFFICIAL_IMAGEMAGICK_OPENH264_PROVENANCE_PROOF_PASS'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
