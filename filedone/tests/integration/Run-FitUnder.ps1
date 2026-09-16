$ErrorActionPreference='Stop'
$exe='filedone/out/fit_under_tests.exe'
if(!(Test-Path -LiteralPath $exe)){ throw 'fit_under_tests.exe missing' }
& $exe
if($LASTEXITCODE -ne 0){ throw "Fit Under integration tests failed: $LASTEXITCODE" }
