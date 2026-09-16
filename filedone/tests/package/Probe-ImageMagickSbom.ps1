$ErrorActionPreference='Stop'

$version='7.1.2-31'
$archiveName="ImageMagick-$version-portable-Q16-HDRI-x64.7z"
$sbomName="ImageMagick-$version-portable-Q16-HDRI-x64.cdx.json"
$base="https://github.com/ImageMagick/ImageMagick/releases/download/$version"
$expectedArchive='A6A83A77A5284A2CAE5CA4A81D95E5FAD21ECD56CDB647EE99F970E233504FFF'
$expectedSbom='E376CAEE27C579C445D79DEEDE5422D6F14C3513AA727D4A7FDF3E019F541209'

$root=Join-Path $env:TEMP ("FileDone_ImageMagickProof_" + $PID)
$extract=Join-Path $root 'portable'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$extract | Out-Null

function Download-Verified([string]$url,[string]$dest,[string]$expected) {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    $actual=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){ throw "SHA mismatch for $([IO.Path]::GetFileName($dest)): $actual" }
    Write-Host "VERIFIED_SHA256 $([IO.Path]::GetFileName($dest))=$actual"
}

try {
    $archive=Join-Path $root $archiveName
    $sbomPath=Join-Path $root $sbomName
    Download-Verified "$base/$archiveName" $archive $expectedArchive
    Download-Verified "$base/$sbomName" $sbomPath $expectedSbom

    $sevenZip=(Get-Command 7z.exe -ErrorAction SilentlyContinue)
    if(!$sevenZip){ $sevenZip=(Get-Command 7z -ErrorAction Stop) }
    & $sevenZip.Source x $archive "-o$extract" -y | Out-Null
    if($LASTEXITCODE -ne 0){ throw "7z extraction failed: $LASTEXITCODE" }

    $magick=Get-ChildItem -LiteralPath $extract -Filter 'magick.exe' -File -Recurse | Select-Object -First 1
    if(!$magick){ throw 'magick.exe missing from official portable archive' }
    $versionText=@(& $magick.FullName -version 2>&1)
    if($LASTEXITCODE -ne 0){ throw "portable magick.exe failed: $LASTEXITCODE`n$($versionText -join "`n")" }
    Write-Host '=== IMAGEMAGICK VERSION ==='
    $versionText | ForEach-Object { Write-Host $_ }

    $sbom=Get-Content -LiteralPath $sbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($sbom.bomFormat -ne 'CycloneDX'){ throw "unexpected SBOM format: $($sbom.bomFormat)" }
    if(!$sbom.components -or @($sbom.components).Count -lt 1){ throw 'SBOM contains no components' }

    $rows=@()
    foreach($component in @($sbom.components)){
        $licenses=@()
        foreach($entry in @($component.licenses)){
            if($entry.license.id){ $licenses += [string]$entry.license.id }
            elseif($entry.license.name){ $licenses += [string]$entry.license.name }
            elseif($entry.expression){ $licenses += [string]$entry.expression }
        }
        $rows += [pscustomobject]@{
            type=[string]$component.type
            name=[string]$component.name
            version=[string]$component.version
            licenses=($licenses -join ' OR ')
            purl=[string]$component.purl
        }
    }

    Write-Host '=== IMAGEMAGICK SBOM COMPONENTS ==='
    $rows | Sort-Object name,version | Format-Table -AutoSize | Out-String -Width 240 | Write-Host

    $missing=@($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.licenses) })
    Write-Host "IMAGEMAGICK_SBOM_COMPONENT_COUNT=$($rows.Count)"
    Write-Host "IMAGEMAGICK_SBOM_MISSING_LICENSE_COUNT=$($missing.Count)"
    if($missing.Count -gt 0){
        Write-Host '=== COMPONENTS WITHOUT DECLARED LICENSE ==='
        $missing | Sort-Object name,version | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
    }

    $evidence=[ordered]@{
        status='PROBED'
        version=$version
        archive=$archiveName
        archiveSha256=$expectedArchive
        sbom=$sbomName
        sbomSha256=$expectedSbom
        componentCount=$rows.Count
        componentsMissingDeclaredLicense=$missing.Count
        magickVersionLines=@($versionText | ForEach-Object { $_.ToString() })
        components=@($rows | Sort-Object name,version)
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'imagemagick-sbom-proof.json') -Encoding utf8

    Write-Host 'IMAGEMAGICK_SBOM_PROOF_COMPLETE'
    Get-Content -LiteralPath (Join-Path $root 'imagemagick-sbom-proof.json') -Raw
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
