param(
    [Parameter(Mandatory=$true)][string]$SourceMsix,
    [Parameter(Mandatory=$true)][string]$IdentityName,
    [Parameter(Mandatory=$true)][string]$Publisher,
    [Parameter(Mandatory=$true)][string]$PublisherDisplayName,
    [string]$Version = '2.0.1.0',
    [string]$DisplayName = 'FileDone',
    [string]$OutputDirectory = 'artifacts/store-rc',
    [string]$ExpectedSourceSha256 = '6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-StoreVersion([string]$Value) {
    $parts=$Value.Split('.')
    if($parts.Count -ne 4){ throw "Store version must have four parts: $Value" }
    $nums=@()
    foreach($part in $parts){
        $n=0
        if(-not [int]::TryParse($part,[ref]$n)){ throw "Store version contains a non-integer part: $Value" }
        if($n -lt 0 -or $n -gt 65535){ throw "Store version part out of range 0..65535: $Value" }
        $nums += $n
    }
    if($nums[0] -eq 0){ throw "Store version Major must be non-zero: $Value" }
    if($nums[3] -ne 0){ throw "Store version Revision must be 0 for Windows 10/11 Store packages: $Value" }
}

Assert-StoreVersion $Version
if($IdentityName -notmatch '^[A-Za-z0-9.-]{3,50}$' -or $IdentityName.EndsWith('.')){
    throw "Invalid Store Package/Identity/Name: $IdentityName"
}
if([string]::IsNullOrWhiteSpace($Publisher)){ throw 'Store Publisher is required.' }
if([string]::IsNullOrWhiteSpace($PublisherDisplayName)){ throw 'Store PublisherDisplayName is required.' }
if([string]::IsNullOrWhiteSpace($DisplayName)){ throw 'Store DisplayName is required.' }
if($IdentityName -match 'QA|SelfTest' -or $Publisher -match 'FileDone QA'){
    throw 'Real Store identity must not contain QA/test identity values.'
}

$SourceMsix=(Resolve-Path -LiteralPath $SourceMsix -ErrorAction Stop).Path
$sourceHash=(Get-FileHash -LiteralPath $SourceMsix -Algorithm SHA256).Hash.ToUpperInvariant()
$sourceBytes=(Get-Item -LiteralPath $SourceMsix).Length
if($ExpectedSourceSha256 -and $sourceHash -ne $ExpectedSourceSha256.ToUpperInvariant()){
    throw "Shipping MSIX authority mismatch expected=$ExpectedSourceSha256 actual=$sourceHash"
}

$sdkBin=Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64' } |
    Where-Object { Test-Path (Join-Path $_ 'makeappx.exe') } |
    Select-Object -First 1
if(!$sdkBin){ throw 'Windows SDK makeappx.exe not found.' }
$makeappx=Join-Path $sdkBin 'makeappx.exe'

$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$work=Join-Path $OutputDirectory '_work'
$sourceRoot=Join-Path $work 'source'
$verifyRoot=Join-Path $work 'verify'
$uploadRoot=Join-Path $work 'upload'
Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OutputDirectory,$sourceRoot,$verifyRoot,$uploadRoot | Out-Null

& $makeappx unpack /p $SourceMsix /d $sourceRoot /o
if($LASTEXITCODE -ne 0){ throw "makeappx unpack source failed: $LASTEXITCODE" }

$payloadBefore=[ordered]@{}
Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
    $rel=$_.FullName.Substring($sourceRoot.Length).TrimStart('\')
    if($rel -notin @('AppxManifest.xml','AppxBlockMap.xml','AppxSignature.p7x','[Content_Types].xml')){
        $payloadBefore[$rel]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    }
}

