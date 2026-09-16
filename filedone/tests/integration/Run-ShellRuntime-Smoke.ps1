$ErrorActionPreference='Stop'

$sourcePath = 'filedone/src/FileDoneShell.cpp'
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8

if ($source -match 'FileDoneBridge\.exe') {
    throw 'Shell still targets FileDoneBridge.exe'
}
if ($source -notmatch 'FileDoneRuntime\.exe') {
    throw 'Shell does not target FileDoneRuntime.exe'
}

Write-Host 'SHELL_RUNTIME_SOURCE_PASS'
