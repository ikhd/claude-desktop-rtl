# Claude Desktop RTL  -  Windows IN-PLACE patcher  (ASCII-only)
# ===========================================================================
# Patches the REAL MSIX app in place so it keeps its package identity ->
# your login AND Claude Code / Cowork keep working. Original mechanism,
# inspired by shraga100's documented approach:
#   1) inject the RTL engine into app.asar + repack
#   2) byte-patch the asar header hash inside Claude.exe (fallback: disable fuse)
#   3) re-sign Claude.exe with a self-signed cert
#   4) swap the Anthropic cert embedded in cowork-svc.exe with our cert + re-sign
#   5) trust our cert (LocalMachine\Root) so the re-signed binaries validate
# Full backup + rollback + -Uninstall restore.
#
# WARNING: needs Administrator (auto-elevates). Closes Claude. Windows MSIX may
# still revert/remove a tampered package on updates -> just re-run, or restore.
#
# Usage:  powershell -ExecutionPolicy Bypass -File install-windows.ps1 [-Uninstall]
param([switch]$Uninstall, [switch]$Auto)
$ErrorActionPreference = 'Stop'

# ---- self-elevate to Administrator -------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Uninstall) { $a += '-Uninstall' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $a
    exit
}

$here     = $PSScriptRoot
$PAYLOAD  = Join-Path $here 'rtl-engine.js'
$BK       = Join-Path $env:LOCALAPPDATA 'ClaudeRTL\backup'
$CERTCN   = 'Claude RTL Patch'

function Info($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[ok] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "[X] $m" -ForegroundColor Red; if (-not $Auto) { Read-Host 'Press Enter to exit' }; exit 1 }

function Get-AsarHeaderHash($asar) {
    $fs = [IO.File]::OpenRead($asar)
    try {
        $br = New-Object IO.BinaryReader($fs)
        $fs.Seek(12,'Begin') | Out-Null
        $n = $br.ReadUInt32()
        $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($br.ReadBytes([int]$n))
        return ([BitConverter]::ToString($sha)).Replace('-','').ToLower()
    } finally { $fs.Close() }
}

# ---- locate the package ------------------------------------------------------
$pkg = Get-AppxPackage -Name '*Claude*' | Select-Object -First 1
if (-not $pkg) { Die "Claude Desktop (MSIX) not found." }
$app    = Join-Path $pkg.InstallLocation 'app'
$claude = Join-Path $app 'Claude.exe'
$asar   = Join-Path $app 'resources\app.asar'
$cowork = Join-Path $app 'resources\cowork-svc.exe'
$appId  = (Get-AppxPackageManifest $pkg).Package.Applications.Application.Id
if ($appId -is [array]) { $appId = $appId[0] }
$aumid  = "$($pkg.PackageFamilyName)!$appId"
foreach ($f in @($claude,$asar)) { if (-not (Test-Path $f)) { Die "Missing $f" } }