$manifestPath=Join-Path $sourceRoot 'AppxManifest.xml'
[xml]$xml=Get-Content -LiteralPath $manifestPath -Raw
$ns=[Xml.XmlNamespaceManager]::new($xml.NameTable)
$ns.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$ns.AddNamespace('uap','http://schemas.microsoft.com/appx/manifest/uap/windows10')
$ns.AddNamespace('rescap','http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities')
$ns.AddNamespace('desktop4','http://schemas.microsoft.com/appx/manifest/desktop/windows10/4')
$ns.AddNamespace('desktop5','http://schemas.microsoft.com/appx/manifest/desktop/windows10/5')

$identity=$xml.SelectSingleNode('/f:Package/f:Identity',$ns)
$properties=$xml.SelectSingleNode('/f:Package/f:Properties',$ns)
$visual=$xml.SelectSingleNode('/f:Package/f:Applications/f:Application/uap:VisualElements',$ns)
if(!$identity -or !$properties -or !$visual){ throw 'Required manifest nodes are missing.' }

$identity.SetAttribute('Name',$IdentityName)
$identity.SetAttribute('Publisher',$Publisher)
$identity.SetAttribute('Version',$Version)
$properties.SelectSingleNode('f:DisplayName',$ns).InnerText=$DisplayName
$properties.SelectSingleNode('f:PublisherDisplayName',$ns).InnerText=$PublisherDisplayName
$properties.SelectSingleNode('f:Description',$ns).InnerText=$DisplayName
$visual.SetAttribute('DisplayName',$DisplayName)
$visual.SetAttribute('Description',$DisplayName)

$fullTrust=$xml.SelectSingleNode('/f:Package/f:Capabilities/rescap:Capability[@Name="runFullTrust"]',$ns)
$contextMenu=$xml.SelectSingleNode('/f:Package/f:Applications/f:Application/f:Extensions/desktop4:Extension[@Category="windows.fileExplorerContextMenus"]/desktop4:FileExplorerContextMenus/desktop5:ItemType/desktop5:Verb',$ns)
if(!$fullTrust){ throw 'Store manifest lost runFullTrust capability.' }
if(!$contextMenu){ throw 'Store manifest lost windows.fileExplorerContextMenus registration.' }
if($contextMenu.GetAttribute('Clsid') -ne '72E5C740-AB37-4FD8-94E8-4DE0ECA292B5'){ throw 'Store manifest shell CLSID changed.' }

$settings=[Xml.XmlWriterSettings]::new()
$settings.Encoding=[Text.UTF8Encoding]::new($false)
$settings.Indent=$true
$writer=[Xml.XmlWriter]::Create($manifestPath,$settings)
try { $xml.Save($writer) } finally { $writer.Dispose() }

$manifestText=Get-Content -LiteralPath $manifestPath -Raw
foreach($forbidden in @('FileDone.QAUnsigned','FileDone.QATestSigned','CN=FileDone QA','QA Root','QA Test')){
    if($manifestText -match [regex]::Escape($forbidden)){ throw "QA residue remains in Store manifest: $forbidden" }
}

Remove-Item -LiteralPath (Join-Path $sourceRoot 'AppxBlockMap.xml') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $sourceRoot 'AppxSignature.p7x') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $sourceRoot '[Content_Types].xml') -Force -ErrorAction SilentlyContinue

$msixName='FileDone_' + $Version + '_x64_Store.msix'
$msix=Join-Path $OutputDirectory $msixName
& $makeappx pack /d $sourceRoot /p $msix /o
if($LASTEXITCODE -ne 0){ throw "makeappx Store pack failed: $LASTEXITCODE" }
if(!(Test-Path -LiteralPath $msix -PathType Leaf)){ throw 'Store MSIX was not created.' }

& $makeappx unpack /p $msix /d $verifyRoot /o
if($LASTEXITCODE -ne 0){ throw "makeappx Store verify unpack failed: $LASTEXITCODE" }
if(Test-Path -LiteralPath (Join-Path $verifyRoot 'AppxSignature.p7x')){ throw 'Store RC unexpectedly contains an AppxSignature.p7x.' }

