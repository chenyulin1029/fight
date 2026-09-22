param(
    [Parameter(Mandatory=$true)][string]$MagickDir,
    [string]$EvidencePath=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$expectedVersion='7.1.2-31'

# These are the only externally backed delegates permitted by the initial
# FileDone Store shipping policy.  This is an engineering minimization gate,
# not a legal conclusion.
$allowedExternalDelegates=@(
    'heic',
    'jpeg',
    'lcms',
    'lzma',
    'png',
    'tiff',
    'webp',
    'xml',
    'zlib'
)

# ImageMagick version.c reports these capability labels from compile-time
# platform/format combinations even when no corresponding external library
# is linked (Windows -> gslib/ps; JPEG+PNG -> jng).  They are tracked but
# intentionally excluded from the external-dependency decision.
$syntheticCapabilities=@('gslib','jng','ps')

$explicitlyForbiddenExternal=@(
    'bzlib',
    'cairo',
    'freetype',
    'jp2',
    'jxl',
    'lqr',
    'openexr',
    'pango',
    'pangocairo',
    'raqm',
    'raw',
    'rsvg',
    'zip'
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
$reported=@($delegateText -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
$externalReported=@($reported | Where-Object { $_ -notin $syntheticCapabilities })

$forbiddenPresent=@($externalReported | Where-Object { $_ -in $explicitlyForbiddenExternal })
$unexpected=@($externalReported | Where-Object { $_ -notin $allowedExternalDelegates })

$evidence=[ordered]@{
    status=if($forbiddenPresent.Count -eq 0 -and $unexpected.Count -eq 0){'PASS'}else{'FAIL'}
    imageMagickVersion=$expectedVersion
    magickExeSha256=(Get-FileHash -LiteralPath $magick -Algorithm SHA256).Hash.ToUpperInvariant()
    reportedCapabilities=$reported
    syntheticCapabilitiesIgnoredForDependencyDecision=$syntheticCapabilities
    externalDelegates=$externalReported
    allowedExternalDelegates=$allowedExternalDelegates
    explicitlyForbiddenExternalPresent=$forbiddenPresent
    unexpectedExternalDelegates=$unexpected
}
if($EvidencePath){
    $parent=Split-Path -Parent $EvidencePath
    if($parent){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}

if($forbiddenPresent.Count -gt 0){
    throw "shipping policy rejected external delegates: $($forbiddenPresent -join ', ')"
}
if($unexpected.Count -gt 0){
    throw "unreviewed external delegates present: $($unexpected -join ', ')"
}

Write-Host 'FILEDONE_IMAGEMAGICK_SHIPPING_DELEGATE_POLICY_PASS'
$evidence | ConvertTo-Json -Depth 6 | Write-Host