function Test-Patched {
    try { return ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($asar))).Contains('CLAUDE RTL PATCH START') } catch { return $false }
}
function Setup-AutoUpdate {
    $dir = Join-Path $env:LOCALAPPDATA 'ClaudeRTL'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path (Join-Path $dir 'patched-version.txt') -Value $pkg.Version -Encoding ASCII
    $aup = Join-Path $here 'auto-update.ps1'
    if (-not (Test-Path $aup)) { Warn "auto-update.ps1 missing; auto-update not enabled."; return }
    try {
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$aup`""
        $trg = New-ScheduledTaskTrigger -AtLogOn
        $prn = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -RunLevel Highest -LogonType Interactive
        Register-ScheduledTask -TaskName 'ClaudeRTL-AutoUpdate' -Action $act -Trigger $trg -Principal $prn -Force | Out-Null
        Ok "Auto-update enabled (re-patches at logon after a Claude update)."
    } catch { Warn "Could not register auto-update task: $($_.Exception.Message)" }
}

function Stop-Claude {
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -match 'cowork-svc' } |
        ForEach-Object { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue }
    Get-Process Claude,cowork-svc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
function Take-Own {
    takeown /F "$claude" 2>&1 | Out-Null
    icacls  "$claude" /grant "*S-1-5-32-544:F" 2>&1 | Out-Null
    $res = Split-Path $asar
    takeown /F "$res" /R /D Y 2>&1 | Out-Null
    icacls  "$res" /grant "*S-1-5-32-544:(OI)(CI)F" /T 2>&1 | Out-Null
}
function Restore-FromBackup {
    if (-not (Test-Path $BK)) { Warn "No backup found."; return }
    Stop-Claude; Take-Own
    foreach ($n in 'app.asar','Claude.exe','cowork-svc.exe') {
        $b = Join-Path $BK $n
        if (Test-Path $b) {
            $dst = switch ($n) { 'app.asar' {$asar} 'Claude.exe' {$claude} 'cowork-svc.exe' {$cowork} }
            Copy-Item $b $dst -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq "CN=$CERTCN" } | ForEach-Object { Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue }
    Ok "Restored original files."
}

# ---- uninstall ---------------------------------------------------------------
if ($Uninstall) {
    Info "Restoring original Claude..."
    Unregister-ScheduledTask -TaskName 'ClaudeRTL-AutoUpdate' -Confirm:$false -ErrorAction SilentlyContinue
    Restore-FromBackup
    Info "Launching Claude..."
    Start-Process explorer.exe "shell:AppsFolder\$aumid"
    if (-not $Auto) { Read-Host 'Done. Press Enter to exit' }
    exit 0
}

# ---- install -----------------------------------------------------------------
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Claude Desktop RTL  -  Windows IN-PLACE patcher"   -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
if (Test-Patched) {
    Ok "Claude is already patched - RTL is active."
    Setup-AutoUpdate
    if (-not $Auto) { Info "Launching Claude..."; Start-Process explorer.exe "shell:AppsFolder\$aumid"; Read-Host 'Press Enter to close' }
    exit 0
}
if (-not (Test-Path $PAYLOAD)) { Die "rtl-engine.js not found next to this script." }
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node -and (Test-Path "$env:ProgramFiles\nodejs\node.exe")) { $node = "$env:ProgramFiles\nodejs\node.exe" }
if (-not $node) { Die "Node.js required (https://nodejs.org)." }
Ok "Claude: $app"
Ok "Node  : $(& $node -v)"

Info "Stopping Claude + taking ownership..."
Stop-Claude
Take-Own

Info "Backing up originals (one-time)..."
New-Item -ItemType Directory -Force -Path $BK | Out-Null
foreach ($pair in @(@($asar,'app.asar'), @($claude,'Claude.exe'), @($cowork,'cowork-svc.exe'))) {
    $b = Join-Path $BK $pair[1]
    if (Test-Path $pair[0]) { Copy-Item $pair[0] $b -Force }
}
Ok "Backup at $BK"

# capture the original signer subject (to clone onto our cert) BEFORE we modify
$origSubject = $null
try { $origSubject = (Get-AuthenticodeSignature $claude).SignerCertificate.Subject } catch {}

try {
    Info "[1/5] Injecting RTL engine into app.asar..."
    $oldHash = Get-AsarHeaderHash $asar
    $tmp = Join-Path $env:TEMP ("clrtl_" + [IO.Path]::GetRandomFileName())
    cmd /c "npx --yes @electron/asar@4.2.0 extract `"$asar`" `"$tmp`"" | Out-Null
    if (-not (Test-Path (Join-Path $tmp '.vite'))) { throw "Unexpected app layout (.vite missing)." }
    $payloadText = Get-Content $PAYLOAD -Raw -Encoding UTF8
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $injected = 0
    Get-ChildItem (Join-Path $tmp '.vite') -Recurse -Filter '*.js' -File | ForEach-Object {
        $body = Get-Content $_.FullName -Raw -Encoding UTF8
        if ($body -notmatch 'CLAUDE RTL PATCH START') {
            [IO.File]::WriteAllText($_.FullName, $payloadText + "`n" + $body, $utf8); $injected++
        }
    }
    if ($injected -eq 0) { throw "No renderer JS files found." }
    cmd /c "npx --yes @electron/asar@4.2.0 pack `"$tmp`" `"$asar.new`"" | Out-Null
    if (-not (Test-Path "$asar.new")) { throw "Repack failed." }
    Move-Item -Force "$asar.new" $asar
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $newHash = Get-AsarHeaderHash $asar
    Ok "Injected into $injected file(s)."

    Info "[2/5] Patching integrity hash inside Claude.exe..."
    $bytes = [IO.File]::ReadAllBytes($claude)
    $latin = [Text.Encoding]::GetEncoding(28591)
    $hay = $latin.GetString($bytes); $needle = $latin.GetString([Text.Encoding]::ASCII.GetBytes($oldHash))
    $newB = [Text.Encoding]::ASCII.GetBytes($newHash)
    $idx = $hay.IndexOf($needle); $count = 0
    while ($idx -ge 0) { [Array]::Copy($newB,0,$bytes,$idx,$newB.Length); $count++; $idx = $hay.IndexOf($needle,$idx+$needle.Length) }
    if ($count -gt 0) { [IO.File]::WriteAllBytes($claude,$bytes); Ok "Patched hash ($count place(s))." }
    else {
        Warn "Hash string not found; disabling integrity fuse instead..."
        cmd /c "npx --yes @electron/fuses@2.1.1 write --app `"$claude`" EnableEmbeddedAsarIntegrityValidation=off" | Out-Null
        $global:LASTEXITCODE = 0
    }

    Info "[3/5] Generating self-signed cert + locating cowork cert slot..."
    $subject = if ($origSubject) { $origSubject } else { "CN=$CERTCN" }
    # locate the Anthropic cert embedded in cowork-svc (to size our cert to fit)
    $coworkBytes = [IO.File]::ReadAllBytes($cowork)
    $chay = $latin.GetString($coworkBytes)
    $anchor = $chay.IndexOf('Anthropic, PBC')
    if ($anchor -lt 0) { throw "Anthropic anchor not found in cowork-svc.exe." }
    $start = -1; $size = 0
    for ($i = $anchor; $i -ge [Math]::Max(0, $anchor - 3000); $i--) {
        if ($coworkBytes[$i] -eq 0x30 -and $coworkBytes[$i+1] -eq 0x82) {
            $len = 4 + (([int]$coworkBytes[$i+2] -shl 8) -bor [int]$coworkBytes[$i+3])
            if ($len -gt 500 -and $len -lt 4000 -and ($i + $len) -gt $anchor) { $start = $i; $size = $len; break }
        }
    }
    if ($start -lt 0) { throw "Could not locate the embedded certificate in cowork-svc.exe." }
    # generate a code-signing cert whose DER fits the slot
    $cert = $null
    for ($t = 0; $t -lt 8; $t++) {
        $c = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject -KeyAlgorithm RSA -KeyLength 2048 `
                -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter ((Get-Date).AddYears(10)) -KeyExportPolicy Exportable
        if ($c.RawData.Length -le $size) { $cert = $c; break }
        Remove-Item ("Cert:\CurrentUser\My\" + $c.Thumbprint) -Force -ErrorAction SilentlyContinue
    }
    if (-not $cert) { throw "Could not generate a certificate that fits the $size-byte slot." }
    # trust it (machine root) so the re-signed binaries validate
    $pub = New-Object Security.Cryptography.X509Certificates.X509Certificate2(,$cert.RawData)
    $root = New-Object Security.Cryptography.X509Certificates.X509Store('Root','LocalMachine')
    $root.Open('ReadWrite'); $root.Add($pub); $root.Close()
    Ok "Cert ready (DER $($cert.RawData.Length) <= slot $size)."

    Info "[4/5] Swapping the embedded cert in cowork-svc.exe..."
    $slot = New-Object byte[] $size
    [Array]::Copy($cert.RawData, 0, $slot, 0, $cert.RawData.Length)   # remainder = 0x00 padding
    [Array]::Copy($slot, 0, $coworkBytes, $start, $size)
    [IO.File]::WriteAllBytes($cowork, $coworkBytes)
    Ok "Swapped cert (size preserved)."

    Info "[5/5] Re-signing Claude.exe + cowork-svc.exe..."
    $s1 = Set-AuthenticodeSignature -FilePath $claude -Certificate $cert -HashAlgorithm SHA256
    $s2 = Set-AuthenticodeSignature -FilePath $cowork -Certificate $cert -HashAlgorithm SHA256
    if ($s1.Status -ne 'Valid' -or $s2.Status -ne 'Valid') { throw "Re-signing failed ($($s1.Status)/$($s2.Status))." }
    Ok "Both binaries re-signed and trusted."
}
catch {
    Write-Host ""
    Warn "Patch failed: $($_.Exception.Message)"
    Warn "Rolling back to the original files..."
    Restore-FromBackup
    Die "Rolled back. Nothing was left half-patched."
}

# remove our signing key (keep only the public trust)
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $subject -and $_.Thumbprint -eq $cert.Thumbprint } |
    ForEach-Object { Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue }

Setup-AutoUpdate

if (-not $Auto) {
    Info "Launching the patched Claude (with your login + RTL + Cowork)..."
    Start-Process explorer.exe "shell:AppsFolder\$aumid"
    Write-Host ""
    Ok "Done! Open Claude normally - same app: your login, your chats, + RTL."
    Write-Host "  Toggle RTL with Ctrl+Alt+R."
    Write-Host "  Auto-update is ON: re-applies the patch at logon after a Claude update."
    Write-Host "  To undo everything:  run this file with  -Uninstall"
    Read-Host 'Press Enter to close'
}
