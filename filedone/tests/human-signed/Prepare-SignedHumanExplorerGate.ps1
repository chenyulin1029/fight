param(
    [string]$PackagePath = (Join-Path $PSScriptRoot 'FileDone-P1.8B-QA-Signed.msix')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$authority=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SIGNED_GATE_AUTHORITY.json') -Raw | ConvertFrom-Json
$PackagePath=(Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
$actualHash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToUpperInvariant()
$actualBytes=(Get-Item -LiteralPath $PackagePath).Length
if($actualHash -ne ([string]$authority.signedMsixSha256).ToUpperInvariant()){ throw "signed MSIX hash mismatch expected=$($authority.signedMsixSha256) actual=$actualHash" }
if($actualBytes -ne [int64]$authority.signedMsixBytes){ throw "signed MSIX bytes mismatch expected=$($authority.signedMsixBytes) actual=$actualBytes" }
$certPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'FileDone-QA-Test.cer') -ErrorAction Stop).Path
$cert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
$trusted=Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint } | Select-Object -First 1
if(!$trusted){ throw 'FileDone QA test certificate is not trusted in LocalMachine TrustedPeople.' }
Get-AppxPackage -Name FileDone.QATestSigned -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
Add-AppxPackage -Path $PackagePath -ForceApplicationShutdown -ErrorAction Stop
$installed=Get-AppxPackage -Name FileDone.QATestSigned -ErrorAction Stop | Select-Object -First 1
if(!$installed){ throw 'FileDone.QATestSigned did not register for the current interactive user' }
foreach($required in @('FileDoneRuntime.exe','FileDoneShellNative.dll','tools\magick.exe','tools\ffmpeg.exe','tools\ffprobe.exe')){
    $p=Join-Path $installed.InstallLocation $required
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){ throw "installed payload missing: $required" }
}
$root=Join-Path $PSScriptRoot 'HUMAN_TEST_FILES'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null
Add-Type -AssemblyName System.Drawing
function New-TestImage([string]$Path,[int]$Width,[int]$Height,[string]$Format,[int]$Seed){
    $bmp=[System.Drawing.Bitmap]::new($Width,$Height)
    $g=[System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(240,244,248))
        $brush=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb((40+$Seed*17)%220,(90+$Seed*31)%220,(140+$Seed*43)%220))
        try {
            $g.FillRectangle($brush,20,20,[Math]::Max(20,$Width-40),[Math]::Max(20,$Height-40))
            $pen=[System.Drawing.Pen]::new([System.Drawing.Color]::White,[Math]::Max(2,[int]($Width/120)))
            try { for($i=0;$i -lt 8;$i++){ $x=30+[int](($Width-60)*$i/8); $g.DrawLine($pen,$x,30,$Width-$x,$Height-30) } } finally { $pen.Dispose() }
        } finally { $brush.Dispose() }
        if($Format -eq 'bmp'){ $bmp.Save($Path,[System.Drawing.Imaging.ImageFormat]::Bmp) } elseif($Format -eq 'png'){ $bmp.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png) } else { throw "unsupported test image format: $Format" }
    } finally { $g.Dispose(); $bmp.Dispose() }
}
New-TestImage (Join-Path $root '01_SINGLE_COMPATIBLE.bmp') 900 600 'bmp' 1
New-TestImage (Join-Path $root '02_SINGLE_SMALLER.png') 1800 1200 'png' 2
New-TestImage (Join-Path $root '03_SAFE_SHARE.png') 1200 800 'png' 3
New-TestImage (Join-Path $root '05_PDF_A.png') 900 1200 'png' 4
New-TestImage (Join-Path $root '05_PDF_B.png') 900 1200 'png' 5
New-TestImage (Join-Path $root '05_PDF_C.png') 900 1200 'png' 6
$ffmpeg=Join-Path $installed.InstallLocation 'tools\ffmpeg.exe'
$video=Join-Path $root '04_FIT_UNDER.mkv'
& $ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=1280x720:rate=30:duration=5' -f lavfi -i 'sine=frequency=880:sample_rate=48000:duration=5' -c:v ffv1 -level 3 -c:a pcm_s16le -shortest $video
if($LASTEXITCODE -ne 0){ throw "video fixture generation failed: $LASTEXITCODE" }
if(!(Test-Path -LiteralPath $video -PathType Leaf)){ throw 'video fixture missing' }
@'
FILEDONE P1.8B SIGNED HUMAN EXPLORER GATE

H1: Right-click 01_SINGLE_COMPATIBLE.bmp. FileDone must appear in the first Windows 11 menu.
H2: FileDone submenu must be exactly Make Compatible / Make Smaller / Fit Under... / Safe to Share / Make PDF.
H3: Run Make Compatible, Make Smaller, and Safe to Share on files 01/02/03.
H4: On 04_FIT_UNDER.mkv choose Fit Under..., enter 1, confirm output.
H5: Multi-select 05_PDF_A/B/C.png, Make PDF, confirm one 3-page PDF in selected order.
H6: Run CHECK_SIGNED_RESULTS.cmd and require FILEDONE_SIGNED_HUMAN_GATE_MACHINE_OUTPUTS_PASS.
'@ | Set-Content -LiteralPath (Join-Path $root '_START_HERE.txt') -Encoding utf8
[ordered]@{status='READY';gate='P1.8B_SIGNED_HUMAN_EXPLORER_GATE';package=$installed.Name;version=$installed.Version.ToString();packageFullName=$installed.PackageFullName;packageFamilyName=$installed.PackageFamilyName;installLocation=$installed.InstallLocation;signedMsixSha256=$actualHash;testFolder=$root;interactiveUser=[Security.Principal.WindowsIdentity]::GetCurrent().Name} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root '_GATE_INFO.json') -Encoding utf8
Write-Host "FILEDONE_SIGNED_PACKAGE_CURRENT_USER_INSTALL_PASS USER=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "FILEDONE_SIGNED_HUMAN_EXPLORER_GATE_READY FOLDER=$root"