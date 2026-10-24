<#
.SYNOPSIS
  Installs, upgrades and uninstalls the per-user MSI silently and checks the result each time.
  Run by CI on a Windows runner; you can also run it on any Windows machine (it installs and removes the app for your user).
.PARAMETER Msi
  The MSI to test (version 0.1.0).
.PARAMETER UpgradeMsi
  A build of the same package with version 0.1.1, used to test the in-place upgrade.
.PARAMETER LogFile
  Optional: also append every line to this file as it happens (so a hang can be diagnosed from the file).
.EXAMPLE
  ./test-msi.ps1 -Msi AgyUsageBar-win-x64.msi -UpgradeMsi AgyUsageBar-win-x64-0.1.1.msi
#>
param(
    [Parameter(Mandatory)] [string]$Msi,
    [Parameter(Mandatory)] [string]$UpgradeMsi,
    [string]$LogFile = ''
)
$ErrorActionPreference = 'Stop'
$v1 = (Resolve-Path $Msi).Path
$v2 = (Resolve-Path $UpgradeMsi).Path
$dir = Join-Path $env:LOCALAPPDATA 'Programs\AgyUsageBar'
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Agy Usage Bar.lnk'
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$upgradeCode = '{84229C8E-27E1-4D99-8155-E8E40ACF34BE}'
$failures = New-Object System.Collections.Generic.List[string]
$clock = [System.Diagnostics.Stopwatch]::StartNew()

function Out-Line([string]$Text) {
  Write-Host $Text
  if ($LogFile) { Add-Content -Path $LogFile -Value $Text }
}
function Info([string]$Text) { Out-Line ('[{0,6:n1}s] {1}' -f $clock.Elapsed.TotalSeconds, $Text) }
# Every check is recorded and the script carries on, so one run shows all problems at once.
function Check([bool]$Ok, [string]$What) {
  if ($Ok) { Info "ok      $What" } else { Out-Line "::error::FAILED: $What"; Info "FAILED  $What"; $failures.Add($What) }
}
# msiexec is started and awaited by hand: "Start-Process -Wait" also waits for the tray app that the installer launches, and would never return.
function Invoke-Msi([string]$Verb, [string]$Package, [string]$Log, [string]$Extra = '') {
  Info "msiexec /$Verb $(Split-Path $Package -Leaf) $Extra"
  $psi = New-Object System.Diagnostics.ProcessStartInfo 'msiexec.exe'
  $psi.UseShellExecute = $false
  $psi.Arguments = ('/{0} "{1}" /qn /norestart /l*v "{2}" {3}' -f $Verb, $Package, $Log, $Extra)
  $p = [System.Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(240000)) {
    $p.Kill()
    if (Test-Path $Log) { Get-Content $Log -Tail 60 }
    throw "msiexec /$Verb did not finish within 4 minutes"
  }
  Info "msiexec exited with $($p.ExitCode)"
  if ($p.ExitCode -ne 0) { if (Test-Path $Log) { Get-Content $Log -Tail 150 }; throw "msiexec /$Verb exited with $($p.ExitCode)" }
}
function Wait-Until([scriptblock]$Condition, [int]$Seconds = 20) {
  for ($i = 0; $i -lt $Seconds; $i++) { if (& $Condition) { return $true }; Start-Sleep -Seconds 1 }
  return [bool](& $Condition)
}
function Get-AppCount { @(Get-Process AgyUsageBar -ErrorAction SilentlyContinue).Count }
function Show-App { Get-Process AgyUsageBar -ErrorAction SilentlyContinue | ForEach-Object { Info "  AgyUsageBar pid $($_.Id), session $($_.SessionId), $($_.Path)" } }
# Where Settings > Apps reads from: look in every Uninstall hive instead of assuming one.
# The .NET registry API is used on purpose: walking these keys with Get-ItemProperty takes minutes on a runner with hundreds of installed products.
function Get-Arp {
  $roots = @(
    @{ Hive = [Microsoft.Win32.RegistryHive]::CurrentUser;  View = [Microsoft.Win32.RegistryView]::Registry64 },
    @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; View = [Microsoft.Win32.RegistryView]::Registry64 },
    @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; View = [Microsoft.Win32.RegistryView]::Registry32 }
  )
  foreach ($r in $roots) {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($r.Hive, $r.View)
    $uninstall = $base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
    if ($null -eq $uninstall) { continue }
    foreach ($name in $uninstall.GetSubKeyNames()) {
      $sub = $uninstall.OpenSubKey($name)
      if ($null -eq $sub) { continue }
      if ($sub.GetValue('DisplayName') -eq 'Agy Usage Bar') {
        [pscustomobject]@{ Hive = "$($r.Hive)"; View = "$($r.View)"; Key = $name; Version = $sub.GetValue('DisplayVersion') }
      }
      $sub.Dispose()
    }
  }
}
# The Windows Installer's own record of what is installed (independent of registry layout).
$wi = New-Object -ComObject WindowsInstaller.Installer
function Get-InstalledVersions { foreach ($pc in $wi.RelatedProducts($upgradeCode)) { $wi.ProductInfo($pc, 'VersionString') } }

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([System.Security.Principal.WindowsPrincipal]$identity).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Info "$([System.Environment]::OSVersion.VersionString), user $($identity.Name), elevated $elevated, Windows Installer service $((Get-Service msiserver).Status)"

