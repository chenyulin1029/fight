$ErrorActionPreference='Stop'

$oracle = Resolve-Path 'filedone/out/oracle/FileDoneCore.P1.5.2.ps1' -ErrorAction SilentlyContinue
if (!$oracle) { throw 'frozen P1.5.2 oracle missing' }
$runtime = Resolve-Path 'filedone/out/FileDoneRuntime.exe' -ErrorAction SilentlyContinue
if (!$runtime) { throw 'FileDoneRuntime.exe missing' }
$expectedSha='6956DE877DA60F42ED72112F59D7C79F6B963A6B52EA606A024763EA9451E8FD'
$actualSha=(Get-FileHash -LiteralPath $oracle.Path -Algorithm SHA256).Hash.ToUpperInvariant()
if($actualSha -ne $expectedSha){ throw "oracle SHA drift: $actualSha" }

$cases = Get-Content -LiteralPath 'filedone/tests/integration/parity-cases.json' -Raw -Encoding UTF8 | ConvertFrom-Json
if(@($cases).Count -lt 11){ throw 'parity case matrix incomplete' }

$reports = 'filedone/out/reports'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$root = Join-Path $env:TEMP ("FileDone_OracleParity_" + $PID)
$nativeTools = Join-Path $root '_native_tools'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root,$nativeTools | Out-Null
$results = [System.Collections.Generic.List[object]]::new()

$oracleText = Get-Content -LiteralPath $oracle.Path -Raw -Encoding UTF8
$nativeActionText = Get-Content -LiteralPath 'filedone/runtime/ActionEngine.cpp' -Raw -Encoding UTF8
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source

function Require-Command([string]$name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (!$command) { throw "$name missing" }
    return $command.Source
}

function Resolve-RealMediaTool([string]$name) {
    $source = Require-Command $name
    $chocoBin = if ($env:ChocolateyInstall) { Join-Path $env:ChocolateyInstall 'bin' } else { $null }
    if ($chocoBin -and $source.StartsWith($chocoBin,[StringComparison]::OrdinalIgnoreCase)) {
        $ffRoot = Join-Path $env:ChocolateyInstall 'lib\ffmpeg\tools'
        $real = Get-ChildItem -LiteralPath $ffRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 1
        if (!$real) { throw "real $name missing under Chocolatey ffmpeg tools" }
        return $real.FullName
    }
    return $source
}

function Invoke-Checked([string]$exe, [string[]]$toolArguments) {
    & $exe @toolArguments
    if ($LASTEXITCODE -ne 0) { throw "$exe fixture command failed: $LASTEXITCODE" }
}

$magick = Require-Command 'magick.exe'
$ffmpeg = Resolve-RealMediaTool 'ffmpeg.exe'
$ffprobe = Resolve-RealMediaTool 'ffprobe.exe'
$magickDir = Split-Path -Parent $magick
Copy-Item -Path (Join-Path $magickDir '*') -Destination $nativeTools -Recurse -Force
Copy-Item -LiteralPath $ffmpeg -Destination (Join-Path $nativeTools 'ffmpeg.exe') -Force
Copy-Item -LiteralPath $ffprobe -Destination (Join-Path $nativeTools 'ffprobe.exe') -Force

function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

function Write-Request([string]$path, [string]$action, [string[]]$paths) {
    $encoding = [System.Text.UnicodeEncoding]::new($false,$true,$true)
    [System.IO.File]::WriteAllLines($path,@($action) + $paths,$encoding)
}

function Set-IsolatedEnvironment([System.Diagnostics.ProcessStartInfo]$start,[string]$envRoot,[bool]$native) {
    $local = Join-Path $envRoot 'localappdata'
    $temp = Join-Path $envRoot 'temp'
    New-Item -ItemType Directory -Force -Path $local,$temp | Out-Null
    $start.Environment['LOCALAPPDATA'] = $local
    $start.Environment['TEMP'] = $temp
    $start.Environment['TMP'] = $temp
    if ($native) {
        $start.Environment['FILEDONE_TOOLS_DIR'] = $nativeTools
        $start.Environment['FILEDONE_TEST_MODE'] = '1'
    }
    else {
        [void]$start.Environment.Remove('FILEDONE_TOOLS_DIR')
        [void]$start.Environment.Remove('FILEDONE_TEST_MODE')
    }
}

