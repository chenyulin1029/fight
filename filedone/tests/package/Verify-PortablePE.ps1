param(
    [Parameter(Mandatory=$true)][string]$ToolPath,
    [string]$EvidencePath=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition,[string]$Message){
    if(-not $Condition){ throw $Message }
}

$tool=(Resolve-Path -LiteralPath $ToolPath).Path
$dumpbin=(Get-Command dumpbin.exe -ErrorAction Stop).Source
$lines=@(& $dumpbin /nologo /dependents $tool 2>&1 | ForEach-Object { $_.ToString() })
Assert-True ($LASTEXITCODE -eq 0) "dumpbin /dependents failed for $tool"

$dependencies=@()
foreach($line in $lines){
    $trim=$line.Trim()
    if($trim -match '^[A-Za-z0-9._+-]+\.dll$'){
        $dependencies += $trim.ToUpperInvariant()
    }
}
$dependencies=@($dependencies | Sort-Object -Unique)
Assert-True ($dependencies.Count -gt 0) "no PE dependencies parsed for $tool"

# Windows inbox/API-set DLLs are allowed.  This gate specifically rejects
# redistributable/compiler runtimes and third-party codec/delegate DLLs that
# would turn a copied tool into a hidden external-install dependency.
$blockedPatterns=@(
    '^VCOMP[0-9_]*\.DLL$',
    '^VCRUNTIME[0-9_]*\.DLL$',
    '^MSVCP[0-9_]*\.DLL$',
    '^CONCRT[0-9_]*\.DLL$',
    '^LIBGCC.*\.DLL$',
    '^LIBSTDC\+\+.*\.DLL$',
    '^LIBWINPTHREAD.*\.DLL$',
    '^CORE_.*\.DLL$',
    '^IM_MOD_.*\.DLL$',
    '^GS(DLL|DLL64|WIN).*\.DLL$',
    '^LIBHEIF.*\.DLL$',
    '^LIBDE265.*\.DLL$',
    '^OPENH264.*\.DLL$',
    '^AOM.*\.DLL$'
)
$blocked=@()
foreach($dep in $dependencies){
    foreach($pattern in $blockedPatterns){
        if($dep -match $pattern){
            $blocked += $dep
            break
        }
    }
}
$blocked=@($blocked | Sort-Object -Unique)

$evidence=[ordered]@{
    status=if($blocked.Count -eq 0){'PASS'}else{'FAIL'}
    tool=$tool
    sha256=(Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToUpperInvariant()
    dependencies=$dependencies
    blockedDependencies=$blocked
    dumpbin=$dumpbin
}
if($EvidencePath){
    $parent=Split-Path -Parent $EvidencePath
    if($parent){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}

if($blocked.Count -gt 0){
    throw "portable PE gate rejected external runtime dependencies: $($blocked -join ', ')"
}

Write-Host 'FILEDONE_PORTABLE_PE_GATE_PASS'
$evidence | ConvertTo-Json -Depth 6 | Write-Host
