<#
    Sanjeevani PC Doctor - RESCUE  (for a Windows that does not start / blue screens)
    Start it from Hiren's BootCD PE: open the USB drive and run PCDoctor-Rescue.cmd.
    Works on the installed Windows while it is OFFLINE. English UI (WinPE has no Devanagari font).
#>
$ErrorActionPreference = 'Continue'
Set-StrictMode -Off
$Here = $PSScriptRoot
$UsbRoot = (Resolve-Path (Join-Path $Here '..\..\..')).Path.TrimEnd('\') + '\'
Import-Module (Join-Path $Here 'Rescue.psm1') -Force -DisableNameChecking

try { $Host.UI.RawUI.WindowTitle = 'Sanjeevani PC Doctor - Rescue' } catch { }

function Pause-RX { Write-Host ''; [void](Read-Host '   Press Enter to continue') }
function Ask-RX([string]$q) { $a = Read-Host "   $q [y/N]"; return ($a -match '^(y|yes)$') }
function Pick-RX([string]$q, [int]$max) {
    $a = Read-Host "   $q (1-$max, Enter = cancel)"
    $n = 0
    if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $max) { return $n }
    return 0
}
function Header {
    Clear-Host
    Write-Host '  ==================================================================' -ForegroundColor Cyan
    Write-Host '     SANJEEVANI  PC DOCTOR  -  RESCUE   (Windows will not start)' -ForegroundColor Cyan
    Write-Host '  ==================================================================' -ForegroundColor Cyan
    if ($script:Win) {
        Write-Host ("   Windows: {0}  {1} {2} (build {3})  PC: {4}   Internet: {5}" -f $script:Win.Drive, $script:Info.ProductName, $script:Info.DisplayVersion, $script:Win.Build, $script:Info.ComputerName, $(if ($script:Online) { 'yes' } else { 'no' })) -ForegroundColor DarkCyan
    }
    Write-Host ''
}

# ------------------------------------------------------------------ choose Windows
Header
Write-RX 'Looking for installed Windows ...' 'STEP'
$all = @(Get-RXWindows)
if (-not $all.Count) {
    Write-RX 'No installed Windows found. If the disk is not visible, it may need a storage (RST/RAID) driver,' 'ERR'
    Write-RX 'or the disk may be failing - check it with the Hard Disk tools in Hiren''s menu.' 'ERR'
    Pause-RX; exit 1
}
if ($all.Count -eq 1) { $script:Win = $all[0] }
else {
    for ($i = 0; $i -lt $all.Count; $i++) { $w = $all[$i]; Write-Host ("   {0}. {1}  build {2}  {3} GB ({4} GB free)  users: {5}" -f ($i + 1), $w.Drive, $w.Build, $w.SizeGB, $w.FreeGB, ($w.Users -join ', ')) }
    $n = Pick-RX 'Which Windows do you want to repair?' $all.Count
    if (-not $n) { exit 0 }
    $script:Win = $all[$n - 1]
}
$script:Info = Get-RXOfflineInfo $script:Win
$pcName = if ($script:Info.ComputerName) { $script:Info.ComputerName } else { 'PC' }
$ReportDir = Join-Path $UsbRoot "Reports\$pcName"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
Set-RXLogFile (Join-Path $ReportDir ("rescue-{0:yyyyMMdd-HHmm}.txt" -f (Get-Date)))
$UndoFile = Join-Path $ReportDir 'rescue-undo.json'
Write-RX ("Rescue session for {0} ({1}, build {2}) on {3}" -f $pcName, $script:Info.ProductName, $script:Win.Build, $script:Win.Drive) 'OK'
$script:Online = Test-RXInternet

