[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,

    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
$InstallerPath = [System.IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Installer does not exist: $InstallerPath"
}
if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('negaflow-sane-installer-' + [Guid]::NewGuid().ToString('N'))
}
$InstallDirectory = [System.IO.Path]::GetFullPath($InstallDirectory)
if (Test-Path -LiteralPath $InstallDirectory) {
    throw "Verification install directory must not already exist: $InstallDirectory"
}

$process = Start-Process -FilePath $InstallerPath -ArgumentList @('/S', "/D=$InstallDirectory") -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Silent install failed with exit code $($process.ExitCode)."
}

$manifestPath = Join-Path $InstallDirectory 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.id -ne 'sane' -or $manifest.protocolVersion -ne 2 -or
    $manifest.executable -ne 'negaflow-scanner-sane.exe') {
    throw 'Installed manifest does not describe the Windows SANE adapter.'
}
foreach ($required in @(
    'negaflow-scanner-sane.exe',
    'sane\bin\scanimage.exe',
    'LICENSES\COPYING',
    'source\negaflow-scanner-sane-source.tar.gz',
    'uninstall.exe',
    # 깨끗한 PC 에서 스캐너를 여는 통로. 이것이 빠지면 설치는 되고 장치만 안 보인다.
    'usbscan-bind\negaflow-usbscan.inf',
    'usbscan-bind\install.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDirectory $required) -PathType Leaf)) {
        throw "Installed payload is missing '$required'."
    }
}

$process = Start-Process -FilePath (Join-Path $InstallDirectory 'negaflow-scanner-sane.exe') `
    -ArgumentList 'detect' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Installed adapter detect failed with exit code $($process.ExitCode)."
}

# NSIS 제거기는 제 디렉터리째 지워야 해서 스스로를 임시 폴더로 복사하고 일을 넘긴 뒤
# **원본은 즉시 0 으로 빠진다.** `-Wait` 가 기다리는 것은 그 원본이라, 실제 제거가 끝나기
# 전에 "디렉터리가 남았다"로 실패할 수 있다 - negaflow 쪽에서 실제로 그렇게 실패했고,
# 같은 디렉터리가 잠시 뒤 스스로 사라져 있었다. 끝난 자리를 결과로 기다린다.
$process = Start-Process -FilePath (Join-Path $InstallDirectory 'uninstall.exe') -ArgumentList '/S' -PassThru
if (-not $process.WaitForExit(60000)) {
    try { $process.Kill($true) } catch { }
    throw 'Silent uninstall did not hand off to its worker copy within 1 minute.'
}
if ($process.ExitCode -ne 0) {
    throw "Silent uninstall failed with exit code $($process.ExitCode)."
}
$deadline = [DateTime]::UtcNow.AddMinutes(3)
while ((Test-Path -LiteralPath $InstallDirectory) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
}
if (Test-Path -LiteralPath $InstallDirectory) {
    throw "Uninstaller left its plug-in directory behind: $InstallDirectory"
}
Write-Host "Installer smoke passed: $InstallerPath" -ForegroundColor Green
