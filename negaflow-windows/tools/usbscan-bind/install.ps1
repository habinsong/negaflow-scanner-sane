# negaflow-scanner-sane - 스캐너 USB 통로 열기
#
# 하는 일은 하나다: 스캐너를 Windows 자신의 usbscan.sys 에 묶어 sanei_usb 가 열 수 있게
# 한다. 바이너리는 하나도 설치하지 않는다.
#
# 서명에 대하여
#   pnputil 은 서명 없는 INF 를 거부한다. 그래서 이 스크립트가 자체 서명 인증서를 만들고
#   카탈로그에 서명한 뒤 신뢰 저장소에 넣는다. 테스트 서명 모드도, 보안 부팅 해제도
#   필요 없다. -RemoveCertificate 로 인증서까지 되돌릴 수 있다.
#
# 순서에 대하여
#   **먼저 설치하고, 성공한 뒤에야 벤더 바인딩을 건드린다.** 반대로 하면 설치가 실패했을
#   때 멀쩡히 쓰던 스캐너가 죽는다. 실제로 그렇게 만든 적이 있다.
#
# 관리자 PowerShell 에서:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall

[CmdletBinding()]
param(
    [switch]$Uninstall,
    # 신뢰 저장소에 넣은 자체 서명 인증서까지 지운다.
    [switch]$RemoveCertificate,
    # 설치 프로그램은 상승한 자식 프로세스의 종료 코드를 직접 받지 못한다.
    # 모든 작업을 마친 뒤에만 고정된 성공 표식을 남겨 부모가 결과를 확인하게 한다.
    [switch]$WriteSuccessMarker,
    # 설치 검증이 32/64비트 PowerShell 양쪽의 시스템 도구 경로만 안전하게 확인한다.
    [switch]$CheckPrerequisites
)

$ErrorActionPreference = 'Stop'
# 콘솔이 이 파일의 한글을 그대로 보이게 한다. 이 줄이 없으면 5.1 이 ANSI 로 읽어 깨진다.
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$here    = $PSScriptRoot
$inf     = Join-Path $here 'negaflow-usbscan.inf'
$catalog = Join-Path $here 'negaflow-usbscan.cat'
$subject = 'CN=negaflow-scanner-sane driver signing'
$successMarker = Join-Path $here 'install.success'

# 32비트 PowerShell 에서 System32 는 SysWOW64 로 리디렉션된다. 64비트 OS 의
# 32비트 프로세스만 쓸 수 있는 Sysnative 별칭으로 네이티브 시스템 도구를 연다.
$nativeSystemDirectory = Join-Path $env:SystemRoot 'System32'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $nativeSystemDirectory = Join-Path $env:SystemRoot 'Sysnative'
}
$pnputil = Join-Path $nativeSystemDirectory 'pnputil.exe'
if (-not (Test-Path -LiteralPath $pnputil -PathType Leaf)) {
    throw "pnputil.exe 를 찾을 수 없습니다: $pnputil"
}

function Write-SuccessMarker {
    if ($WriteSuccessMarker) {
        Set-Content -LiteralPath $successMarker -Value 'ok' -Encoding ASCII
    }
}

function Invoke-PnpUtil {
    param([Parameter(Mandatory)][string[]]$ArgumentList)

    $output = & $pnputil @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $detail = ($output | Out-String).Trim()
        throw "pnputil.exe 실패 (종료 코드 $exitCode): $detail"
    }
    return $output
}

if ($CheckPrerequisites) {
    Write-Output "pnputil=$pnputil"
    Write-SuccessMarker
    return
}

$isAdmin = ([Security.Principal.WindowsPrincipal]`
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '관리자 권한이 필요합니다. 관리자 PowerShell 에서 다시 실행하십시오.'
}

function Get-NegaflowPackages {
    $text = (Invoke-PnpUtil -ArgumentList @('/enum-drivers') | Out-String)
    $found = @()
    foreach ($block in ($text -split "`r?`n`r?`n")) {
        if ($block -match 'negaflow-usbscan\.inf' -and
            $block -match 'Published Name\s*:\s*(\S+)') {
            $found += $Matches[1]
        }
    }
    return $found
}

function Show-ScannerState {
    $devices = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_07B3|VID_04B8' -and $_.Present }
    if (-not $devices) { Write-Output '  (스캐너 없음)'; return }
    foreach ($device in $devices) {
        $service = (Get-PnpDeviceProperty -InstanceId $device.InstanceId `
            -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data
        $infName = (Get-PnpDeviceProperty -InstanceId $device.InstanceId `
            -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
        # Windows PowerShell 5.1 에는 ?? 가 없다. 이 스크립트는 5.1 에서 돌아야 한다.
        if (-not $service) { $service = '-' }
        if (-not $infName) { $infName = '-' }
        '  {0,-8} service={1,-10} inf={2,-18} {3}' -f `
            $device.Status, $service, $infName, $device.FriendlyName
    }
}

