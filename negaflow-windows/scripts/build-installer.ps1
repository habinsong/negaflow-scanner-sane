[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [string]$VcpkgRoot,

    [string]$MsysRoot = 'C:\msys64',

    [string]$OutputDirectory,

    [switch]$SkipTests,

    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot

if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    foreach ($candidate in @(
        $env:VCPKG_ROOT,
        $env:VCPKG_INSTALLATION_ROOT,
        'C:\vcpkg',
        'C:\Program Files\Microsoft Visual Studio\18\Community\VC\vcpkg')) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'scripts\buildsystems\vcpkg.cmake'))) {
            $VcpkgRoot = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    throw 'vcpkg was not found. Pass -VcpkgRoot or set VCPKG_ROOT.'
}
$VcpkgRoot = [System.IO.Path]::GetFullPath($VcpkgRoot)
$toolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
if (-not (Test-Path -LiteralPath $toolchain -PathType Leaf)) {
    throw "vcpkg toolchain is missing: $toolchain"
}

$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$cygpath = Join-Path $MsysRoot 'usr\bin\cygpath.exe'
$scanimage = Join-Path $MsysRoot 'ucrt64\bin\scanimage.exe'
$makensis = 'C:\Program Files (x86)\NSIS\makensis.exe'
foreach ($required in @($bash, $cygpath, $scanimage, $makensis)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "MSYS2 UCRT64 SANE runtime is missing: $required"
    }
}

$buildDirectory = Join-Path $projectRoot 'out\build'
$plugin = Join-Path $buildDirectory "$Configuration\negaflow-scanner-sane.exe"
$manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'negaflow-mac\manifest.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$version = [string]$manifest.pluginVersion
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "manifest.json has an invalid pluginVersion: '$version'"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'out\release\x64'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$installerName = "negaflow-scanner-sane-$version-x64-setup.exe"
$installer = Join-Path $OutputDirectory $installerName
if ((Test-Path -LiteralPath $installer) -and -not $Overwrite) {
    throw "Installer already exists: $installer. Pass -Overwrite to replace this release artifact."
}

& cmake -S $projectRoot -B $buildDirectory -A x64 "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
    '-DVCPKG_TARGET_TRIPLET=x64-windows-static'
if ($LASTEXITCODE -ne 0) {
    throw 'CMake configure failed.'
}
& cmake --build $buildDirectory --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) {
    throw "CMake $Configuration build failed."
}
if (-not $SkipTests) {
    & ctest --test-dir $buildDirectory -C $Configuration --output-on-failure
    if ($LASTEXITCODE -ne 0) {
        throw "CTest $Configuration failed."
    }
}
if (-not (Test-Path -LiteralPath $plugin -PathType Leaf)) {
    throw "Plugin executable is missing: $plugin"
}

$installerDirectory = Join-Path $repositoryRoot 'negaflow-mac\Installer\windows'
$makeInstaller = Join-Path $installerDirectory 'make-installer.sh'
$posixScript = (& $cygpath -u $makeInstaller).Trim()
$posixPlugin = (& $cygpath -u $plugin).Trim()
$posixMakensis = (& $cygpath -u $makensis).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'cygpath could not convert the installer paths.'
}
& $bash -lc "MINGW_PREFIX=/ucrt64 MAKENSIS='$posixMakensis' '$posixScript' '$posixPlugin'"
if ($LASTEXITCODE -ne 0) {
    throw 'SANE installer assembly failed.'
}

$generated = Join-Path $installerDirectory $installerName
if (-not (Test-Path -LiteralPath $generated -PathType Leaf)) {
    throw "Installer script did not create: $generated"
}
Copy-Item -LiteralPath $generated -Destination $installer -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$installer.sha256" -Encoding ASCII -NoNewline -Value "$hash *$installerName`n"
Write-Host "Installer: $installer" -ForegroundColor Green
Write-Host "SHA-256: $hash" -ForegroundColor Green
