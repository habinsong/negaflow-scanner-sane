# negaflow-scanner-sane — Windows 설치 프로그램
#
# 하나만 실행하면 플러그인과 SANE 런타임이 함께 설치된다. 사용자가 따로
# 받아야 하는 것은 없다. 관리자 권한도 필요 없다 — 드라이버를 바꾸지 않기
# 때문이다.
#
#   .\install.ps1              설치 또는 갱신
#   .\install.ps1 -Uninstall   제거
#   .\install.ps1 -Quiet       무인
#
# 실패하면 이전 설치를 되돌린다. 반쯤 설치된 상태로 두지 않는다.

[CmdletBinding()]
param(
    [switch] $Uninstall,
    [switch] $Quiet,
    [string] $Destination
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$PluginId  = 'sane'
$PayloadDir = Join-Path $PSScriptRoot 'payload'
if (-not $Destination) {
    $Destination = Join-Path $env:LOCALAPPDATA "Negaflow\ScannerPlugins\$PluginId"
}

function Say([string] $text) { if (-not $Quiet) { Write-Host $text } }

function Assert-Supported {
    # scanimage.exe 와 백엔드는 x64 다. ARM64 에서는 에뮬레이션으로 돌지만
    # USB 계층이 검증되지 않았으므로 조용히 넘기지 않는다.
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -ne 'AMD64') {
        throw "이 패키지는 x64 전용입니다. 이 컴퓨터는 $arch 입니다."
    }
    if ([Environment]::OSVersion.Version.Major -lt 10) {
        throw 'Windows 10 이상이 필요합니다.'
    }
}

function Remove-Installation([string] $path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    # 실행 중인 플러그인이 있으면 파일이 잠긴다. 먼저 알린다.
    $running = Get-Process -Name 'negaflow-scanner-sane', 'scanimage' -ErrorAction SilentlyContinue
    if ($running) {
        throw '플러그인이 실행 중입니다. negaflow 를 닫고 다시 시도하십시오.'
    }
    Remove-Item -LiteralPath $path -Recurse -Force
    return $true
}

# --- 제거 -------------------------------------------------------------------

if ($Uninstall) {
    if (Remove-Installation $Destination) {
        Say "제거했습니다: $Destination"
    } else {
        Say "설치되어 있지 않습니다: $Destination"
    }
    exit 0
}

# --- 설치 -------------------------------------------------------------------

Assert-Supported

if (-not (Test-Path -LiteralPath (Join-Path $PayloadDir 'negaflow-scanner-sane.exe'))) {
    throw "payload 를 찾을 수 없습니다: $PayloadDir"
}

Say 'negaflow-scanner-sane 을 설치합니다.'
Say "  대상: $Destination"
Say '  SANE 런타임이 함께 설치됩니다. 관리자 권한은 필요하지 않습니다.'

$parent  = Split-Path -Parent $Destination
$staging = Join-Path $parent ("$PluginId.staging-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$backup  = Join-Path $parent ("$PluginId.previous-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

New-Item -ItemType Directory -Force -Path $parent | Out-Null

$movedAside = $false
try {
    # ① 새것을 staging 에 완성한다. 여기까지 실패해도 기존 설치는 그대로다.
    Copy-Item -LiteralPath $PayloadDir -Destination $staging -Recurse -Force

    # ② 기존을 옆으로 치운다.
    if (Test-Path -LiteralPath $Destination) {
        $running = Get-Process -Name 'negaflow-scanner-sane', 'scanimage' -ErrorAction SilentlyContinue
        if ($running) {
            throw '플러그인이 실행 중입니다. negaflow 를 닫고 다시 시도하십시오.'
        }
        Move-Item -LiteralPath $Destination -Destination $backup
        $movedAside = $true
    }

    # ③ 새것을 제자리에.
    Move-Item -LiteralPath $staging -Destination $Destination
} catch {
    # 되돌린다. 반쯤 설치된 상태로 두지 않는다.
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($movedAside -and (Test-Path -LiteralPath $backup)) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $backup -Destination $Destination
        Say '설치에 실패해 이전 상태로 되돌렸습니다.'
    }
    throw
}

if (Test-Path -LiteralPath $backup) {
    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 확인 -------------------------------------------------------------------
#
# 설치했다고 말하기 전에 실제로 도는지 본다. 스캐너가 없어도 플러그인은
# 빈 목록을 내고 정상 종료해야 한다.

$exe = Join-Path $Destination 'negaflow-scanner-sane.exe'
$probe = & $exe detect 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "설치는 됐지만 플러그인이 동작하지 않습니다 (종료 코드 $LASTEXITCODE):`n$probe"
}

Say ''
Say '설치했습니다.'
$found = ([regex]'"id"').Matches([string] $probe).Count
if ($found -gt 0) {
    Say "  스캐너 ${found}대를 찾았습니다."
} else {
    Say '  지금은 스캐너가 연결되어 있지 않습니다. 연결하면 negaflow 가 찾습니다.'
}
Say ''
Say '  라이선스: GPL-2.0-or-later. LICENSES\ 와 source\ 를 함께 설치했습니다.'
Say "  제거하려면: .\install.ps1 -Uninstall"
