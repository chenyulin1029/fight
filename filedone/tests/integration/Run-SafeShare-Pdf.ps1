$ErrorActionPreference='Stop'
$exe='filedone/out/safe_pdf_tests.exe'
if(!(Test-Path -LiteralPath $exe)){ throw 'safe_pdf_tests.exe missing' }
& $exe
if($LASTEXITCODE -ne 0){ throw "Safe Share/PDF integration tests failed: $LASTEXITCODE" }