# ------------------------------------------------------------------ actions
function Do-Network {
    Header
    Write-RX 'Network / drivers' 'STEP'
    if (Test-RXInternet) { $script:Online = $true; Write-RX 'Internet is working.' 'OK' }
    $n = Install-RXDriversFromWindows $script:Win
    if ($n -gt 0) { Start-Sleep 5 }
    $script:Online = Test-RXInternet
    if ($script:Online) { Write-RX 'Internet is working.' 'OK'; Pause-RX; return }
    Write-RX 'No internet yet.' 'WARN'
    Write-RX 'Wi-Fi: open PENetwork from the Hiren''s Start menu (or taskbar), pick your Wi-Fi and enter the password.'
    Write-RX 'LAN: plug in a cable. Mobile: connect the phone by USB and turn on USB tethering.'
    $pen = Get-ChildItem -LiteralPath ($env:SystemDrive + '\') -Filter 'PENetwork*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pen -and (Ask-RX 'Open PENetwork now?')) { Start-Process $pen.FullName }
    $sdio = Get-ChildItem -LiteralPath (Join-Path $UsbRoot 'Tools\Drivers') -Filter 'SDIO_x64*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sdio -and (Test-Path (Join-Path $sdio.DirectoryName 'drivers')) -and (Ask-RX 'Still no network driver? Open Snappy Driver Installer (offline packs on this USB)?')) { Start-Process $sdio.FullName -WorkingDirectory $sdio.DirectoryName }
    Pause-RX
}

function Do-BlueScreen {
    Header
    Write-RX 'Blue screen analysis' 'STEP'
    $bsv = Get-ChildItem -LiteralPath (Join-Path $UsbRoot 'Tools') -Filter 'BlueScreenView.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bsv) { $bsv = Get-ChildItem -LiteralPath ($env:SystemDrive + '\') -Filter 'BlueScreenView.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $bsv) { Write-RX 'BlueScreenView not found on the USB (Tools\Crash). Run UPDATE.cmd on a working PC.' 'ERR'; Pause-RX; return }
    $crashes = @(Get-RXCrashes -Win $script:Win -BlueScreenView $bsv.FullName)
    if (-not $crashes.Count) {
        Write-RX "No crash dumps in $($script:Win.Root)Windows\Minidump." 'WARN'
        Write-RX 'Windows may not be saving them, or the crash happens before Windows loads (then: disk / boot problem).'
        Pause-RX; return
    }
    $sum = @(Get-RXCrashSummary $crashes)
    Write-RX ("{0} crash(es) found. Most recent: {1}  {2}" -f $crashes.Count, $crashes[0].Time, $crashes[0].BugCheck)
    Write-Host ''
    for ($i = 0; $i -lt $sum.Count; $i++) {
        $s = $sum[$i]
        $tag = if ($s.IsMicrosoft) { 'Windows/Microsoft file' } else { 'THIRD-PARTY driver' }
        Write-Host ("   {0}. {1,-22} {2,3}x  {3}  [{4}]  {5}" -f ($i + 1), $s.Driver, $s.Count, $s.BugChecks, $tag, $s.Description) -ForegroundColor $(if ($s.IsMicrosoft) { 'Gray' } else { 'Yellow' })
    }
    Write-Host ''
    $third = @($sum | Where-Object { -not $_.IsMicrosoft -and $_.Driver -match '\.sys$' })
    if (-not $third.Count) {
        Write-RX 'The crashes point to Windows'' own files. That usually means faulty RAM, a failing disk, overheating,'
        Write-RX 'or corrupted system files. Next: run MemTest86 from the boot menu, check the disk (option 6), then SFC (option 4).'
        Pause-RX; return
    }
    Write-RX ("Most likely cause: {0} ({1}) - a third-party driver." -f $third[0].Driver, $(if ($third[0].Company) { $third[0].Company } else { 'unknown maker' })) 'WARN'
    Write-RX 'Disabling it lets Windows start; afterwards install that device''s latest driver from the PC maker / Windows Update.'
    if (Ask-RX ("Disable {0} in the installed Windows? (can be undone with option 9)" -f $third[0].Driver)) {
        try { $null = Disable-RXDriver -Win $script:Win -SysFile $third[0].Driver -UndoFile $UndoFile; Write-RX 'Now restart without the USB and try Windows.' 'OK' }
        catch { Write-RX $_.Exception.Message 'ERR' }
    }
    Pause-RX
}

