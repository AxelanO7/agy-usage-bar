<#
.SYNOPSIS
  Installs Agy Usage Bar (Windows tray app) from the latest GitHub release with the per-user MSI and starts it.
  Same result as double-clicking the .msi: no administrator rights, Start Menu entry, listed in Settings > Apps.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -LaunchAtLogin
#>
[CmdletBinding()]
param(
    [switch]$LaunchAtLogin,
    [string]$Repo = 'AxelanO7/agy-usage-bar'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is far faster without the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    throw 'This script is for Windows. On macOS run scripts/install.sh.'
}

$rid = if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'win-arm64' } else { 'win-x64' }
$asset = "AgyUsageBar-$rid.msi"
$url = "https://github.com/$Repo/releases/latest/download/$asset"
$msi = Join-Path $env:TEMP $asset
$log = Join-Path $env:TEMP 'AgyUsageBar-install.log'

if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
    Write-Host "Note: the 'agy' command was not found. The app needs the Antigravity CLI installed and signed in."
    Write-Host "      Installing the app anyway; it will show '!' until agy is available (tray menu: Locate agy.exe...)."
}

Write-Host "Downloading $asset from github.com/$Repo (latest release)..."
Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

# msiexec is started and awaited by hand: "Start-Process -Wait" would also wait for the tray app the installer launches.
$psi = New-Object System.Diagnostics.ProcessStartInfo 'msiexec.exe'
$psi.UseShellExecute = $false
$psi.Arguments = ('/i "{0}" /qn /norestart /l*v "{1}"' -f $msi, $log) + $(if ($LaunchAtLogin) { ' LAUNCHATLOGIN=1' } else { '' })
Write-Host 'Installing (per user, no administrator rights)...'
$p = [System.Diagnostics.Process]::Start($psi)
if (-not $p.WaitForExit(300000)) { $p.Kill(); throw 'msiexec did not finish within 5 minutes.' }
Remove-Item $msi -Force -ErrorAction SilentlyContinue

# 0 = ok, 3010 = ok but Windows wants a restart (not needed for this app).
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    if (Test-Path $log) { Get-Content $log -Tail 40 }
    throw "The installer failed with exit code $($p.ExitCode) (full log: $log). The portable AgyUsageBar-$rid.exe on the release page needs no installer."
}

$exe = Join-Path $env:LOCALAPPDATA 'Programs\AgyUsageBar\AgyUsageBar.exe'
if (-not (Test-Path $exe)) { throw "Installed, but $exe is missing. See $log." }
if ($LaunchAtLogin) { Write-Host 'Launch at login: on.' }
Write-Host "Installed to $exe and started."
Write-Host 'Look for the icon in the system tray (Windows 11: open the ^ overflow and drag it onto the taskbar).'
Write-Host 'Remove it later from Settings > Apps > Agy Usage Bar.'
