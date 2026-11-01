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
    if ($isos.Count -eq 0) { Write-PDLog 'USB वर Windows ISO सापडला नाही.' 'WARN'; return $null }
    $iso = $isos[0].FullName
    Write-PDLog "Windows ISO mount करत आहे: $iso" 'STEP'
    try {
        $img = Get-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
        if (-not $img -or -not $img.Attached) { $img = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop }
        $letter = ($img | Get-Volume).DriveLetter
        if (-not $letter) { throw 'ISO ला drive letter मिळाले नाही' }
        $wim = "${letter}:\sources\install.wim"; $kind = 'WIM'
        if (-not (Test-Path $wim)) { $wim = "${letter}:\sources\install.esd"; $kind = 'ESD' }
        if (-not (Test-Path $wim)) { throw 'install.wim / install.esd सापडली नाही' }
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $want = $script:EditionNames[$edition]
        $images = @(Get-WindowsImage -ImagePath $wim -ErrorAction Stop)
        $match = $null
        if ($want) { $match = $images | Where-Object { $_.ImageName -match ("\b" + [regex]::Escape($want) + "$") } | Select-Object -First 1 }
        if (-not $match) { $match = $images | Select-Object -First 1 }
        Write-PDLog ("Repair source: {0} index {1} ({2})" -f $wim, $match.ImageIndex, $match.ImageName)
        return [pscustomobject]@{ Source = ('{0}:{1}:{2}' -f $kind, $wim, $match.ImageIndex); Iso = $iso }
    } catch {
        Write-PDLog ('ISO वापरता आला नाही: ' + $_.Exception.Message) 'WARN'
        return $null
    }
}

function Invoke-PDRepairOS {
    param([switch]$SkipRestorePoint)
    $result = [ordered]@{ Dism = 'Not run'; Sfc = 'Not run'; Notes = @() }
    if (-not $SkipRestorePoint) { [void](New-PDRestorePoint 'Sanjeevani: before system repair') }

    Write-PDLog 'Step 1/2: DISM RestoreHealth (Windows Update वरून चांगल्या files घेते, Internet हवे)...' 'STEP'
    $dism = "$env:WINDIR\System32\Dism.exe"
    $code = Invoke-PDProcess -FilePath $dism -Arguments '/Online /Cleanup-Image /RestoreHealth' -ProgressLabel 'DISM repair'
    if ($code -ne 0) {
        Write-PDLog 'Online repair जमला नाही. USB वरील Windows ISO वापरून प्रयत्न करतो...' 'WARN'
        $src = Get-PDWindowsSource
        if ($src) {
            $code = Invoke-PDProcess -FilePath $dism -Arguments ('/Online /Cleanup-Image /RestoreHealth /Source:"{0}" /LimitAccess' -f $src.Source) -ProgressLabel 'DISM repair (ISO)'
            try { Dismount-DiskImage -ImagePath $src.Iso -ErrorAction SilentlyContinue | Out-Null } catch { }
            if ($code -ne 0) { $result.Notes += 'ISO चे Windows version या PC च्या version पेक्षा वेगळे असल्यास DISM fail होतो. त्याच version चा ISO वापरा.' }
        }
    }
    $result.Dism = if ($code -eq 0) { 'OK' } else { "Failed (code $code)" }

    Write-PDLog 'Step 2/2: SFC /scannow (खराब system files बदलतो)...' 'STEP'
    $start = Get-Date
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\sfc.exe" -Arguments '/scannow' -Unicode -ProgressLabel 'SFC repair')
    $cbs = Read-PDCbsResult -Since $start
    if ($cbs.Unrepaired -gt 0) {
        $result.Sfc = "काही files दुरुस्त झाल्या नाहीत ($($cbs.Unrepaired))"
        $result.Notes += 'PC restart करून पुन्हा हेच repair चालवा. तरीही राहिल्यास Windows ISO मधून setup.exe चालवून "Keep files and apps" repair install करा.'
    } elseif ($cbs.Repaired -gt 0) {
        $result.Sfc = "$($cbs.Repaired) files दुरुस्त केल्या"
        $result.Notes += 'बदल पूर्ण होण्यासाठी PC restart करा.'
    } else {
        $result.Sfc = 'कोणतीही खराब file सापडली नाही'
    }
    Write-PDLog ("Repair निकाल - DISM: {0}; SFC: {1}" -f $result.Dism, $result.Sfc) 'OK'
    return [pscustomobject]$result
}