function Do-Updates {
    Header
    Write-RX 'Stuck or bad Windows updates' 'STEP'
    Write-RX 'Step 1: undo updates that were half-installed (fixes most "Undoing changes" / restart loops).'
    if (Ask-RX 'Revert pending update actions now?') {
        $null = Invoke-RXTool 'dism.exe' @("/Image:$($script:Win.Root)", '/Cleanup-Image', '/RevertPendingActions')
    }
    Write-RX 'Step 2: updates installed in the last 14 days:' 'STEP'
    $pk = @(Get-RXRecentPackages -Win $script:Win -Days 14)
    if (-not $pk.Count) { Write-RX 'none found.'; Pause-RX; return }
    for ($i = 0; $i -lt $pk.Count; $i++) { Write-Host ("   {0}. {1:yyyy-MM-dd HH:mm}  {2}  {3}" -f ($i + 1), $pk[$i].Installed, $pk[$i].Type, $pk[$i].Id) }
    $n = Pick-RX 'Remove which update? (usually the newest one, if problems started after it)' $pk.Count
    if ($n -and (Ask-RX "Remove $($pk[$n-1].Id)?")) {
        $null = Invoke-RXTool 'dism.exe' @("/Image:$($script:Win.Root)", '/Remove-Package', "/PackageName:$($pk[$n-1].Id)")
    }
    Pause-RX
}

function Do-Sfc {
    Header
    Write-RX 'System file check (offline SFC) - 10 to 30 minutes' 'STEP'
    if (-not (Get-Command sfc.exe -ErrorAction SilentlyContinue)) { Write-RX 'sfc.exe is not available in this boot environment.' 'ERR'; Pause-RX; return }
    $null = Invoke-RXTool 'sfc.exe' @('/scannow', "/offbootdir=$($script:Win.Root)", "/offwindir=$($script:Win.Root)Windows")
    Write-RX 'If SFC says it could not repair some files, use option 5 (repair from a Windows ISO).'
    Pause-RX
}

function Do-Dism {
    Header
    Write-RX 'Repair Windows image from a Windows ISO (offline DISM)' 'STEP'
    Write-RX 'Offline repair cannot use Windows Update - it needs a Windows ISO of the SAME build as this PC.'
    $isos = @(Get-ChildItem -LiteralPath (Join-Path $UsbRoot 'ISO') -Filter *.iso -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'win' })
    if (-not $isos.Count) { Write-RX 'No Windows ISO in the USB''s ISO folder.' 'ERR'; Pause-RX; return }
    $iso = $isos[0]
    if ($isos.Count -gt 1) { for ($i = 0; $i -lt $isos.Count; $i++) { Write-Host ("   {0}. {1}" -f ($i + 1), $isos[$i].Name) }; $n = Pick-RX 'Which ISO?' $isos.Count; if (-not $n) { return }; $iso = $isos[$n - 1] }
    $sz = Find-RX7z $UsbRoot
    if (-not $sz) { Write-RX '7-Zip not found (needed to open the ISO). Run UPDATE.cmd on a working PC.' 'ERR'; Pause-RX; return }
    $cache = Join-Path $UsbRoot 'Rescue\wim'
    $wim = Export-RXInstallImage -Iso $iso.FullName -SevenZip $sz -Dest $cache
    if (-not $wim) { Write-RX 'Could not extract install.wim / install.esd from the ISO.' 'ERR'; Pause-RX; return }
    $idx = @(Get-RXWimIndexes $wim)
    $want = @{ Core = 'Home'; CoreSingleLanguage = 'Home Single Language'; Professional = 'Pro'; Education = 'Education'; Enterprise = 'Enterprise' }[$script:Info.EditionID]
    $pick = $idx | Where-Object { $want -and $_.Name -match ([regex]::Escape($want) + '$') } | Select-Object -First 1
    if (-not $pick) { for ($i = 0; $i -lt $idx.Count; $i++) { Write-Host ("   {0}. {1}" -f ($i + 1), $idx[$i].Name) }; $n = Pick-RX "Which edition is installed ($($script:Info.ProductName))?" $idx.Count; if (-not $n) { return }; $pick = $idx[$n - 1] }
    $wb = Get-RXWimBuild $wim $pick.Index
    Write-RX ("ISO: {0} build {1}   Installed Windows: build {2}" -f $pick.Name, $wb, $script:Win.Build)
    if ($wb -ne $script:Win.Build) {
        Write-RX 'The builds are different - DISM will probably fail. Get an ISO of the same Windows version' 'WARN'
        Write-RX "(e.g. $($script:Info.DisplayVersion)) or rescue your data (option 8) and reinstall."
        if (-not (Ask-RX 'Try anyway?')) { return }
    }
    $kind = if ($wim -match '\.esd$') { 'ESD' } else { 'WIM' }
    $scratch = Join-Path $script:Win.Root '$SanjeevaniScratch'
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $null = Invoke-RXTool 'dism.exe' @("/Image:$($script:Win.Root)", '/Cleanup-Image', '/RestoreHealth', "/Source:${kind}:${wim}:$($pick.Index)", '/LimitAccess', "/ScratchDir:$scratch")
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    Write-RX 'Then run option 4 (SFC) again.'
    Pause-RX
}