try {
  Info '== 1. Fresh install'
  Invoke-Msi i $v1 install.log
  Check (Test-Path "$dir\AgyUsageBar.exe") 'AgyUsageBar.exe is installed'
  Check (Test-Path $lnk) 'Start Menu shortcut exists'
  Info 'waiting for the installer to start the app...'
  Check (Wait-Until { (Get-AppCount) -eq 1 }) "the installer started the app (running copies: $(Get-AppCount))"
  Show-App
  Info 'asking the Windows Installer what is installed...'
  Check ((@(Get-InstalledVersions) -join ',') -eq '0.1.0') "Windows Installer lists exactly version 0.1.0 (got: $(@(Get-InstalledVersions) -join ','))"
  Info 'reading the Add/Remove Programs entries...'
  $arp = @(Get-Arp)
  Out-Line ($arp | Format-List | Out-String)
  Check ($arp.Count -eq 1 -and $arp[0].Version -eq '0.1.0') 'Add/Remove Programs entry exists with version 0.1.0'
  Check (-not (Get-ItemProperty $run -Name AgyUsageBar -ErrorAction SilentlyContinue)) 'launch at login is off by default'

  Info '== 2. Upgrade while the app is running'
  Invoke-Msi i $v2 upgrade.log
  Info 'waiting for one running copy after the upgrade...'
  Check (Wait-Until { (Get-AppCount) -eq 1 }) "one copy runs after the upgrade (running copies: $(Get-AppCount))"
  Show-App
  Check ((@(Get-InstalledVersions) -join ',') -eq '0.1.1') "Windows Installer lists exactly version 0.1.1 (got: $(@(Get-InstalledVersions) -join ','))"
  $arp = @(Get-Arp)
  Check ($arp.Count -eq 1 -and $arp[0].Version -eq '0.1.1') 'one Add/Remove Programs entry, version 0.1.1'
  Check (Test-Path "$dir\AgyUsageBar.exe") 'the exe is still installed after the upgrade'

  Info '== 3. Uninstall'
  Invoke-Msi x $v2 uninstall.log
  Info 'waiting for the app to stop...'
  Check (Wait-Until { (Get-AppCount) -eq 0 }) 'the app was stopped'
  Check (-not (Test-Path $dir)) 'install folder removed'
  Check (-not (Test-Path $lnk)) 'shortcut removed'
  Check (@(Get-InstalledVersions).Count -eq 0) 'Windows Installer no longer lists the product'
  Check (@(Get-Arp).Count -eq 0) 'Add/Remove Programs entry removed'

  Info '== 4. Optional launch at login (LAUNCHATLOGIN=1)'
  Invoke-Msi i $v1 install-login.log 'LAUNCHATLOGIN=1'
  $val = (Get-ItemProperty $run -Name AgyUsageBar -ErrorAction SilentlyContinue).AgyUsageBar
  Check ($val -like '*AgyUsageBar.exe*') "Run key written: '$val'"
  Invoke-Msi x $v1 uninstall-login.log
  Check (-not (Get-ItemProperty $run -Name AgyUsageBar -ErrorAction SilentlyContinue)) 'Run key removed on uninstall'
  Check (Wait-Until { (Get-AppCount) -eq 0 }) 'the app was stopped by the last uninstall'
}
catch {
  Out-Line "::error::test script aborted: $($_.Exception.Message)"
  Info "aborted: $($_.Exception.Message)"
  $failures.Add("aborted: $($_.Exception.Message)")
}
finally {
  # Leave nothing behind, whatever happened above.
  Get-Process AgyUsageBar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
  Info "$($failures.Count) check(s) failed: $($failures -join '; ')"
  exit 1
}
Info 'All installer checks passed'
exit 0
