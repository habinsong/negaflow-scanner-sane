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
    'uninstall.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDirectory $required) -PathType Leaf)) {
        throw "Installed payload is missing '$required'."
    }
}

$process = Start-Process -FilePath (Join-Path $InstallDirectory 'negaflow-scanner-sane.exe') `
    -ArgumentList 'detect' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Installed adapter detect failed with exit code $($process.ExitCode)."
}
$process = Start-Process -FilePath (Join-Path $InstallDirectory 'uninstall.exe') -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Silent uninstall failed with exit code $($process.ExitCode)."
}
if (Test-Path -LiteralPath $InstallDirectory) {
    throw "Uninstaller left its plug-in directory behind: $InstallDirectory"
}
Write-Host "Installer smoke passed: $InstallerPath" -ForegroundColor Green
