<#
.SYNOPSIS
  Installs Agy Usage Bar (Windows tray app) from the latest GitHub release and starts it.
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
$dir = Join-Path $env:LOCALAPPDATA 'Programs\AgyUsageBar'
$exe = Join-Path $dir 'AgyUsageBar.exe'
$url = "https://github.com/$Repo/releases/latest/download/AgyUsageBar-$rid.exe"

if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
    Write-Host "Note: the 'agy' command was not found. The app needs the Antigravity CLI installed and signed in."
    Write-Host "      Installing the app anyway; it will show '!' until agy is available (tray menu: Locate agy.exe...)."
}

Write-Host "Downloading AgyUsageBar-$rid.exe from github.com/$Repo (latest release)..."
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Get-Process -Name AgyUsageBar -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
Unblock-File -Path $exe

# Start Menu shortcut so it can be launched again later.
$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path $programs 'Agy Usage Bar.lnk'))
$link.TargetPath = $exe
$link.WorkingDirectory = $dir
$link.Save()

if ($LaunchAtLogin) {
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-ItemProperty -Path $run -Name 'AgyUsageBar' -Value "`"$exe`"" -PropertyType String -Force | Out-Null
    Write-Host 'Launch at login: on.'
}

Start-Process -FilePath $exe
Write-Host "Installed to $exe and started."
Write-Host 'Look for the icon in the system tray (Windows 11: open the ^ overflow and drag it onto the taskbar).'
