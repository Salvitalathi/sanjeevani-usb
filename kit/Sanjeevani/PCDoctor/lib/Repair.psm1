# Sanjeevani PC Doctor - Windows repair actions
Set-StrictMode -Off

$script:EditionNames = @{
    'Core' = 'Home'; 'CoreSingleLanguage' = 'Home Single Language'; 'CoreN' = 'Home N'
    'Professional' = 'Pro'; 'ProfessionalN' = 'Pro N'; 'ProfessionalEducation' = 'Pro Education'
    'ProfessionalWorkstation' = 'Pro for Workstations'; 'Education' = 'Education'; 'Enterprise' = 'Enterprise'
}

# Looks for a Windows ISO on the USB, mounts it and returns a DISM /Source string
function Get-PDWindowsSource {
    $isoDir = Join-Path $global:PDCtx.UsbRoot 'ISO'
    $isos = @(Get-ChildItem -LiteralPath $isoDir -Recurse -Filter '*.iso' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'win(dows)?[ _-]?1[01]' })
    if ($isos.Count -eq 0) { Write-PDLog 'No Windows ISO found on the USB.' 'WARN'; return $null }
    $iso = $isos[0].FullName
    Write-PDLog "Mounting the Windows ISO: $iso" 'STEP'
    try {
        $img = Get-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
        if (-not $img -or -not $img.Attached) { $img = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop }
        $letter = ($img | Get-Volume).DriveLetter
        if (-not $letter) { throw 'the ISO got no drive letter' }
        $wim = "${letter}:\sources\install.wim"; $kind = 'WIM'
        if (-not (Test-Path $wim)) { $wim = "${letter}:\sources\install.esd"; $kind = 'ESD' }
        if (-not (Test-Path $wim)) { throw 'install.wim / install.esd not found' }
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $want = $script:EditionNames[$edition]
        $images = @(Get-WindowsImage -ImagePath $wim -ErrorAction Stop)
        $match = $null
        if ($want) { $match = $images | Where-Object { $_.ImageName -match ("\b" + [regex]::Escape($want) + "$") } | Select-Object -First 1 }
        if (-not $match) { $match = $images | Select-Object -First 1 }
        Write-PDLog ("Repair source: {0} index {1} ({2})" -f $wim, $match.ImageIndex, $match.ImageName)
        return [pscustomobject]@{ Source = ('{0}:{1}:{2}' -f $kind, $wim, $match.ImageIndex); Iso = $iso }
    } catch {
        Write-PDLog ('The ISO could not be used: ' + $_.Exception.Message) 'WARN'
        return $null
    }
}

