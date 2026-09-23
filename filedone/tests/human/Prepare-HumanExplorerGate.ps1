param(
    [string]$PackagePath = (Join-Path $PSScriptRoot 'FileDone-P1.8B-Shipping-x64.msix')
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    throw 'Human Explorer Gate requires Administrator PowerShell because the unsigned MSIX contains executable activation. Launch RUN_HUMAN_EXPLORER_GATE.cmd and approve the UAC prompt.'
}
Write-Host 'FILEDONE_HUMAN_GATE_ADMIN_ELEVATION_PASS'

$expectedHash='6EEBA692EE6AA36718B6AE0AB68EEB928A9268E70880E33216252713996253BE'
$expectedBytes=33940809

$PackagePath=(Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
$actualHash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToUpperInvariant()
$actualBytes=(Get-Item -LiteralPath $PackagePath).Length
if($actualHash -ne $expectedHash){ throw "MSIX hash mismatch expected=$expectedHash actual=$actualHash" }
if($actualBytes -ne $expectedBytes){ throw "MSIX bytes mismatch expected=$expectedBytes actual=$actualBytes" }

Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -Name FileDone.DevShell -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue

Add-AppxPackage -Path $PackagePath -AllowUnsigned -ForceApplicationShutdown -ErrorAction Stop
$installed=Get-AppxPackage -Name FileDone.QAUnsigned -ErrorAction Stop | Select-Object -First 1
if(!$installed){ throw 'FileDone.QAUnsigned did not register' }

foreach($required in @('FileDoneRuntime.exe','FileDoneShellNative.dll','tools\magick.exe','tools\ffmpeg.exe','tools\ffprobe.exe')){
    $p=Join-Path $installed.InstallLocation $required
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){ throw "installed payload missing: $required" }
}

$desktop=[Environment]::GetFolderPath('Desktop')
if([string]::IsNullOrWhiteSpace($desktop)){ $desktop=Join-Path $env:USERPROFILE 'Desktop' }
$root=Join-Path $desktop 'FileDone_P1_8B_HUMAN_GATE'
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
            try {
                for($i=0;$i -lt 8;$i++){
                    $x=30+[int](($Width-60)*$i/8)
                    $g.DrawLine($pen,$x,30,$Width-$x,$Height-30)
                }
            } finally { $pen.Dispose() }
        } finally { $brush.Dispose() }

        if($Format -eq 'bmp'){ $bmp.Save($Path,[System.Drawing.Imaging.ImageFormat]::Bmp) }
        elseif($Format -eq 'png'){ $bmp.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png) }
        else { throw "unsupported test image format: $Format" }
    } finally {
        $g.Dispose()
        $bmp.Dispose()
    }
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

$checklist=@'
FILEDONE P1.8B HUMAN EXPLORER GATE

H1 — Modern Explorer menu
Right-click 01_SINGLE_COMPATIBLE.bmp.
PASS only if FileDone is visible in the normal Windows 11 right-click menu.
If it appears only under "Show more options", report FAIL.

H2 — Exact submenu
Open FileDone. It must show exactly:
1. Make Compatible
2. Make Smaller
3. Fit Under...
4. Safe to Share
5. Make PDF

H3 — Single-file actions
01_SINGLE_COMPATIBLE.bmp -> FileDone -> Make Compatible
02_SINGLE_SMALLER.png -> FileDone -> Make Smaller
03_SAFE_SHARE.png -> FileDone -> Safe to Share

H4 — Fit Under UI
04_FIT_UNDER.mkv -> FileDone -> Fit Under...
The dialog must open normally. Enter: 1
Press OK and wait for the output MP4.

H5 — Multi-selection Make PDF
Select 05_PDF_A.png + 05_PDF_B.png + 05_PDF_C.png together.
Right-click the selection -> FileDone -> Make PDF.
Exactly one new PDF should be produced.
Open it and confirm it contains 3 pages in the selected order.

H6 — Automated result check
Double-click CHECK_RESULTS.cmd from the downloaded Human Gate bundle.
It must report FILEDONE_HUMAN_GATE_MACHINE_OUTPUTS_PASS.

After reporting the Human results, CLEANUP_AFTER_GATE.cmd removes the package.
'@
$startHere=Join-Path $root '_START_HERE.txt'
$checklist | Set-Content -LiteralPath $startHere -Encoding utf8

[ordered]@{
    status='READY'
    gate='P1.8B_HUMAN_EXPLORER_GATE'
    msixSha256=$actualHash
    msixBytes=$actualBytes
    package=$installed.Name
    version=$installed.Version.ToString()
    installLocation=$installed.InstallLocation
    testFolder=$root
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root '_GATE_INFO.json') -Encoding utf8

Write-Host "FILEDONE_HUMAN_EXPLORER_GATE_READY FOLDER=$root"
Start-Process explorer.exe -ArgumentList "/select,`"$startHere`""
