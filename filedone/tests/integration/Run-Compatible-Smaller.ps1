$ErrorActionPreference='Stop'
$exe='filedone/out/action_engine_tests.exe'
if(!(Test-Path -LiteralPath $exe)){ throw 'action_engine_tests.exe missing' }
& $exe
if($LASTEXITCODE -ne 0){ throw "Compatible/Smaller integration tests failed: $LASTEXITCODE" }
