$ErrorActionPreference='Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repo

$expected='6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD'
$parts=Get-ChildItem -LiteralPath 'filedone/tests/oracle/parts' -Filter 'part*.b64' | Sort-Object Name
if($parts.Count -ne 5){ throw "P1.5.2 oracle part count mismatch: $($parts.Count)" }
$base64=($parts | ForEach-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8).Trim() }) -join ''
$oracleBytes=[Convert]::FromBase64String($base64)
New-Item -ItemType Directory -Force -Path 'filedone/out/oracle' | Out-Null
$oracle='filedone/out/oracle/FileDoneCore.P1.5.2.ps1'
[IO.File]::WriteAllBytes((Join-Path $repo $oracle),$oracleBytes)
$actual=(Get-FileHash -LiteralPath $oracle -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual -ne $expected){ throw "P1.5.2 oracle drift: $actual" }

New-Item -ItemType Directory -Force -Path filedone/out | Out-Null
Remove-Item -LiteralPath filedone/out/runtime_unit_tests.exe -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath filedone/out/FileDoneRuntime.exe -Force -ErrorAction SilentlyContinue

$common=@('/nologo','/std:c++17','/EHsc','/MT','/DUNICODE','/D_UNICODE','/W4','/WX')
$unitSources=@(
    'filedone/tests/runtime_unit_tests.cpp',
    'filedone/runtime/RequestFile.cpp',
    'filedone/runtime/PathPolicy.cpp',
    'filedone/runtime/ActionMutex.cpp'
)
& cl.exe @common '/Ifiledone/tests' '/Ifiledone/runtime' @unitSources `
    '/Fe:filedone/out/runtime_unit_tests.exe' '/link' 'bcrypt.lib'
if($LASTEXITCODE -ne 0){ throw "runtime unit-test compile failed: $LASTEXITCODE" }

& filedone/out/runtime_unit_tests.exe
if($LASTEXITCODE -ne 0){ throw "runtime unit tests failed: $LASTEXITCODE" }

if (Test-Path -LiteralPath filedone/runtime/FileDoneRuntime.cpp) {
    $sources = Get-ChildItem -LiteralPath filedone/runtime -Filter '*.cpp' | ForEach-Object { $_.FullName }
    & cl.exe @common @sources '/Fe:filedone/out/FileDoneRuntime.exe' '/link' 'bcrypt.lib' 'shell32.lib' 'user32.lib' 'ole32.lib'
    if($LASTEXITCODE -ne 0){ throw "FileDoneRuntime compile failed: $LASTEXITCODE" }
}
