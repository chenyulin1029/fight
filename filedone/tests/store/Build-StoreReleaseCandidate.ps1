param(
  [Parameter(Mandatory=$true)][string]$SourceMsix,
  [Parameter(Mandatory=$true)][string]$OutputMsix,
  [Parameter(Mandatory=$true)][string]$IdentityName,
  [Parameter(Mandatory=$true)][string]$Publisher,
  [Parameter(Mandatory=$true)][string]$PublisherDisplayName,
  [Parameter(Mandatory=$true)][string]$StoreEntryExe,
  [Parameter(Mandatory=$true)][string]$Version,
  [switch]$Preview,
  [switch]$RunWack,
  [string]$EvidencePath
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$ShippingAuthorityHash='6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE'
$ShippingAuthorityBytes=33940809
$ExpectedPayloadHashes=[ordered]@{
  'FileDoneRuntime.exe'='6CEDE760ADDEBC70AD15E45B79D95577FB3E3AEB0985D405811D6251F0203FC5'
  'FileDoneShellNative.dll'=$null
  'tools\ffmpeg.exe'='30A6C3141FE2E8994DA0B83A50A530ABD782F0085D6A63C83173A396C96D5549'
  'tools\ffprobe.exe'='7A4F1AED91D6E1B90A966818EB7B1DC8AB091124ACFA52F681763EC5D8041AB7'
  'tools\magick.exe'='2E3173334814B95D72190700D83C571601188B4AB47F3251DCC8ACC76C2A739A'
}

if($Version -notmatch '^([1-9]\d{0,4})\.(\d{1,5})\.(\d{1,5})\.0$'){ throw 'Store version must be A.B.C.0 with nonzero first component and fourth component reserved as 0.' }
$parts=$Version.Split('.') | ForEach-Object {[int]$_}
if($parts | Where-Object { $_ -gt 65535 }){ throw 'Store version components must be <= 65535.' }
if([string]::IsNullOrWhiteSpace($IdentityName)){ throw 'IdentityName is required.' }
if([string]::IsNullOrWhiteSpace($Publisher)){ throw 'Publisher is required.' }
if([string]::IsNullOrWhiteSpace($PublisherDisplayName)){ throw 'PublisherDisplayName is required.' }
if(!$Preview){
  if($IdentityName -match '(?i)QA|Preview|Unsigned'){ throw 'Final Store package identity still looks like QA/Preview/Unsigned.' }
  if($Publisher -match '(?i)QA Test|Store Preview'){ throw 'Final Store publisher still looks like a test publisher.' }
}

$SourceMsix=(Resolve-Path -LiteralPath $SourceMsix -ErrorAction Stop).Path
$StoreEntryExe=(Resolve-Path -LiteralPath $StoreEntryExe -ErrorAction Stop).Path
$storeEntryHash=(Get-FileHash -LiteralPath $StoreEntryExe -Algorithm SHA256).Hash.ToUpperInvariant()
$sourceHash=(Get-FileHash -LiteralPath $SourceMsix -Algorithm SHA256).Hash.ToUpperInvariant()
$sourceBytes=(Get-Item -LiteralPath $SourceMsix).Length
if($sourceHash -ne $ShippingAuthorityHash){ throw "shipping MSIX authority hash mismatch expected=$ShippingAuthorityHash actual=$sourceHash" }
if($sourceBytes -ne $ShippingAuthorityBytes){ throw "shipping MSIX authority size mismatch expected=$ShippingAuthorityBytes actual=$sourceBytes" }

$sdkBin=Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64' } | Where-Object { (Test-Path (Join-Path $_ 'makeappx.exe')) -and (Test-Path (Join-Path $_ 'signtool.exe')) } | Select-Object -First 1
if(!$sdkBin){ throw 'Windows SDK MakeAppx/SignTool not found.' }
$makeappx=Join-Path $sdkBin 'makeappx.exe'
$signtool=Join-Path $sdkBin 'signtool.exe'

$outDir=Split-Path -Parent $OutputMsix
if([string]::IsNullOrWhiteSpace($outDir)){ $outDir=(Get-Location).Path }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$OutputMsix=[IO.Path]::GetFullPath($OutputMsix)
if([string]::IsNullOrWhiteSpace($EvidencePath)){ $EvidencePath=Join-Path $outDir 'store-rc-evidence.json' }
$EvidencePath=[IO.Path]::GetFullPath($EvidencePath)
$work=Join-Path $outDir '_store_rc_work'
$verify=Join-Path $outDir '_store_rc_verify'
Remove-Item -LiteralPath $work,$verify -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $OutputMsix -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null

& $makeappx unpack /p $SourceMsix /d $work /o
if($LASTEXITCODE -ne 0){ throw "MakeAppx unpack failed: $LASTEXITCODE" }

$before=[ordered]@{}
foreach($rel in $ExpectedPayloadHashes.Keys){
  $p=Join-Path $work $rel
  if(!(Test-Path -LiteralPath $p -PathType Leaf)){ throw "shipping payload missing before Store repack: $rel" }
  $h=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant()
  $before[$rel]=$h
  if($ExpectedPayloadHashes[$rel] -and $h -ne $ExpectedPayloadHashes[$rel]){ throw "shipping payload authority mismatch: $rel $h" }
}

Remove-Item -LiteralPath (Join-Path $work 'FileDoneBridge.exe') -Force -ErrorAction Stop
Copy-Item -LiteralPath $StoreEntryExe -Destination (Join-Path $work 'FileDoneStoreEntry.exe') -Force

$manifest=Join-Path $work 'AppxManifest.xml'
[xml]$xml=Get-Content -LiteralPath $manifest -Raw
$ns=[Xml.XmlNamespaceManager]::new($xml.NameTable)
$ns.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$application=$xml.SelectSingleNode('/f:Package/f:Applications/f:Application',$ns)
$identity=$xml.SelectSingleNode('/f:Package/f:Identity',$ns)
$props=$xml.SelectSingleNode('/f:Package/f:Properties',$ns)
if(!$identity -or !$props -or !$application){ throw 'Store manifest Identity/Properties/Application missing.' }
$identity.SetAttribute('Name',$IdentityName)
$identity.SetAttribute('Publisher',$Publisher)
$identity.SetAttribute('Version',$Version)
$identity.SetAttribute('ProcessorArchitecture','x64')
$application.SetAttribute('Executable','FileDoneStoreEntry.exe')
$publisherNode=$props.SelectSingleNode('f:PublisherDisplayName',$ns)
if(!$publisherNode){ throw 'PublisherDisplayName missing.' }
$publisherNode.InnerText=$PublisherDisplayName

$settings=[Xml.XmlWriterSettings]::new()
$settings.Encoding=[Text.UTF8Encoding]::new($false)
$settings.Indent=$true
$writer=[Xml.XmlWriter]::Create($manifest,$settings)
try { $xml.Save($writer) } finally { $writer.Dispose() }

Remove-Item -LiteralPath (Join-Path $work 'AppxBlockMap.xml') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $work 'AppxSignature.p7x') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $work '[Content_Types].xml') -Force -ErrorAction SilentlyContinue

