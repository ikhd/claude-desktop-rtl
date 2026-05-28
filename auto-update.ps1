# auto-update.ps1  -  re-applies the RTL patch if a Claude update removed it.
# Registered as a logon Scheduled Task (RunLevel Highest) by install-windows.ps1.
# Runs silently; does nothing if the patch is still present.
$here = $PSScriptRoot
$pkg  = Get-AppxPackage -Name '*Claude*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pkg) { exit 0 }
$asar = Join-Path $pkg.InstallLocation 'app\resources\app.asar'
if (-not (Test-Path $asar)) { exit 0 }

try { $patched = ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($asar))).Contains('CLAUDE RTL PATCH START') }
catch { $patched = $false }

if ($patched) { exit 0 }   # still patched -> nothing to do

# A Claude update wiped the patch -> re-apply silently (this task is already elevated).
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'install-windows.ps1') -Auto
