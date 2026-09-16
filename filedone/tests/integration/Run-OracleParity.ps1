$ErrorActionPreference='Stop'

$oracle = Resolve-Path 'filedone/out/oracle/FileDoneCore.P1.5.2.ps1' -ErrorAction SilentlyContinue
if (!$oracle) { throw 'frozen P1.5.2 oracle missing' }
$expected='6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD'
$actual=(Get-FileHash -LiteralPath $oracle.Path -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual -ne $expected){ throw "oracle SHA drift: $actual" }

$cases = Get-Content -LiteralPath 'filedone/tests/integration/parity-cases.json' -Raw -Encoding UTF8 | ConvertFrom-Json
if(@($cases).Count -lt 10){ throw 'parity case matrix incomplete' }

$lines = Get-Content -LiteralPath $oracle.Path -Encoding UTF8
Write-Host '=== ORACLE SURFACE HEAD ==='
$headCount=[Math]::Min(90,$lines.Count)
for($i=0;$i -lt $headCount;$i++){ Write-Host (('{0:D4}: ' -f ($i+1)) + $lines[$i]) }
Write-Host '=== ORACLE SURFACE TAIL ==='
$start=[Math]::Max(0,$lines.Count-120)
for($i=$start;$i -lt $lines.Count;$i++){ Write-Host (('{0:D4}: ' -f ($i+1)) + $lines[$i]) }

throw 'ORACLE_PARITY_RED: adapter not implemented yet'