function Reenumerate-Scanners {
    # 이미 꽂혀 있던 장치는 부팅 때 잡힌 바인딩을 유지한다. 다시 열거해야 새 INF 를 본다.
    $devices = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_07B3|VID_04B8' -and $_.Present }
    foreach ($device in $devices) {
        try { Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null } catch {}
        try { Enable-PnpDevice  -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null } catch {}
    }
    # 그래도 안 붙으면 없는 장치로 남아 있을 수 있다. 버스를 다시 훑는다.
    try { Invoke-PnpUtil -ArgumentList @('/scan-devices') | Out-Null } catch {}
}

Write-Output '=== 지금 상태 ==='
Show-ScannerState

if ($Uninstall) {
    foreach ($package in Get-NegaflowPackages) {
        Write-Output "제거: $package"
        Invoke-PnpUtil -ArgumentList @('/delete-driver', $package, '/uninstall')
    }
    if ($RemoveCertificate) {
        foreach ($store in 'Root', 'TrustedPublisher', 'My') {
            Get-ChildItem "Cert:\LocalMachine\$store" -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq $subject } |
                ForEach-Object {
                    Write-Output "인증서 제거: $store\$($_.Thumbprint)"
                    Remove-Item $_.PSPath -Force
                }
        }
    }
    if (Test-Path $catalog) { Remove-Item $catalog -Force }
    Reenumerate-Scanners
    Write-Output '=== 제거 후 ==='
    Show-ScannerState
    Write-SuccessMarker
    return
}

# --- 1. 서명 인증서 ---
$certificate = Get-ChildItem 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1
if (-not $certificate) {
    Write-Output '=== 자체 서명 인증서 생성 ==='
    $certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject `
        -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(10) `
        -KeyUsage DigitalSignature -KeyExportPolicy Exportable
}
# 드라이버 패키지를 받으려면 발급자를 신뢰(Root)하고 게시자도 신뢰(TrustedPublisher)해야 한다.
foreach ($store in 'Root', 'TrustedPublisher') {
    $already = Get-ChildItem "Cert:\LocalMachine\$store" -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if (-not $already) {
        $open = New-Object Security.Cryptography.X509Certificates.X509Store($store, 'LocalMachine')
        $open.Open('ReadWrite')
        $open.Add($certificate)
        $open.Close()
        Write-Output "인증서 신뢰 추가: $store"
    }
}

# --- 2. 카탈로그 생성과 서명 ---
Write-Output '=== 카탈로그 서명 ==='
if (Test-Path $catalog) { Remove-Item $catalog -Force }
New-FileCatalog -Path $inf -CatalogFilePath $catalog -CatalogVersion 2 | Out-Null
$signed = Set-AuthenticodeSignature -FilePath $catalog -Certificate $certificate `
    -HashAlgorithm SHA256
if ($signed.Status -ne 'Valid') {
    throw "카탈로그 서명 실패: $($signed.Status) $($signed.StatusMessage)"
}

# --- 3. 설치. 성공을 확인하기 전에는 아무것도 지우지 않는다 ---
Write-Output '=== 설치 ==='
try {
    Invoke-PnpUtil -ArgumentList @('/add-driver', $inf, '/install')
}
catch {
    Write-Warning 'INF 설치 실패. 벤더 바인딩은 그대로 두었으므로 지금 쓰던 스캐너는 계속 동작합니다.'
    throw
}

Reenumerate-Scanners
Write-Output '=== 설치 후 ==='
Show-ScannerState
Write-Output ''
Write-Output 'service=usbscan 이면 통로가 열린 것입니다. 이어서:'
Write-Output '  negaflow-scanner-sane.exe detect'
Write-SuccessMarker
