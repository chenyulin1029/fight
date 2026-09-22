param(
    [string]$Workspace=(Get-Location).Path,
    [string]$OutputDir='artifacts/filedone-im-minimal',
    [string]$EvidencePath='artifacts/evidence/im-minimal-build.json'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$version='7.1.2-31'
$dependencyRelease='2026.09.01.0503'
$dependencyArtifact='windows-x64-static-OpenMP-linked-runtime.zip'
$dependencySha='8AFBAC24F681A6D4A1D747E0835EF243F3628616B7FA9E5AA15C64D72F2F0FB6'
$fileCoderSources=@('jpeg.c','png.c','gif.c','tiff.c','webp.c','heic.c','pdf.c','bmp.c')
$fixturePseudoCoderSources=@('xc.c','gradient.c','plasma.c')
$registeredCoderSources=@($fileCoderSources + $fixturePseudoCoderSources)
$internalHelperSources=@('psd.c')
$keepCoderSources=@($registeredCoderSources + $internalHelperSources)
$keepCoderConfigs=@('Config.jpeg.txt','Config.png.txt','Config.tiff.txt','Config.webp.txt','Config.heic.txt')

function Assert-True([bool]$condition,[string]$message){
    if(-not $condition){ throw $message }
}

function Write-Utf8NoBom([string]$Path,[string]$Text){
    $encoding=[Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path,$Text,$encoding)
}

$root=(Resolve-Path -LiteralPath $Workspace).Path
$source=Join-Path $root 'ImageMagick'
$configure=Join-Path $root 'Configure'
$artifacts=Join-Path $root 'Artifacts'
$out=Join-Path $root $OutputDir
$evidenceFile=Join-Path $root $EvidencePath

Assert-True (Test-Path -LiteralPath (Join-Path $source 'configure')) 'ImageMagick source tree missing'
$sourceVersion=(Select-String -LiteralPath (Join-Path $source 'configure') -Pattern "PACKAGE_VERSION='([^']+)'" | Select-Object -First 1).Matches.Groups[1].Value
Assert-True ($sourceVersion -eq $version) "ImageMagick source version drift: $sourceVersion"

$sourceCommit=(git -C $source rev-parse HEAD).Trim()
Assert-True ($LASTEXITCODE -eq 0 -and $sourceCommit) 'unable to resolve ImageMagick source commit'

$configExe=Join-Path $configure 'Configure.Release.x64.exe'
Assert-True (Test-Path -LiteralPath $configExe -PathType Leaf) 'Configure.Release.x64.exe missing'

$dependencyZip=Join-Path (Join-Path $root 'Dependencies') $dependencyArtifact
Assert-True (Test-Path -LiteralPath $dependencyZip -PathType Leaf) "dependency artifact missing: $dependencyZip"
$actualDependencySha=(Get-FileHash -LiteralPath $dependencyZip -Algorithm SHA256).Hash.ToUpperInvariant()
Assert-True ($actualDependencySha -eq $dependencySha) "dependency artifact SHA drift: $actualDependencySha"

# FileDone shipping delegate/link closure.  The official prebuilt dependency
# archive contains generated capability headers and a pre-build static-lib
# list rather than dependency source/config directories.  MagickBaseConfig
# merges every Artifacts/config/*.h file, and static applications link every
# library listed in Artifacts/pre-build-libs.txt.  Prune both inputs before
# Configure so unused delegates are not compiled or linked.
$keepCapabilityHeaders=@(
    'heif.h',
    'jpeg-turbo.h',
    'lcms.h',
    'lzma.h',
    'png.h',
    'tiff.h',
    'webp.h',
    'xml.h',
    'zlib.h'
)
$configArtifacts=Join-Path $artifacts 'config'
Assert-True (Test-Path -LiteralPath $configArtifacts -PathType Container) "dependency config artifacts missing: $configArtifacts"
$removedCapabilityHeaders=@()
foreach($header in @(Get-ChildItem -LiteralPath $configArtifacts -Filter '*.h' -File)){
    if($header.Name -notin $keepCapabilityHeaders){
        $removedCapabilityHeaders += $header.Name
        Remove-Item -LiteralPath $header.FullName -Force
    }
}
$remainingCapabilityHeaders=@(Get-ChildItem -LiteralPath $configArtifacts -Filter '*.h' -File | Select-Object -ExpandProperty Name | Sort-Object)
foreach($required in $keepCapabilityHeaders){
    Assert-True ($required -in $remainingCapabilityHeaders) "required capability header missing after prune: $required"
}
$unexpectedCapabilityHeaders=@($remainingCapabilityHeaders | Where-Object { $_ -notin $keepCapabilityHeaders })
Assert-True ($unexpectedCapabilityHeaders.Count -eq 0) "unexpected capability headers survived prune: $($unexpectedCapabilityHeaders -join ', ')"

$magickCoreConfig=Join-Path $configure 'Configs/MagickCore/Config.txt'
Assert-True (Test-Path -LiteralPath $magickCoreConfig -PathType Leaf) 'MagickCore Configure config missing'
$magickCoreConfigText=@'
[DYNAMIC_LIBRARY]

[DEFINES]
_MAGICKLIB_

[DYNAMIC_DEFINES]
_MAGICKMOD_

[INCLUDES]
\ImageMagick

[REFERENCES]
lcms
xml
zlib

[OPENCL]

[MAGICK_PROJECT]
'@
Write-Utf8NoBom $magickCoreConfig $magickCoreConfigText

$keepPreBuildLibs=@(
    'CORE_RL_aom_.lib',
    'CORE_RL_brotli_.lib',
    'CORE_RL_de265_.lib',
    'CORE_RL_heif_.lib',
    'CORE_RL_jpeg-turbo-12_.lib',
    'CORE_RL_jpeg-turbo-16_.lib',
    'CORE_RL_jpeg-turbo_.lib',
    'CORE_RL_lcms_.lib',
    'CORE_RL_lzma_.lib',
    'CORE_RL_openh264_.lib',
    'CORE_RL_png_.lib',
    'CORE_RL_tiff_.lib',
    'CORE_RL_webp_.lib',
    'CORE_RL_xml_.lib',
    'CORE_RL_zlib_.lib'
)
$preBuildLibsPath=Join-Path $artifacts 'pre-build-libs.txt'
Assert-True (Test-Path -LiteralPath $preBuildLibsPath -PathType Leaf) "pre-build-libs missing: $preBuildLibsPath"
$allPreBuildLibs=@(Get-Content -LiteralPath $preBuildLibsPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach($required in $keepPreBuildLibs){
    Assert-True ($required -in $allPreBuildLibs) "required pre-build lib missing: $required"
}
$removedPreBuildLibs=@($allPreBuildLibs | Where-Object { $_ -notin $keepPreBuildLibs })
Write-Utf8NoBom $preBuildLibsPath (($keepPreBuildLibs -join "`r`n") + "`r`n")

$codersDir=Join-Path $source 'coders'

$allCoderSources=@(Get-ChildItem -LiteralPath $codersDir -Filter '*.c' -File | Select-Object -ExpandProperty Name | Sort-Object)
foreach($name in $keepCoderSources){
    Assert-True ($name -in $allCoderSources) "required coder/helper source missing: $name"
}
$excludedCoderSources=@($allCoderSources | Where-Object { $_ -notin $keepCoderSources })
Assert-True ($excludedCoderSources.Count -gt 0) 'coder trim would exclude nothing'

$coderConfigDir=Join-Path $configure 'Configs/coders'
$coderConfig=Join-Path $coderConfigDir 'Config.txt'
Assert-True (Test-Path -LiteralPath $coderConfig -PathType Leaf) 'Configure coder Config.txt missing'

$configText=@"
[CODER]

[INCLUDES]
..

[EXCLUDES]
$($excludedCoderSources -join "`r`n")

[REFERENCES]
MagickCore

[MAGICK_PROJECT]
"@
Write-Utf8NoBom $coderConfig $configText

$specialConfigs=@(Get-ChildItem -LiteralPath $coderConfigDir -Filter 'Config.*.txt' -File)
$removedCoderConfigs=@()
foreach($file in $specialConfigs){
    if($file.Name -notin $keepCoderConfigs){
        $removedCoderConfigs += $file.Name
        Remove-Item -LiteralPath $file.FullName -Force
    }
}
foreach($name in $keepCoderConfigs){
    Assert-True (Test-Path -LiteralPath (Join-Path $coderConfigDir $name) -PathType Leaf) "required coder config missing: $name"
}

$codersList=Join-Path $codersDir 'coders-list.h'
Assert-True (Test-Path -LiteralPath $codersList -PathType Leaf) 'coders-list.h missing'
$codersListText=@'
/* FileDone source-minimal static coder registry. Generated by Build-ImageMagickMinimal.ps1. */
#include "coders/coders-private.h"

#if defined(MAGICKCORE_JPEG_DELEGATE)
  AddMagickCoder(JPEG)
#endif
#if defined(MAGICKCORE_PNG_DELEGATE)
  AddMagickCoder(PNG)
#endif
AddMagickCoder(GIF)
AddMagickCoder(BMP)
AddMagickCoder(GRADIENT)
AddMagickCoder(PLASMA)
AddMagickCoder(XC)
#if defined(MAGICKCORE_TIFF_DELEGATE)
  AddMagickCoder(TIFF)
#endif
#if defined(MAGICKCORE_WEBP_DELEGATE)
  AddMagickCoder(WEBP)
#endif
#if defined(MAGICKCORE_HEIC_DELEGATE)
  AddMagickCoder(HEIC)
#endif
AddMagickCoder(PDF)
'@
Write-Utf8NoBom $codersList $codersListText

Push-Location $configure
try {
    & $configExe /noWizard /VS2026 /hdri /Q16 /x64 /static /linkRuntime /onlyMagick
    if($LASTEXITCODE -ne 0){ throw "Configure failed: $LASTEXITCODE" }
}
finally { Pop-Location }

$solution=Get-ChildItem -LiteralPath $root -Filter '*.sln' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
Assert-True ($null -ne $solution) 'ImageMagick solution was not generated'

$vsDevCmd='C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\Tools\VsDevCmd.bat'
Assert-True (Test-Path -LiteralPath $vsDevCmd -PathType Leaf) "VS2026 developer command prompt missing: $vsDevCmd"
$buildCommand="call `"$vsDevCmd`" -arch=x64 -host_arch=x64 && msbuild `"$($solution.FullName)`" /m /t:Rebuild /p:Configuration=Release,Platform=x64"
cmd.exe /d /s /c $buildCommand
if($LASTEXITCODE -ne 0){ throw "msbuild failed: $LASTEXITCODE" }

$bin=Join-Path $artifacts 'bin'
$magick=Join-Path $bin 'magick.exe'
Assert-True (Test-Path -LiteralPath $magick -PathType Leaf) "built magick.exe missing: $magick"

Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item -LiteralPath $magick -Destination (Join-Path $out 'magick.exe') -Force
Get-ChildItem -LiteralPath $bin -Filter '*.xml' -File -ErrorAction SilentlyContinue | Copy-Item -Destination $out -Force
$icc=Join-Path $bin 'sRGB.icc'
if(Test-Path -LiteralPath $icc){ Copy-Item -LiteralPath $icc -Destination $out -Force }

$builtMagick=Join-Path $out 'magick.exe'
$versionOutput=@(& $builtMagick -version 2>&1 | ForEach-Object { $_.ToString() })
Assert-True ($LASTEXITCODE -eq 0) "built magick.exe did not start`n$($versionOutput -join "`n")"

$evidence=[ordered]@{
    status='BUILT_NOT_YET_GATE_PASSED'
    imageMagickVersion=$version
    imageMagickSourceCommit=$sourceCommit
    flavor='Q16-HDRI'
    architecture='x64'
    buildType='static-linked-runtime'
    configureFlags=@('/noWizard','/VS2026','/hdri','/Q16','/x64','/static','/linkRuntime','/onlyMagick')
    dependencyRelease=$dependencyRelease
    dependencyArtifact=$dependencyArtifact
    dependencySha256=$actualDependencySha
    keptCapabilityHeaders=$keepCapabilityHeaders
    removedCapabilityHeaders=@($removedCapabilityHeaders | Sort-Object)
    remainingCapabilityHeaders=$remainingCapabilityHeaders
    keptPreBuildLibs=$keepPreBuildLibs
    removedPreBuildLibs=@($removedPreBuildLibs | Sort-Object)
    magickCoreReferences=@('lcms','xml','zlib')
    fileCoderSources=$fileCoderSources
    fixturePseudoCoderSources=$fixturePseudoCoderSources
    registeredCoderSources=$registeredCoderSources
    internalHelperSources=$internalHelperSources
    excludedCoderSourceCount=$excludedCoderSources.Count
    keptSpecialCoderConfigs=$keepCoderConfigs
    removedSpecialCoderConfigCount=$removedCoderConfigs.Count
    magickExeSha256=(Get-FileHash -LiteralPath $builtMagick -Algorithm SHA256).Hash.ToUpperInvariant()
    magickExeBytes=(Get-Item -LiteralPath $builtMagick).Length
    packagedFiles=@(Get-ChildItem -LiteralPath $out -File | Select-Object -ExpandProperty Name | Sort-Object)
    versionOutput=$versionOutput
}
$evidenceDir=Split-Path -Parent $evidenceFile
if($evidenceDir){ New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null }
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8

Write-Host 'FILEDONE_IMAGEMAGICK_MINIMAL_BUILD_COMPLETE'
$evidence | ConvertTo-Json -Depth 8 | Write-Host