& $makeappx pack /d $work /p $OutputMsix /o
if($LASTEXITCODE -ne 0){ throw "MakeAppx Store pack failed: $LASTEXITCODE" }

$cert=$null; $trusted=$null; $pfx=$null
try {
  $cert=New-SelfSignedCertificate -Type Custom -Subject $Publisher -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy Exportable -KeyUsage DigitalSignature -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={critical}{text}CA=false') -FriendlyName 'FileDone Store RC Ephemeral Signer' -NotAfter (Get-Date).AddDays(14)
  $cer=Join-Path $outDir 'FileDone-Store-RC-Signer.cer'
  Export-Certificate -Cert $cert -FilePath $cer | Out-Null
  $trusted=Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction Stop
  $pwPlain=[Guid]::NewGuid().ToString('N')
  $pw=ConvertTo-SecureString -String $pwPlain -Force -AsPlainText
  $pfx=Join-Path $outDir '_store_rc_signer.pfx'
  Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pw -ChainOption EndEntityCertOnly | Out-Null
  & $signtool sign /fd SHA256 /f $pfx /p $pwPlain $OutputMsix
  if($LASTEXITCODE -ne 0){ throw "SignTool Store RC sign failed: $LASTEXITCODE" }
  & $signtool verify /pa /v $OutputMsix
  if($LASTEXITCODE -ne 0){ throw "SignTool Store RC verify failed: $LASTEXITCODE" }

  New-Item -ItemType Directory -Force -Path $verify | Out-Null
  & $makeappx unpack /p $OutputMsix /d $verify /o
  if($LASTEXITCODE -ne 0){ throw "MakeAppx Store verify unpack failed: $LASTEXITCODE" }
  [xml]$vx=Get-Content -LiteralPath (Join-Path $verify 'AppxManifest.xml') -Raw
  $vns=[Xml.XmlNamespaceManager]::new($vx.NameTable)
  $vns.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
  $vi=$vx.SelectSingleNode('/f:Package/f:Identity',$vns)
  if($vi.Name -ne $IdentityName -or $vi.Publisher -ne $Publisher -or $vi.Version -ne $Version -or $vi.ProcessorArchitecture -ne 'x64'){ throw 'packed Store manifest identity mismatch.' }
$va=$vx.SelectSingleNode('/f:Package/f:Applications/f:Application',$vns)
if(!$va -or $va.GetAttribute('Executable') -ne 'FileDoneStoreEntry.exe'){ throw 'packed Store Application executable mismatch.' }
$entryPath=Join-Path $verify 'FileDoneStoreEntry.exe'
if(!(Test-Path -LiteralPath $entryPath -PathType Leaf)){ throw 'Store entry executable missing.' }
if((Get-FileHash -LiteralPath $entryPath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $storeEntryHash){ throw 'Store entry executable hash mismatch.' }
if(Test-Path -LiteralPath (Join-Path $verify 'FileDoneBridge.exe')){ throw 'Legacy FileDoneBridge.exe must not ship in Store RC.' }

  $after=[ordered]@{}
  foreach($rel in $before.Keys){
    $h=(Get-FileHash -LiteralPath (Join-Path $verify $rel) -Algorithm SHA256).Hash.ToUpperInvariant()
    $after[$rel]=$h
    if($h -ne $before[$rel]){ throw "Store repack mutated shipping payload: $rel" }
  }

  $wackStatus='EXTERNAL_REQUIRED'
  $wackReport=$null
  if($RunWack){
    $appcert='C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe'
    if(!(Test-Path -LiteralPath $appcert -PathType Leaf)){ throw 'Windows App Certification Kit appcert.exe not found.' }
    $wackReport=Join-Path $outDir 'WACK-report.xml'
    & $appcert reset | Out-Host
    if($LASTEXITCODE -ne 0){ throw "WACK reset failed: $LASTEXITCODE" }
    & $appcert test -appxpackagepath $OutputMsix -reportoutputpath $wackReport | Out-Host
    if($LASTEXITCODE -ne 0){ throw "WACK package test failed: $LASTEXITCODE" }
    if(!(Test-Path -LiteralPath $wackReport -PathType Leaf) -or (Get-Item $wackReport).Length -le 0){ throw 'WACK report missing or empty.' }
    $wackStatus='PASS'
    Write-Host 'FILEDONE_STORE_WACK_PASS'
  }

  $outHash=(Get-FileHash -LiteralPath $OutputMsix -Algorithm SHA256).Hash.ToUpperInvariant()
  $outBytes=(Get-Item -LiteralPath $OutputMsix).Length
  [ordered]@{
    status='PASS'; gate=if($Preview){'FILEDONE_STORE_RC_PREVIEW'}else{'FILEDONE_STORE_RC_SUBMISSION'};
    preview=[bool]$Preview; sourceShippingMsixSha256=$sourceHash; sourceShippingMsixBytes=$sourceBytes;
    identityName=$IdentityName; publisher=$Publisher; publisherDisplayName=$PublisherDisplayName; version=$Version; architecture='x64';
    outputMsix=(Split-Path -Leaf $OutputMsix); outputSha256=$outHash; outputBytes=$outBytes;
    payloadHashes=$after; storeEntryExe='FileDoneStoreEntry.exe'; storeEntrySha256=$storeEntryHash; legacyBridgeRemoved=$true;
    wack=$wackStatus; wackReport=if($wackReport){Split-Path -Leaf $wackReport}else{$null};
    storeSignaturePolicy='Ephemeral matching-publisher test signature; Microsoft Store re-signs MSIX after certification.'
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
  if($Preview){ Write-Host "FILEDONE_STORE_RC_PREVIEW_PASS SHA256=$outHash BYTES=$outBytes" } else { Write-Host "FILEDONE_STORE_RC_SUBMISSION_PACKAGE_PASS SHA256=$outHash BYTES=$outBytes" }
} finally {
  if($trusted){ Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Thumbprint -eq $cert.Thumbprint | Remove-Item -Force -ErrorAction SilentlyContinue }
  if($cert){ Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -eq $cert.Thumbprint | Remove-Item -Force -ErrorAction SilentlyContinue }
  if($pfx){ Remove-Item -LiteralPath $pfx -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $work,$verify -Recurse -Force -ErrorAction SilentlyContinue
}