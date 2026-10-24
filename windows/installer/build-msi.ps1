<#
.SYNOPSIS
  Builds the per-user MSI from a published AgyUsageBar.exe (Windows only: WiX needs the Windows Installer service).
.EXAMPLE
  ./build-msi.ps1 -Exe publish\win-x64\AgyUsageBar.exe -Arch x64 -Version 0.1.0 -Out AgyUsageBar-win-x64.msi
#>
param(
    [Parameter(Mandatory)] [string]$Exe,
    [ValidateSet('x64', 'arm64')] [string]$Arch = 'x64',
    [string]$Version = '0.1.0',
    [Parameter(Mandatory)] [string]$Out
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$icon = Join-Path $here '..\src\AgyUsageBar\app.ico'

# WiX 5.x on purpose: v6 and newer require accepting a EULA, which blocks unattended builds.
if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
    dotnet tool install --global wix --version 5.0.2
    $env:PATH += ";$env:USERPROFILE\.dotnet\tools"
}
# The wix tool targets an older .NET than the one setup-dotnet installs; let it run on the newer runtime.
$env:DOTNET_ROLL_FORWARD = 'Major'
wix build -arch $Arch -pdbtype none -d Version=$Version -d ExePath=$((Resolve-Path $Exe).Path) -d IconPath=$((Resolve-Path $icon).Path) -o $Out (Join-Path $here 'Package.wxs')
if ($LASTEXITCODE -ne 0) { throw "wix build failed ($LASTEXITCODE)" }
Write-Host "Built $Out ($([math]::Round((Get-Item $Out).Length / 1MB, 1)) MB)"