function Do-Chkdsk {
    Header
    Write-RX "Disk check of $($script:Win.Drive) (fixes file-system errors). Back up important data first if the disk is failing." 'STEP'
    if (Ask-RX "Run chkdsk $($script:Win.Drive) /f now?") { $null = Invoke-RXTool 'chkdsk.exe' @($script:Win.Drive, '/f') }
    Pause-RX
}

function Do-Boot {
    Header
    Write-RX 'Rebuild boot files (for "no bootable device", boot loops after cloning, missing BCD)' 'STEP'
    $dp = Join-Path $env:TEMP 'sjv_dp.txt'
    Set-Content $dp 'list volume' -Encoding ASCII
    & diskpart.exe /s $dp
    Write-Host ''
    Write-RX 'UEFI PC: choose the small FAT32 volume (100-500 MB, Hidden/System) on the SAME disk as Windows.'
    Write-RX 'Old BIOS PC: choose "System Reserved" (or the Windows volume if there is none). NEVER the USB / Ventoy volumes.'
    $vn = Read-Host '   Volume number (Enter = cancel)'
    if ($vn -notmatch '^\d+$') { return }
    $free = [char[]]'SRQPONMLK' | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
    if (-not $free) { Write-RX 'No free drive letter.' 'ERR'; Pause-RX; return }
    Set-Content $dp "select volume $vn`r`nassign letter=$free" -Encoding ASCII
    & diskpart.exe /s $dp | Out-Null
    if (-not (Test-Path "${free}:\")) { Write-RX 'Could not open that volume - nothing changed.' 'ERR'; Pause-RX; return }
    $null = Invoke-RXTool 'bcdboot.exe' @("$($script:Win.Root)Windows", '/s', "${free}:", '/f', 'ALL')
    Set-Content $dp "select volume $vn`r`nremove letter=$free" -Encoding ASCII
    & diskpart.exe /s $dp | Out-Null
    Write-RX 'Done. Remove the USB and restart.' 'OK'
    Pause-RX
}

function Do-Restore {
    Header
    $rs = Join-Path $env:SystemRoot 'System32\rstrui.exe'
    if (Test-Path $rs) { Write-RX 'Opening System Restore for the installed Windows ...' 'STEP'; Start-Process $rs "/offline:$($script:Win.Root)Windows=active" }
    else {
        Write-RX 'System Restore is not available inside this boot environment.' 'WARN'
        Write-RX 'Use Windows'' own recovery: power the PC on and off 3 times during the logo -> Advanced options -> System Restore.'
    }
    Pause-RX
}

function Do-Rescue {
    Header
    Write-RX 'Copy personal files to safety (Desktop, Documents, Downloads, Pictures, Videos, Music)' 'STEP'
    $items = @(Get-RXUserData $script:Win)
    if (-not $items.Count) { Write-RX 'No personal files found.'; Pause-RX; return }
    $total = ($items | Measure-Object Bytes -Sum).Sum
    foreach ($i in $items) { Write-Host ("   {0,-14} {1,-10} {2,10}" -f $i.User, $i.Folder, (Format-RXSize $i.Bytes)) }
    Write-RX ("Total: {0}" -f (Format-RXSize $total))
    $usbFree = ([IO.DriveInfo]::new($UsbRoot.Substring(0, 3))).AvailableFreeSpace
    $dest = Join-Path $UsbRoot ("Rescue\{0}-{1:yyyyMMdd}" -f $pcName, (Get-Date))
    Write-RX ("Destination: {0}  (free: {1})" -f $dest, (Format-RXSize $usbFree))
    $alt = Read-Host '   Press Enter to use it, or type another drive letter (e.g. E) for an external disk'
    if ($alt -match '^[A-Za-z]$') { $dest = "$($alt.ToUpper()):\Sanjeevani-Rescue\$pcName-$(Get-Date -Format yyyyMMdd)"; $usbFree = ([IO.DriveInfo]::new("$($alt.ToUpper()):\")).AvailableFreeSpace }
    if ($total -gt $usbFree - 1GB) { Write-RX 'Not enough free space there.' 'ERR'; Pause-RX; return }
    if (-not (Ask-RX 'Start copying?')) { return }
    $fail = Copy-RXUserData -Items $items -Dest $dest
    if ($fail) { Write-RX "$fail folder(s) had files that could not be read (disk errors?)." 'WARN' } else { Write-RX "All files copied to $dest" 'OK' }
    Pause-RX
}

function Do-Undo {
    Header
    Write-RX 'Undo: re-enable drivers disabled by this tool' 'STEP'
    try { $n = Undo-RXDriverChanges -Win $script:Win -UndoFile $UndoFile; Write-RX "$n change(s) undone." 'OK' } catch { Write-RX $_.Exception.Message 'ERR' }
    Pause-RX
}

# ------------------------------------------------------------------ menu
while ($true) {
    Header
    Write-Host '   1. Network: get internet / load missing drivers (Wi-Fi, LAN, display)'
    Write-Host '   2. Blue screen: find the driver that crashes Windows'
    Write-Host '   3. Updates: undo stuck updates / remove a bad update'
    Write-Host '   4. Check and repair system files (SFC)'
    Write-Host '   5. Repair Windows image from a Windows ISO (DISM)'
    Write-Host '   6. Check and fix disk errors (CHKDSK)'
    Write-Host '   7. Rebuild boot files (BCDBOOT)'
    Write-Host '   8. Save personal files to the USB / external disk'
    Write-Host '   9. Undo driver changes made by this tool'
    Write-Host '  10. System Restore'
    Write-Host '   0. Exit'
    Write-Host ''
    Write-Host '   Tip: Windows will not start? Try 3, then 2, then 4, then 7. Save your files first (8) if the disk is failing.' -ForegroundColor DarkGray
    switch (Read-Host '   Choose') {
        '1' { Do-Network } '2' { Do-BlueScreen } '3' { Do-Updates } '4' { Do-Sfc } '5' { Do-Dism }
        '6' { Do-Chkdsk } '7' { Do-Boot } '8' { Do-Rescue } '9' { Do-Undo } '10' { Do-Restore }
        '0' { Write-RX 'Rescue session ended.'; exit 0 }
    }
}
