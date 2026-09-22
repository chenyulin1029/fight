param(
    [Parameter(Mandatory=$true)][string]$MagickDir,
    [string]$EvidencePath=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$expectedVersion='7.1.2-31'
$allowedDelegates=@(
    'bzlib',
    'heic',
    'jpeg',
    'lcms',
    'lzma',
    'png',
    'tiff',
    'webp',
    'xml',
    'zip',
    'zlib'
)
$explicitlyForbidden=@(
    'cairo',
    'freetype',
    'gslib',
    'jng',
    'jp2',
    'jxl',
    'lqr',
    'openexr',
    'pango',
    'pangocairo',
    'ps',
    'raqm',
    'raw',
    'rsvg'
)

function Assert-True([bool]$Condition,[string]$Message) {
    if(-not $Condition){ throw $Message }
}

$root=(Resolve-Path -LiteralPath $MagickDir).Path
$magick=Join-Path $root 'magick.exe'
Assert-True (Test-Path -LiteralPath $magick -PathType Leaf) "magick.exe missing: $magick"

$versionLines=@(& $magick -version 2>&1 | ForEach-Object { $_.ToString() })
Assert-True ($LASTEXITCODE -eq 0) "magick -version failed"
$versionText=$versionLines -join "`n"
Assert-True ($versionText -match [regex]::Escape("ImageMagick $expectedVersion")) "unexpected ImageMagick version"

$delegateLine=$versionLines | Where-Object { $_ -match '^Delegates \(built-in\):\s*(.*)$' } | Select-Object -First 1
Assert-True ($null -ne $delegateLine) 'ImageMagick built-in delegate line missing'
$delegateText=([regex]::Match($delegateLine,'^Delegates \(built-in\):\s*(.*)$')).Groups[1].Value
$delegates=@($delegateText -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)

$forbiddenPresent=@($delegates | Where-Object { $_ -in $explicitlyForbidden })
$unexpected=@($delegates | Where-Object { $_ -notin $allowedDelegates })

$evidence=[ordered]@{
    status=if($forbiddenPresent.Count -eq 0 -and $unexpected.Count -eq 0){'PASS'}else{'FAIL'}
    imageMagickVersion=$expectedVersion
    magickExeSha256=(Get-FileHash -LiteralPath $magick -Algorithm SHA256).Hash.ToUpperInvariant()
    delegates=$delegates
    allowedDelegates=$allowedDelegates
    explicitlyForbiddenPresent=$forbiddenPresent
    unexpectedDelegates=$unexpected
}
if($EvidencePath){
    $parent=Split-Path -Parent $EvidencePath
    if($parent){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}

if($forbiddenPresent.Count -gt 0){
    throw "shipping policy rejected built-in delegates: $($forbiddenPresent -join ', ')"
}
if($unexpected.Count -gt 0){
    throw "unreviewed built-in delegates present: $($unexpected -join ', ')"
}

Write-Host 'FILEDONE_IMAGEMAGICK_SHIPPING_DELEGATE_POLICY_PASS'
$evidence | ConvertTo-Json -Depth 6 | Write-Host