[xml]$verifyXml=Get-Content -LiteralPath (Join-Path $verifyRoot 'AppxManifest.xml') -Raw
$verifyNs=[Xml.XmlNamespaceManager]::new($verifyXml.NameTable)
$verifyNs.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$verifyIdentity=$verifyXml.SelectSingleNode('/f:Package/f:Identity',$verifyNs)
$verifyProps=$verifyXml.SelectSingleNode('/f:Package/f:Properties',$verifyNs)
if($verifyIdentity.GetAttribute('Name') -ne $IdentityName){ throw 'Packed Store identity Name mismatch.' }
if($verifyIdentity.GetAttribute('Publisher') -ne $Publisher){ throw 'Packed Store Publisher mismatch.' }
if($verifyIdentity.GetAttribute('Version') -ne $Version){ throw 'Packed Store Version mismatch.' }
if($verifyProps.SelectSingleNode('f:PublisherDisplayName',$verifyNs).InnerText -ne $PublisherDisplayName){ throw 'Packed Store PublisherDisplayName mismatch.' }

foreach($rel in $payloadBefore.Keys){
    $p=Join-Path $verifyRoot $rel
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){ throw "Store payload missing: $rel" }
    $after=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant()
    if($after -ne $payloadBefore[$rel]){ throw "Store packaging mutated shipping payload: $rel" }
}
$dangerous=@(Get-ChildItem -LiteralPath $verifyRoot -Recurse -File | Where-Object { $_.Extension -in @('.pfx','.p12','.cer','.key','.pem') })
if($dangerous.Count -gt 0){ throw 'Certificate/private-key material must not be inside the Store package.' }

Copy-Item -LiteralPath $msix -Destination (Join-Path $uploadRoot $msixName) -Force
$zip=Join-Path $work 'FileDone-Store.zip'
$uploadName='FileDone_' + $Version + '_x64.msixupload'
$upload=Join-Path $OutputDirectory $uploadName
Compress-Archive -LiteralPath (Join-Path $uploadRoot $msixName) -DestinationPath $zip -CompressionLevel Optimal -Force
Move-Item -LiteralPath $zip -Destination $upload -Force

$msixHash=(Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash.ToUpperInvariant()
$uploadHash=(Get-FileHash -LiteralPath $upload -Algorithm SHA256).Hash.ToUpperInvariant()
$evidence=[ordered]@{
    status='PASS'
    gate='FILEDONE_STORE_RC_PACKAGE'
    sourceShippingMsixSha256=$sourceHash
    sourceShippingMsixBytes=$sourceBytes
    identityName=$IdentityName
    publisher=$Publisher
    publisherDisplayName=$PublisherDisplayName
    displayName=$DisplayName
    version=$Version
    processorArchitecture=$verifyIdentity.GetAttribute('ProcessorArchitecture')
    msix=$msixName
    msixSha256=$msixHash
    msixBytes=(Get-Item -LiteralPath $msix).Length
    msixupload=$uploadName
    msixuploadSha256=$uploadHash
    msixuploadBytes=(Get-Item -LiteralPath $upload).Length
    payloadFileCount=$payloadBefore.Count
    payloadHashes=$payloadBefore
    qaResidue=$false
    signedByDeveloper=$false
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'STORE_RC_AUTHORITY.json') -Encoding utf8

Remove-Item -LiteralPath $work -Recurse -Force
Write-Host "FILEDONE_STORE_IDENTITY_PASS NAME=$IdentityName VERSION=$Version"
Write-Host "FILEDONE_STORE_PAYLOAD_PARITY_PASS FILES=$($payloadBefore.Count)"
Write-Host "FILEDONE_STORE_NO_QA_RESIDUE_PASS"
Write-Host "FILEDONE_STORE_MSIXUPLOAD_PASS SHA256=$uploadHash"
Write-Host "FILEDONE_STORE_RC_PACKAGE_PASS MSIX_SHA256=$msixHash"
