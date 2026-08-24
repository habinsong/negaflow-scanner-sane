<#
.SYNOPSIS
    downstream SANE 런타임(mingw-w64-ucrt-x86_64-sane)을 저장소의 PKGBUILD 와
    patches/ 로 빌드하고 MSYS2 UCRT64 에 설치한다.

.DESCRIPTION
    이 스크립트가 존재하는 이유는 손으로 하던 절차가 실제로 두 번 틀렸기 때문이다.

      1) SOURCES.md 의 `cp sane-runtime/PKGBUILD sane-runtime/patches/*.patch <작업>` 를
         사람이 옮겨 적으면서 sane-runtime/ 최상위에 남아 있던 낡은 패치 복사본을
         집어, 011(OpticFilm host-side Gray) 이 빠진 채로 런타임이 빌드됐다.
         빌드는 성공하고 Gray 만 조용히 옛 동작으로 남는다.
      2) 빌드 산출물은 `libsane-<backend>-1.dll` 인데 dll.c 는 Windows 에서
         `cygsane-<backend>-1.dll` 만 로드한다. lib/sane 에 남은 낡은 cygsane-* 가
         새로 빌드한 libsane-* 를 가려서, 고친 백엔드를 넣고도 옛 코드가 돈다.

    그래서 이 스크립트는 패치 목록을 PKGBUILD 의 source=() 와 대조해서 검증하고,
    설치 뒤 lib/sane 의 낡은 cygsane-* 그림자를 제거한다.

.PARAMETER MsysRoot
    MSYS2 설치 경로. 기본값 C:\msys64

.PARAMETER WorkRoot
    makepkg 작업 디렉터리. 기본값은 저장소의 build-sane-runtime\ (gitignore 대상).

.PARAMETER SkipInstall
    빌드만 하고 pacman 설치는 하지 않는다.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-sane-runtime.ps1
#>
[CmdletBinding()]
param(
    [string]$MsysRoot = 'C:\msys64',
    [string]$WorkRoot,
    [switch]$SkipInstall,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoWindows = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $repoWindows
$runtimeDir = Join-Path $repoRoot 'negaflow-mac\sane-runtime'
$patchDir = Join-Path $runtimeDir 'patches'
$pkgbuild = Join-Path $runtimeDir 'PKGBUILD'

if (-not $WorkRoot) { $WorkRoot = Join-Path $repoWindows 'build-sane-runtime' }

$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$cygpath = Join-Path $MsysRoot 'usr\bin\cygpath.exe'
foreach ($required in @($bash, $cygpath, $pkgbuild, $patchDir)) {
    if (-not (Test-Path $required)) { throw "필요한 경로가 없습니다: $required" }
}

function Convert-ToPosixPath([string]$WindowsPath) {
    return (& $cygpath -u $WindowsPath).Trim()
}

# --- 1. PKGBUILD 의 source=() 와 patches/ 를 대조한다 -------------------------
$pkgbuildText = Get-Content -Raw -LiteralPath $pkgbuild
$declared = [regex]::Matches($pkgbuildText, '"(\d{3}-[A-Za-z0-9._-]+\.patch)"') |
    ForEach-Object { $_.Groups[1].Value }
if ($declared.Count -eq 0) { throw "PKGBUILD 의 source=() 에서 패치를 찾지 못했습니다." }

$onDisk = Get-ChildItem -LiteralPath $patchDir -Filter '*.patch' |
    Sort-Object Name | Select-Object -ExpandProperty Name

$missing = $declared | Where-Object { $onDisk -notcontains $_ }
if ($missing) { throw "PKGBUILD 가 요구하는 패치가 patches\ 에 없습니다: $($missing -join ', ')" }

$extra = $onDisk | Where-Object { $declared -notcontains $_ }
if ($extra) { throw "patches\ 에 PKGBUILD 가 쓰지 않는 패치가 있습니다: $($extra -join ', ')" }

# 2) prepare() 가 실제로 모든 패치를 적용하는지도 본다. source=() 에만 넣고
#    prepare() 에 빠뜨리면 makepkg 는 성공하고 그 패치만 사라진다.
foreach ($name in $declared) {
    if ($pkgbuildText -notmatch [regex]::Escape("/$name")) {
        throw "PKGBUILD 의 prepare() 가 $name 을 적용하지 않습니다."
    }
}

# --- 2. CRLF 로 오염된 패치는 patch(1) 에 적용되지 않는다 --------------------
foreach ($name in $declared) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $patchDir $name))
    if ($bytes -contains 13) {
        throw "CRLF 로 오염된 패치입니다. LF 로 되돌리세요: patches\$name"
    }
}
if ([System.IO.File]::ReadAllBytes($pkgbuild) -contains 13) {
    throw "CRLF 로 오염된 PKGBUILD 입니다. LF 로 되돌리세요."
}

