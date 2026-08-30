[CmdletBinding()]
param(
    [string]$VcpkgRoot,

    [string]$MsysRoot = 'C:\msys64'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot
$logDirectory = Join-Path $projectRoot 'out\logs'
$logPath = Join-Path $logDirectory ("local-ci-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    Write-Host '[local-ci] release build, CTest, and setup' -ForegroundColor Cyan
    $buildArguments = @{
        Configuration = 'Release'
        MsysRoot = $MsysRoot
        Overwrite = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($VcpkgRoot)) {
        $buildArguments.VcpkgRoot = $VcpkgRoot
    }
    & (Join-Path $PSScriptRoot 'build-installer.ps1') @buildArguments

    $manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'negaflow-mac\manifest.json') `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $installer = Join-Path $projectRoot `
        "out\release\x64\negaflow-sane-$($manifest.pluginVersion)-win-x64.exe"
    Write-Host '[local-ci] install, payload, detect, and uninstall' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'verify-installer.ps1') -InstallerPath $installer

    Write-Host '[local-ci] complete' -ForegroundColor Green
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "[local-ci] log: $logPath"
}
