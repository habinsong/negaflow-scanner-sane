# negaflow-scanner-sane — 스캐너 USB 통로 열기
#
# 하는 일은 하나다: 스캐너를 Windows 자신의 usbscan.sys 에 묶어 sanei_usb 가 열 수 있게
# 한다. 바이너리는 하나도 설치하지 않는다(INF 주석 참고).
#
# 관리자 PowerShell 에서 실행한다:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# 되돌리려면:
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall

[CmdletBinding()]
param(
    [switch]$Uninstall,
    # 벤더 INF(SilverFast 의 oem113.inf 등)가 우리보다 우선해 붙어 있으면 그것을 지운다.
    # **기본은 끔** — 벤더 소프트웨어를 쓰는 사용자의 설정을 말없이 걷어내지 않는다.
    [switch]$ReplaceVendorBinding
)

$ErrorActionPreference = 'Stop'
$inf = Join-Path $PSScriptRoot 'negaflow-usbscan.inf'

$isAdmin = ([Security.Principal.WindowsPrincipal]`
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '관리자 권한이 필요합니다. 관리자 PowerShell 에서 다시 실행하십시오.'
}

function Get-NegaflowDriverPackages {
    # /enum-drivers 는 문단 단위로 나온다. 원본 이름으로 우리 것을 골라낸다.
    $text = (pnputil /enum-drivers | Out-String)
    $packages = @()
    foreach ($block in ($text -split "`r?`n`r?`n")) {
        if ($block -match 'negaflow-usbscan\.inf') {
            if ($block -match 'Published Name\s*:\s*(\S+)') { $packages += $Matches[1] }
        }
    }
    return $packages
}

function Show-ScannerState {
    Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_07B3|VID_04B8' -and $_.Present } |
        ForEach-Object {
            $service = (Get-PnpDeviceProperty -InstanceId $_.InstanceId `
                -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data
            $infName = (Get-PnpDeviceProperty -InstanceId $_.InstanceId `
                -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
            "  {0,-8} service={1,-10} inf={2,-16} {3}" -f `
                $_.Status, ($service ?? '-'), ($infName ?? '-'), $_.FriendlyName
        }
}

Write-Output '=== 지금 상태 ==='
Show-ScannerState

if ($Uninstall) {
    foreach ($package in Get-NegaflowDriverPackages) {
        Write-Output "제거: $package"
        pnputil /delete-driver $package /uninstall
    }
    Write-Output '=== 제거 후 ==='
    Show-ScannerState
    return
}

if ($ReplaceVendorBinding) {
    # 벤더 INF 는 앱을 지워도 드라이버 저장소에 남는다. 그것이 붙어 있는 한 우리 INF 가
    # 붙었는지 알 수 없으므로, 확인이 목적일 때만 이 스위치를 쓴다.
    $bound = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_07B3|VID_04B8' -and $_.Present } |
        ForEach-Object {
            (Get-PnpDeviceProperty -InstanceId $_.InstanceId `
                -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
        } | Where-Object { $_ -and $_ -match '^oem' } | Select-Object -Unique
    foreach ($package in $bound) {
        Write-Output "벤더 바인딩 제거: $package"
        pnputil /delete-driver $package /uninstall
    }
}

Write-Output "=== 설치: $inf ==="
pnputil /add-driver $inf /install
if ($LASTEXITCODE -ne 0) {
    Write-Warning @'
INF 설치가 실패했습니다. 가장 흔한 원인은 **서명** 입니다 — 이 INF 는 바이너리를 설치하지
않지만, 드라이버 패키지는 서명 강제를 통과해야 합니다. D-1(코드 서명 인증서)로 카탈로그에
서명하면 해결됩니다.
'@
}

# 이미 꽂혀 있던 장치는 새 INF 를 보고 다시 열거해야 붙는다.
Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_07B3|VID_04B8' -and $_.Present } |
    ForEach-Object {
        try { $null = Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false } catch {}
        try { $null = Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false } catch {}
    }

Write-Output '=== 설치 후 ==='
Show-ScannerState
Write-Output ''
Write-Output 'service=usbscan 이면 통로가 열린 것입니다. 이어서 확인:'
Write-Output '  negaflow-scanner-sane.exe detect'