function Invoke-PDDiskCheck {
    param([string]$DriveLetter = $env:SystemDrive.TrimEnd(':'))
    Write-PDLog "Drive ${DriveLetter}: तपासत आहे (online scan)..." 'STEP'
    try {
        $r = Repair-Volume -DriveLetter $DriveLetter -Scan -ErrorAction Stop
        Write-PDLog "Scan निकाल: $r"
        if ("$r" -eq 'NoErrorsFound') { return 'Disk मध्ये file-system errors नाहीत.' }
        Repair-Volume -DriveLetter $DriveLetter -OfflineScanAndFix -ErrorAction Stop | Out-Null
        Write-PDLog 'Errors सापडले. पुढच्या restart ला disk दुरुस्ती (chkdsk) चालेल.' 'WARN'
        return 'Errors सापडले - PC restart करा; Windows सुरू होण्याआधी disk दुरुस्त होईल. आधी महत्त्वाचा data backup घ्या.'
    } catch {
        Write-PDLog ('Repair-Volume चालले नाही, chkdsk वापरतो: ' + $_.Exception.Message) 'WARN'
        $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\chkdsk.exe" -Arguments "${DriveLetter}: /scan"
        return "chkdsk exit code $code (0 = errors नाहीत)."
    }
}

function Reset-PDWindowsUpdate {
    Write-PDLog 'Windows Update components reset करत आहे...' 'STEP'
    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc'
    foreach ($s in $svcs) {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -eq 'Disabled') {
            Add-PDUndo @{ Type = 'Service'; Name = $s; StartType = 'Disabled' }
            Set-Service $s -StartupType Manual -ErrorAction SilentlyContinue
            Write-PDLog "$s service Disabled होती - Manual केली."
        }
        Stop-Service $s -Force -ErrorAction SilentlyContinue
    }
    $stamp = Get-Date -Format 'yyyyMMddHHmm'
    foreach ($p in "$env:WINDIR\SoftwareDistribution", "$env:WINDIR\System32\catroot2") {
        Get-ChildItem -Path ($p + '.bak*') -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $p) {
            try { Rename-Item -LiteralPath $p -NewName ((Split-Path $p -Leaf) + ".bak$stamp") -ErrorAction Stop; Write-PDLog "$p reset झाले." 'OK' }
            catch { Write-PDLog ("$p rename झाले नाही: " + $_.Exception.Message) 'WARN' }
        }
    }
    foreach ($s in 'cryptsvc', 'bits', 'wuauserv') { Start-Service $s -ErrorAction SilentlyContinue }
    Write-PDLog 'Windows Update reset पूर्ण. Settings > Windows Update मध्ये "Check for updates" करा.' 'OK'
}

function Reset-PDNetwork {
    Write-PDLog 'Network settings reset करत आहे...' 'STEP'
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\netsh.exe" -Arguments 'winsock reset')
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\netsh.exe" -Arguments 'int ip reset')
    [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\ipconfig.exe" -Arguments '/flushdns')
    Write-PDLog 'Network reset पूर्ण - PC restart करा. (Wi-Fi password पुन्हा टाकावा लागू शकतो.)' 'OK'
}

function Repair-PDDefender {
    Write-PDLog 'Microsoft Defender चालू करत आहे...' 'STEP'
    try {
        Set-Service WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service WinDefend -ErrorAction SilentlyContinue
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Write-PDLog 'Real-time protection चालू.' 'OK'
    } catch { Write-PDLog ('Defender चालू झाला नाही (third-party antivirus असेल / Tamper protection): ' + $_.Exception.Message) 'WARN' }
    try { Update-MpSignature -ErrorAction Stop; Write-PDLog 'Definitions update झाले.' 'OK' } catch { Write-PDLog 'Definitions update झाले नाहीत (Internet?).' 'WARN' }
}

function Start-PDQuickVirusScan {
    Write-PDLog 'Defender quick scan सुरू...' 'STEP'
    try { Start-MpScan -ScanType QuickScan -ErrorAction Stop; Write-PDLog 'Quick scan पूर्ण. Threats असतील तर Windows Security मध्ये दिसतील.' 'OK' }
    catch { Write-PDLog ('Scan चालला नाही: ' + $_.Exception.Message) 'WARN' }
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
    Write-PDLog ("{0} drivers ({1}) backup झाले." -f $n, (Format-PDSize $size)) 'OK'
    return [pscustomobject]@{ Path = $Destination; Count = $n; Bytes = $size; ExitCode = $code }
}

function Restore-PDDrivers {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Folder सापडला नाही: $Path" }
    $n = @(Get-ChildItem -LiteralPath $Path -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count
    if ($n -eq 0) { throw 'या folder मध्ये driver (.inf) files नाहीत.' }
    Write-PDLog "$n drivers install करत आहे: $Path" 'STEP'
    $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\pnputil.exe" -Arguments ('/add-driver "{0}\*.inf" /subdirs /install' -f $Path.TrimEnd('\')) -ProgressLabel 'Drivers restore'
    # pnputil: 0 = ok, 3010 = ok but restart needed, 259 = nothing new to install
    $ok = $code -in 0, 3010, 259
    Write-PDLog ("Drivers restore {0} (code {1}). PC restart करा." -f $(if ($ok) { 'पूर्ण' } else { 'काही drivers install झाले नाहीत' }), $code) $(if ($ok) { 'OK' } else { 'WARN' })
    return [pscustomobject]@{ Count = $n; ExitCode = $code; Ok = $ok }
}

Export-ModuleMember -Function *