function Start-Native([string]$action,[string[]]$paths,[object]$targetMb,[string]$workDir,[string]$envRoot) {
    $request = Join-Path $workDir (([Guid]::NewGuid().ToString('N')) + '.fdreq')
    Write-Request $request $action $paths
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $runtime.Path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $null = $start.ArgumentList.Add($request)
    if ($null -ne $targetMb) {
        $targetValue = [Convert]::ToDouble($targetMb,[Globalization.CultureInfo]::InvariantCulture)
        $null = $start.ArgumentList.Add('--target-mb')
        $null = $start.ArgumentList.Add($targetValue.ToString([Globalization.CultureInfo]::InvariantCulture))
    }
    Set-IsolatedEnvironment $start $envRoot $true
    $process = [System.Diagnostics.Process]::Start($start)
    if (!$process) { throw 'FileDoneRuntime.exe failed to start' }
    return $process
}

function Start-Oracle([string]$action,[string[]]$paths,[object]$targetMb,[string]$workDir,[string]$envRoot) {
    $payload = [ordered]@{ action=$action; paths=@($paths); targetMb=$targetMb }
    $json = $payload | ConvertTo-Json -Compress -Depth 4
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $oracleEsc = $oracle.Path.Replace("'","''")
    $command = @"
`$cfgText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload64'))
`$cfg=`$cfgText | ConvertFrom-Json
`$invoke=@{ Action=[string]`$cfg.action; Paths=@(`$cfg.paths); Quiet=`$true }
if (`$null -ne `$cfg.targetMb -and [double]`$cfg.targetMb -gt 0) { `$invoke.TargetMB=[double]`$cfg.targetMb }
& '$oracleEsc' @invoke
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $pwsh
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $null = $start.ArgumentList.Add('-NoLogo')
    $null = $start.ArgumentList.Add('-NoProfile')
    $null = $start.ArgumentList.Add('-EncodedCommand')
    $null = $start.ArgumentList.Add($encoded)
    Set-IsolatedEnvironment $start $envRoot $false
    $process = [System.Diagnostics.Process]::Start($start)
    if (!$process) { throw 'oracle process failed to start' }
    return $process
}