function Invoke-PDRepairOS {
    param([switch]$SkipRestorePoint)
    $result = [ordered]@{ Dism = 'Not run'; Sfc = 'Not run'; Notes = @() }
    if (-not $SkipRestorePoint) { [void](New-PDRestorePoint 'Sanjeevani: before system repair') }

    Write-PDLog 'Step 1/2: DISM RestoreHealth (takes good files from Windows Update, needs internet) ...' 'STEP'
    $dism = "$env:WINDIR\System32\Dism.exe"
    $code = Invoke-PDProcess -FilePath $dism -Arguments '/Online /Cleanup-Image /RestoreHealth' -ProgressLabel 'DISM repair'
    if ($code -ne 0) {
        Write-PDLog 'The online repair did not work. Trying with the Windows ISO on the USB ...' 'WARN'
        $src = Get-PDWindowsSource
        if ($src) {
            $code = Invoke-PDProcess -FilePath $dism -Arguments ('/Online /Cleanup-Image /RestoreHealth /Source:"{0}" /LimitAccess' -f $src.Source) -ProgressLabel 'DISM repair (ISO)'
            try { Dismount-DiskImage -ImagePath $src.Iso -ErrorAction SilentlyContinue | Out-Null } catch { }
            if ($code -ne 0) { $result.Notes += (L 'DISM fails if the ISO''s Windows version differs from this PC''s version. Use an ISO of the same version.' 'ISO चे Windows version या PC च्या version पेक्षा वेगळे असल्यास DISM fail होतो. त्याच version चा ISO वापरा.' 'ISO का Windows version इस PC के version से अलग हो तो DISM fail होता है। उसी version का ISO इस्तेमाल करें।') }
        }
    }
    $result.Dism = if ($code -eq 0) { 'OK' } else { "Failed (code $code)" }

    Write-PDLog 'Step 2/2: SFC /scannow (replaces damaged system files) ...' 'STEP'
    $start = Get-Date
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\sfc.exe" -Arguments '/scannow' -Unicode -ProgressLabel 'SFC repair')
    $cbs = Read-PDCbsResult -Since $start
    if ($cbs.Unrepaired -gt 0) {
        $result.Sfc = (L 'some files could not be repaired ({0})' 'काही files दुरुस्त झाल्या नाहीत ({0})' 'कुछ files ठीक नहीं हुईं ({0})') -f $cbs.Unrepaired
        $result.Notes += (L 'Restart the PC and run this repair again. If it remains, run setup.exe from a Windows ISO and do a "Keep files and apps" repair install.' 'PC restart करून पुन्हा हेच repair चालवा. तरीही राहिल्यास Windows ISO मधून setup.exe चालवून "Keep files and apps" repair install करा.' 'PC restart करके यही repair फिर चलाएँ। फिर भी रहे तो Windows ISO से setup.exe चलाकर "Keep files and apps" repair install करें।')
    } elseif ($cbs.Repaired -gt 0) {
        $result.Sfc = (L '{0} files repaired' '{0} files दुरुस्त केल्या' '{0} files ठीक कीं') -f $cbs.Repaired
        $result.Notes += (L 'Restart the PC to complete the changes.' 'बदल पूर्ण होण्यासाठी PC restart करा.' 'बदलाव पूरे होने के लिए PC restart करें।')
    } else {
        $result.Sfc = (L 'no damaged files found' 'कोणतीही खराब file सापडली नाही' 'कोई खराब file नहीं मिली')
    }
    Write-PDLog ("Repair result - DISM: {0}; SFC: {1}" -f $result.Dism, $result.Sfc) 'OK'
    return [pscustomobject]$result
}

function Invoke-PDDiskCheck {
    param([string]$DriveLetter = $env:SystemDrive.TrimEnd(':'))
    Write-PDLog "Checking drive ${DriveLetter}: (online scan) ..." 'STEP'
    try {
        $r = Repair-Volume -DriveLetter $DriveLetter -Scan -ErrorAction Stop
        Write-PDLog "Scan result: $r"
        if ("$r" -eq 'NoErrorsFound') { return (L 'No file-system errors on the disk.' 'Disk मध्ये file-system errors नाहीत.' 'Disk में file-system errors नहीं हैं।') }
        Repair-Volume -DriveLetter $DriveLetter -OfflineScanAndFix -ErrorAction Stop | Out-Null
        Write-PDLog 'Errors found. The disk repair (chkdsk) runs at the next restart.' 'WARN'
        return (L 'Errors found - restart the PC; the disk is repaired before Windows starts. Back up important data first.' 'Errors सापडले - PC restart करा; Windows सुरू होण्याआधी disk दुरुस्त होईल. आधी महत्त्वाचा data backup घ्या.' 'Errors मिले - PC restart करें; Windows शुरू होने से पहले disk ठीक होगा। पहले ज़रूरी data का backup लें।')
    } catch {
        Write-PDLog ('Repair-Volume did not run, using chkdsk: ' + $_.Exception.Message) 'WARN'
        $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\chkdsk.exe" -Arguments "${DriveLetter}: /scan"
        return "chkdsk exit code $code (0 = " + (L 'no errors' 'errors नाहीत' 'errors नहीं') + ')'
    }
}

function Reset-PDWindowsUpdate {
    Write-PDLog 'Resetting the Windows Update components ...' 'STEP'
    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc'
    foreach ($s in $svcs) {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -eq 'Disabled') {
            Add-PDUndo @{ Type = 'Service'; Name = $s; StartType = 'Disabled' }
            Set-Service $s -StartupType Manual -ErrorAction SilentlyContinue
            Write-PDLog "$s service was Disabled - set to Manual."
        }
        Stop-Service $s -Force -ErrorAction SilentlyContinue
    }
    $stamp = Get-Date -Format 'yyyyMMddHHmm'
    foreach ($p in "$env:WINDIR\SoftwareDistribution", "$env:WINDIR\System32\catroot2") {
        Get-ChildItem -Path ($p + '.bak*') -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $p) {
            try { Rename-Item -LiteralPath $p -NewName ((Split-Path $p -Leaf) + ".bak$stamp") -ErrorAction Stop; Write-PDLog "$p reset." 'OK' }
            catch { Write-PDLog ("$p could not be renamed: " + $_.Exception.Message) 'WARN' }
        }
    }
    foreach ($s in 'cryptsvc', 'bits', 'wuauserv') { Start-Service $s -ErrorAction SilentlyContinue }
    Write-PDLog 'Windows Update reset done. Press "Check for updates" in Settings > Windows Update.' 'OK'
}