Write-Host "패치 $($declared.Count) 개를 확인했습니다: $($declared -join ', ')"

# --- 3. 작업 디렉터리 구성 ---------------------------------------------------
if ($Clean -and (Test-Path $WorkRoot)) { Remove-Item -Recurse -Force $WorkRoot }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

Copy-Item -LiteralPath $pkgbuild -Destination $WorkRoot -Force
foreach ($name in $declared) {
    Copy-Item -LiteralPath (Join-Path $patchDir $name) -Destination $WorkRoot -Force
}

# 캐시된 upstream tarball 은 다시 받지 않는다. 해시는 makepkg 가 검증한다.
$cachedTarball = Join-Path $runtimeDir 'backends-1.4.0.tar.bz2'
if ((Test-Path $cachedTarball) -and -not (Test-Path (Join-Path $WorkRoot 'backends-1.4.0.tar.bz2'))) {
    Copy-Item -LiteralPath $cachedTarball -Destination $WorkRoot -Force
}

$posixWork = Convert-ToPosixPath $WorkRoot

# --- 4. makepkg ---------------------------------------------------------------
Write-Host "UCRT64 에서 빌드합니다: $WorkRoot"
& $bash -lc "cd '$posixWork' && MSYSTEM=UCRT64 makepkg-mingw -sf --nocheck --noconfirm"
if ($LASTEXITCODE -ne 0) { throw "makepkg-mingw 가 실패했습니다 (exit $LASTEXITCODE)." }

$package = Get-ChildItem -LiteralPath $WorkRoot -Filter 'mingw-w64-ucrt-x86_64-sane-*.pkg.tar.zst' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $package) { throw "빌드 산출 패키지를 찾지 못했습니다." }

$packageHash = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "패키지: $($package.Name)"
Write-Host "SHA-256: $packageHash"

if ($SkipInstall) { return }

# --- 5. 설치와 낡은 cygsane-* 그림자 제거 ------------------------------------
$posixPackage = Convert-ToPosixPath $package.FullName
& $bash -lc "pacman -U --noconfirm '$posixPackage'"
if ($LASTEXITCODE -ne 0) { throw "pacman -U 가 실패했습니다 (exit $LASTEXITCODE)." }

# dll.c 는 Windows 에서 cygsane-<backend>-1.dll 만 dlopen 한다. 패키지는
# libsane-* 만 넣으므로, 예전에 손으로 복사해 둔 cygsane-* 가 남아 있으면
# 새 백엔드가 영원히 로드되지 않는다. 패키지가 소유하지 않는 것만 지운다.
$libSane = Join-Path $MsysRoot 'ucrt64\lib\sane'
$stale = @()
if (Test-Path $libSane) {
    $stale = Get-ChildItem -LiteralPath $libSane -Filter 'cygsane-*.dll' -ErrorAction SilentlyContinue
}
foreach ($file in $stale) {
    Write-Host "낡은 백엔드 그림자를 제거합니다: $($file.Name)"
    Remove-Item -LiteralPath $file.FullName -Force
}

Write-Host "설치 완료. 다음은 scripts\build-installer.ps1 로 플러그인 setup 을 만듭니다."