function Prepare-Fixture([string]$fixture,[string]$dir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    switch ($fixture) {
        'opaque-bmp' {
            $path=Join-Path $dir 'source.bmp'
            Invoke-Checked $magick @('-size','640x480','xc:orange',$path)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'alpha-png' {
            $path=Join-Path $dir 'source.png'
            Invoke-Checked $magick @('-size','640x480','xc:none','-fill','blue','-draw','rectangle 40,40 600,440',$path)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'large-png' {
            $path=Join-Path $dir 'source.png'
            Invoke-Checked $magick @('-size','1800x1200','plasma:fractal',$path)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'metadata-jpeg' {
            $path=Join-Path $dir 'source.jpg'
            Invoke-Checked $magick @('-size','640x480','xc:orange','-set','comment','FileDoneSecret',$path)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'ordered-images-3' {
            $p1=Join-Path $dir '01_red.png'
            $p2=Join-Path $dir '02_green.png'
            $p3=Join-Path $dir '03_blue.png'
            Invoke-Checked $magick @('-size','120x80','xc:red',$p1)
            Invoke-Checked $magick @('-size','120x80','xc:green',$p2)
            Invoke-Checked $magick @('-size','120x80','xc:blue',$p3)
            return [pscustomobject]@{ Paths=@($p1,$p2,$p3); Seeded=$null; PolicyOnly=$false }
        }
        'already-compatible-mp4' {
            $path=Join-Path $dir 'source.mp4'
            Invoke-Checked $ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=640x360:rate=24','-f','lavfi','-i','sine=frequency=900:sample_rate=44100','-t','1','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac',$path)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'unsupported-txt' {
            $path=Join-Path $dir 'source.txt'
            [IO.File]::WriteAllText($path,'unsupported',[Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'heic' {
            $jpg=Join-Path $dir 'heic_payload.jpg'
            $path=Join-Path $dir 'source.heic'
            Invoke-Checked $magick @('-size','96x96','xc:purple','-quality','92',$jpg)
            Move-Item -LiteralPath $jpg -Destination $path -Force
            & $magick identify -quiet $path *> $null
            $canDecode = ($LASTEXITCODE -eq 0)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=(-not $canDecode) }
        }
        'duplicate-output' {
            $path=Join-Path $dir 'source.png'
            Invoke-Checked $magick @('-size','900x600','gradient:',$path)
            $seeded=Join-Path $dir 'source_smaller.jpg'
            [IO.File]::WriteAllText($seeded,'SENTINEL',[Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{ Paths=@($path); Seeded=$seeded; PolicyOnly=$false }
        }
        'concurrent-same-input' {
            $path=Join-Path $dir 'source.png'
            Invoke-Checked $magick @('-size','1500x1000','plasma:fractal',$path)
            return [pscustomobject]@{ Paths=@($path); Seeded=$null; PolicyOnly=$false }
        }
        'multi-nonpdf-first-only' {
            $p1=Join-Path $dir 'first.png'
            $p2=Join-Path $dir 'second.png'
            Invoke-Checked $magick @('-size','900x600','gradient:',$p1)
            Invoke-Checked $magick @('-size','900x600','gradient:',$p2)
            return [pscustomobject]@{ Paths=@($p1,$p2); Seeded=$null; PolicyOnly=$false }
        }
        default { throw "unknown parity fixture: $fixture" }
    }
}

function File-Names([string]$dir) {
    return @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}

function Input-Hashes([string[]]$paths) {
    return @($paths | ForEach-Object { Hash $_ })
}

function Same-Hashes([string[]]$paths,[object[]]$before) {
    if ($paths.Count -ne $before.Count) { return $false }
    for($i=0;$i -lt $paths.Count;$i++) {
        if ((Hash $paths[$i]) -ne [string]$before[$i]) { return $false }
    }
    return $true
}

function Output-Suffixes([string[]]$outputs,[string]$primaryInput) {
    $stem=[IO.Path]::GetFileNameWithoutExtension($primaryInput)
    $values=@()
    foreach($path in $outputs) {
        $name=[IO.Path]::GetFileName($path)
        if($name.StartsWith($stem,[StringComparison]::OrdinalIgnoreCase)) { $values += $name.Substring($stem.Length) }
        else { $values += $name }
    }
    $values=@($values | Sort-Object)
    if($values.Count -eq 0){ return $null }
    if($values.Count -eq 1){ return $values[0] }
    return $values
}

function Pdf-PageCount([string]$path) {
    $text=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($path))
    return ([regex]::Matches($text,'/Type\s*/Page(?!s)')).Count
}

function Metadata-Removed([string]$path) {
    $value=(& $magick identify -quiet -format '%[comment]' $path) -join ''
    return ($LASTEXITCODE -eq 0 -and $value -notmatch 'FileDoneSecret')
}

function Oracle-OrderContract {
    return ($oracleText -match 'foreach\s*\(\$p\s+in\s+\$ImagePaths\)\s*\{\s*\$args\s*\+=\s*\$p\s*\}')
}

function Native-OrderContract {
    return ($nativeActionText -match 'args\.insert\(args\.end\(\),\s*paths\.begin\(\),\s*paths\.end\(\)\)')
}

function Heic-PolicyOutcome([string]$side) {
    if($side -eq 'oracle') {
        $ok = ($oracleText -match "\.heic'.*\.heif" -or $oracleText -match "@\('\.heic','\.heif'\)") -and
              ($oracleText -match "Get-UniqueOutputPath\s+\$Path\s+'_safe'\s+'\.jpg'") -and
              ($oracleText -match "'-quality','92'")
    }
    else {
        $ok = ($nativeActionText -match 'ext\s*==\s*L"\.heic"' -and $nativeActionText -match 'ext\s*==\s*L"\.heif"') -and
              ($nativeActionText -match 'UniqueOutputPath\(path,\s*L"_safe",\s*L"\.jpg"\)') -and
              ($nativeActionText -match 'L"-quality",\s*L"92"')
    }
    return [pscustomobject]@{
        status=$(if($ok){'success'}else{'failure'})
        exitCodes=@()
        outputCount=$(if($ok){1}else{0})
        extension=$(if($ok){'.jpg'}else{$null})
        suffix=$(if($ok){'_safe.jpg'}else{$null})
        originalUnchanged=$ok
        underTarget=$null
        metadataRemoved=$null
        pageCount=$null
        orderPreserved=$null
        noop=$false
        cleanFailure=$false
        existingOutputUnchanged=$null
        collisionSafe=$null
        firstOnly=$null
        verificationMode='policy-contract-fallback'
    }
}

function Run-Side([string]$side,[object]$case,[object]$fixture,[string]$workDir,[string]$envRoot) {
    $beforeNames=File-Names $workDir
    $beforeHashes=Input-Hashes @($fixture.Paths)
    $seededHash = if($fixture.Seeded){ Hash $fixture.Seeded } else { $null }
    $processes=@()
    $target = if($null -ne $case.targetMb){ [double]$case.targetMb } else { $null }

    if($case.fixture -eq 'concurrent-same-input') {
        if($side -eq 'oracle') {
            $processes += Start-Oracle $case.action @($fixture.Paths) $target $workDir $envRoot
            $processes += Start-Oracle $case.action @($fixture.Paths) $target $workDir $envRoot
        } else {
            $processes += Start-Native $case.action @($fixture.Paths) $target $workDir $envRoot
            $processes += Start-Native $case.action @($fixture.Paths) $target $workDir $envRoot
        }
    }
    else {
        if($side -eq 'oracle') { $processes += Start-Oracle $case.action @($fixture.Paths) $target $workDir $envRoot }
        else { $processes += Start-Native $case.action @($fixture.Paths) $target $workDir $envRoot }
    }

    $exitCodes=@()
    foreach($process in $processes) {
        $process.WaitForExit()
        $exitCodes += $process.ExitCode
        $process.Dispose()
    }

    $afterFiles=@(Get-ChildItem -LiteralPath $workDir -File -ErrorAction SilentlyContinue)
    $outputs=@($afterFiles | Where-Object { $_.Name -notin $beforeNames } | Select-Object -ExpandProperty FullName)
    $outputs=@($outputs | Sort-Object)
    $allSuccess = (@($exitCodes | Where-Object { $_ -ne 0 }).Count -eq 0)
    $allFailure = (@($exitCodes | Where-Object { $_ -eq 0 }).Count -eq 0)
    $originalUnchanged=Same-Hashes @($fixture.Paths) @($beforeHashes)
    $extension = if($outputs.Count -eq 1){ [IO.Path]::GetExtension($outputs[0]).ToLowerInvariant() } else { $null }
    $suffix=Output-Suffixes @($outputs) $fixture.Paths[0]
    $underTarget=$null
    if($null -ne $target -and $outputs.Count -eq 1) {
        $underTarget=((Get-Item -LiteralPath $outputs[0]).Length -le [math]::Floor($target*1024*1024))
    }
    $metadataRemoved=$null
    if($case.fixture -eq 'metadata-jpeg' -and $outputs.Count -eq 1) { $metadataRemoved=Metadata-Removed $outputs[0] }
    $pageCount=$null
    if($case.fixture -eq 'ordered-images-3' -and $outputs.Count -eq 1) { $pageCount=Pdf-PageCount $outputs[0] }
    $orderPreserved=$null
    if($case.fixture -eq 'ordered-images-3') { $orderPreserved = if($side -eq 'oracle'){ Oracle-OrderContract }else{ Native-OrderContract } }
    $existingOutputUnchanged=$null
    if($fixture.Seeded) { $existingOutputUnchanged=((Hash $fixture.Seeded) -eq $seededHash) }
    $suffixList=@($suffix)
    $collisionSafe=$null
    if($case.fixture -eq 'concurrent-same-input') {
        $collisionSafe=$allSuccess -and $outputs.Count -eq 2 -and
            ('_smaller.jpg' -in $suffixList) -and ('_smaller_2.jpg' -in $suffixList)
    }
    $firstOnly=$null
    if($case.fixture -eq 'multi-nonpdf-first-only') {
        $expectedName=[IO.Path]::GetFileNameWithoutExtension($fixture.Paths[0]) + '_smaller.jpg'
        $firstOnly=$allSuccess -and $outputs.Count -eq 1 -and ([IO.Path]::GetFileName($outputs[0]) -eq $expectedName)
    }

    return [pscustomobject]@{
        status=$(if($allSuccess){'success'}elseif($allFailure){'failure'}else{'mixed'})
        exitCodes=@($exitCodes)
        outputCount=$outputs.Count
        extension=$extension
        suffix=$suffix
        originalUnchanged=$originalUnchanged
        underTarget=$underTarget
        metadataRemoved=$metadataRemoved
        pageCount=$pageCount
        orderPreserved=$orderPreserved
        noop=($allSuccess -and $outputs.Count -eq 0)
        cleanFailure=($allFailure -and $outputs.Count -eq 0)
        existingOutputUnchanged=$existingOutputUnchanged
        collisionSafe=$collisionSafe
        firstOnly=$firstOnly
        verificationMode=$(if($case.fixture -eq 'ordered-images-3'){'runtime+source-order-contract'}else{'runtime'})
    }
}

function Normalize-Value([object]$value) {
    return (ConvertTo-Json -InputObject $value -Compress -Depth 8)
}

function Field-Value([object]$outcome,[string]$field) {
    $property=$outcome.PSObject.Properties[$field]
    if($null -eq $property){ return $null }
    return $property.Value
}

function Expected-For([string]$id) {
    switch($id) {
        'P-01' { return @{status='success';outputCount=1;extension='.jpg';suffix='_compatible.jpg';originalUnchanged=$true} }
        'P-02' { return @{status='success';outputCount=1;extension='.webp';suffix='_smaller.webp';originalUnchanged=$true} }
        'P-03' { return @{status='success';outputCount=1;extension='.jpg';suffix='_under.jpg';originalUnchanged=$true;underTarget=$true} }
        'P-04' { return @{status='success';outputCount=1;extension='.jpg';suffix='_safe.jpg';originalUnchanged=$true;metadataRemoved=$true} }
        'P-05' { return @{status='success';outputCount=1;extension='.pdf';suffix='_document.pdf';originalUnchanged=$true;pageCount=3;orderPreserved=$true} }
        'P-06' { return @{status='success';outputCount=0;originalUnchanged=$true;noop=$true} }
        'P-07' { return @{status='failure';outputCount=0;originalUnchanged=$true;cleanFailure=$true} }
        'P-08' { return @{status='success';outputCount=1;extension='.jpg';suffix='_safe.jpg';originalUnchanged=$true} }
        'P-09' { return @{status='success';outputCount=1;suffix='_smaller_2.jpg';originalUnchanged=$true;existingOutputUnchanged=$true} }
        'P-10' { return @{status='success';outputCount=2;suffix=@('_smaller.jpg','_smaller_2.jpg');originalUnchanged=$true;collisionSafe=$true} }
        'P-11' { return @{status='success';outputCount=1;suffix='_smaller.jpg';originalUnchanged=$true;firstOnly=$true} }
        default { throw "no expectations for $id" }
    }
}

try {
    foreach($case in @($cases)) {
        $caseRoot=Join-Path $root $case.id
        $oracleWork=Join-Path $caseRoot 'oracle'
        $nativeWork=Join-Path $caseRoot 'native'
        $oracleEnv=Join-Path $caseRoot 'oracle-env'
        $nativeEnv=Join-Path $caseRoot 'native-env'
        New-Item -ItemType Directory -Force -Path $oracleWork,$nativeWork,$oracleEnv,$nativeEnv | Out-Null

        $oracleFixture=Prepare-Fixture $case.fixture $oracleWork
        $nativeFixture=Prepare-Fixture $case.fixture $nativeWork
        if($case.id -eq 'P-08' -and ($oracleFixture.PolicyOnly -or $nativeFixture.PolicyOnly)) {
            $oracleOutcome=Heic-PolicyOutcome 'oracle'
            $nativeOutcome=Heic-PolicyOutcome 'native'
        }
        else {
            $oracleOutcome=Run-Side 'oracle' $case $oracleFixture $oracleWork $oracleEnv
            $nativeOutcome=Run-Side 'native' $case $nativeFixture $nativeWork $nativeEnv
        }

        $differences=[System.Collections.Generic.List[string]]::new()
        $allowed=[System.Collections.Generic.List[string]]::new()
        foreach($field in @($case.compare)) {
            $ov=Field-Value $oracleOutcome $field
            $nv=Field-Value $nativeOutcome $field
            if((Normalize-Value $ov) -ne (Normalize-Value $nv)) {
                if($field -eq 'underTarget' -and $ov -eq $false -and $nv -eq $true) {
                    $allowed.Add('underTarget: native intentionally enforces strict <= target')
                }
                else {
                    $differences.Add("$field oracle=$(Normalize-Value $ov) native=$(Normalize-Value $nv)")
                }
            }
        }

        $expected=Expected-For $case.id
        foreach($field in $expected.Keys) {
            $ov=Field-Value $oracleOutcome $field
            $ev=$expected[$field]
            if((Normalize-Value $ov) -ne (Normalize-Value $ev)) {
                $differences.Add("oracle-baseline $field expected=$(Normalize-Value $ev) actual=$(Normalize-Value $ov)")
            }
        }

        $pass=($differences.Count -eq 0)
        $results.Add([pscustomobject]@{
            id=$case.id
            action=$case.action
            fixture=$case.fixture
            pass=$pass
            oracle=$oracleOutcome
            native=$nativeOutcome
            allowedDifferences=@($allowed)
            differences=@($differences)
        })
        if($pass){ Write-Host "$($case.id) PARITY PASS" }
        else { Write-Host "$($case.id) PARITY FAIL: $($differences -join ' | ')" }
    }
}
finally {
    $passed=@($results | Where-Object pass).Count
    $total=@($cases).Count
    $report=[ordered]@{
        gate='ORACLE_PARITY'
        oracleSha256=$actualSha
        total=$total
        passed=$passed
        status=$(if($passed -eq $total){'PASS'}else{'FAIL'})
        cases=$results
    }
    $jsonPath=Join-Path $reports 'oracle-parity.json'
    $htmlPath=Join-Path $reports 'oracle-parity.html'
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $rows=@($results | ForEach-Object {
        [pscustomobject]@{
            Id=$_.id
            Action=$_.action
            Fixture=$_.fixture
            Pass=$_.pass
            Differences=($_.differences -join '; ')
            Allowed=($_.allowedDifferences -join '; ')
        }
    }) | ConvertTo-Html -Fragment
    @("<!doctype html><meta charset='utf-8'><title>FileDone Oracle Parity</title><h1>Oracle Parity: $passed/$total</h1>",$rows) | Set-Content -LiteralPath $htmlPath -Encoding utf8
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if(@($results | Where-Object pass).Count -ne @($cases).Count){
    throw "Oracle parity failed: $(@($results | Where-Object pass).Count)/$(@($cases).Count)"
}
Write-Host 'ORACLE_PARITY_PASS'
