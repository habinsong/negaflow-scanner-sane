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
# 브랜딩 비트맵은 Pillow 로 굽는다. MSYS 의 python3 에는 Pillow 가 없고, `bash -lc` 는
# 로그인 셸이라 PATH 를 새로 짜서 Windows 의 `py` 런처도 사라진다 — 그 자리에서
# `py: command not found` 로 설치 프로그램 조립이 멈췄다. 여기서 찾은 Windows Python 을
# 그대로 넘긴다.
# **런처가 아니라 실제 인터프리터를 넘긴다.** `py.exe` 는 스크립트의 `#!/usr/bin/env
# python3` 를 보고 `python3` 를 다시 찾는데, 이 기계에서 그것은 Microsoft Store 별칭
# (`WindowsApps\python3.exe`)이고 MSYS 에서 그 재분석 지점을 실행하면 fork 가
# `cygheap read copy failed` 로 죽는다. 실제 exe 경로를 미리 풀어서 그 우회를 없앤다.
$launcher = Get-Command py -ErrorAction SilentlyContinue
if ($null -ne $launcher) {
    $pythonPath = (& $launcher.Source -3 -c 'import sys; print(sys.executable)' 2>$null)
}
if ([string]::IsNullOrWhiteSpace($pythonPath)) {
    $fallback = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $fallback) {
        $pythonPath = (& $fallback.Source -c 'import sys; print(sys.executable)' 2>$null)
    }
}
if ([string]::IsNullOrWhiteSpace($pythonPath) -or -not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
    throw 'Python was not found. The installer branding bitmaps need Windows Python with Pillow.'
}
$pythonPath = $pythonPath.Trim()
& $pythonPath -c 'import PIL' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Pillow is missing from $pythonPath. Install it with: `"$pythonPath`" -m pip install pillow"
}
$posixPython = (& $cygpath -u $pythonPath).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'cygpath could not convert the Python path.'
}

& $bash -lc "MINGW_PREFIX=/ucrt64 PYTHON='$posixPython' MAKENSIS='$posixMakensis' '$posixScript' '$posixPlugin'"
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