function Reset-PDNetwork {
    Write-PDLog 'Resetting the network settings ...' 'STEP'
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\netsh.exe" -Arguments 'winsock reset')
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\netsh.exe" -Arguments 'int ip reset')
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\ipconfig.exe" -Arguments '/flushdns')
    Write-PDLog 'Network reset done - restart the PC. (The Wi-Fi password may have to be entered again.)' 'OK'
}

function Repair-PDDefender {
    Write-PDLog 'Turning Microsoft Defender on ...' 'STEP'
    try {
        Set-Service WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service WinDefend -ErrorAction SilentlyContinue
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Write-PDLog 'Real-time protection on.' 'OK'
    } catch { Write-PDLog ('Defender did not turn on (third-party antivirus / Tamper protection?): ' + $_.Exception.Message) 'WARN' }
    try { Update-MpSignature -ErrorAction Stop; Write-PDLog 'Definitions updated.' 'OK' } catch { Write-PDLog 'Definitions not updated (internet?).' 'WARN' }
}

function Start-PDQuickVirusScan {
    Write-PDLog 'Defender quick scan started ...' 'STEP'
    try { Start-MpScan -ScanType QuickScan -ErrorAction Stop; Write-PDLog 'Quick scan finished. Any threats are shown in Windows Security.' 'OK' }
    catch { Write-PDLog ('The scan did not run: ' + $_.Exception.Message) 'WARN' }
}

# ---------------- drivers backup / restore (Windows built-in DISM + pnputil)
function Backup-PDDrivers {
    param([string]$Destination)
    if (-not $Destination) { $Destination = Join-Path $global:PDCtx.ReportDir ("Drivers-{0:yyyyMMdd-HHmm}" -f (Get-Date)) }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Write-PDLog "Third-party drivers backup: $Destination" 'STEP'
    $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\Dism.exe" -Arguments ('/Online /Export-Driver /Destination:"{0}"' -f $Destination) -ProgressLabel 'Drivers backup'
    $n = @(Get-ChildItem -LiteralPath $Destination -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count
    $size = Get-PDFolderSize $Destination
    if ($code -ne 0) { Write-PDLog "DISM export exit code $code" 'WARN' }
    Write-PDLog ("{0} drivers ({1}) backed up." -f $n, (Format-PDSize $size)) 'OK'
    return [pscustomobject]@{ Path = $Destination; Count = $n; Bytes = $size; ExitCode = $code }
}

function Restore-PDDrivers {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw ((L 'Folder not found: ' 'Folder सापडला नाही: ' 'Folder नहीं मिला: ') + $Path) }
    $n = @(Get-ChildItem -LiteralPath $Path -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count
    if ($n -eq 0) { throw (L 'This folder has no driver (.inf) files.' 'या folder मध्ये driver (.inf) files नाहीत.' 'इस folder में driver (.inf) files नहीं हैं।') }
    Write-PDLog "Installing $n drivers: $Path" 'STEP'
    $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\pnputil.exe" -Arguments ('/add-driver "{0}\*.inf" /subdirs /install' -f $Path.TrimEnd('\')) -ProgressLabel 'Drivers restore'
    # pnputil: 0 = ok, 3010 = ok but restart needed, 259 = nothing new to install
    $ok = $code -in 0, 3010, 259
    Write-PDLog ("Drivers restore {0} (code {1}). Restart the PC." -f $(if ($ok) { 'finished' } else { '- some drivers were not installed' }), $code) $(if ($ok) { 'OK' } else { 'WARN' })
    return [pscustomobject]@{ Count = $n; ExitCode = $code; Ok = $ok }
}

Export-ModuleMember -Function *
