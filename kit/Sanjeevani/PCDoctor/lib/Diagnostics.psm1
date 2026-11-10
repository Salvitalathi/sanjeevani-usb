# Sanjeevani PC Doctor - read-only diagnostics. Nothing in this file changes the PC.
Set-StrictMode -Off

function Get-PDSystemInfo {
    Write-PDLog 'Collecting system information ...' 'STEP'
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $arr = @(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue)
    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name })
    $encl = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
    $batt = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

    $memType = 'Unknown'
    if ($mem.Count -gt 0) {
        switch ([int]$mem[0].SMBIOSMemoryType) {
            20 { $memType = 'DDR' } 21 { $memType = 'DDR2' } 24 { $memType = 'DDR3' }
            26 { $memType = 'DDR4' } 34 { $memType = 'DDR5' } 30 { $memType = 'LPDDR4' } 35 { $memType = 'LPDDR5' }
        }
    }
    $slotsTotal = 0
    foreach ($a in $arr) { $slotsTotal += [int]$a.MemoryDevices }
    $maxRamGB = 0
    foreach ($a in $arr) { if ($a.MaxCapacityEx) { $maxRamGB += [math]::Round($a.MaxCapacityEx / 1MB) } elseif ($a.MaxCapacity) { $maxRamGB += [math]::Round($a.MaxCapacity / 1MB) } }

    $laptopTypes = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $isLaptop = $false
    if ($encl) { foreach ($t in $encl.ChassisTypes) { if ($laptopTypes -contains [int]$t) { $isLaptop = $true } } }
    if ($batt.Count -gt 0) { $isLaptop = $true }

    $firmware = 'BIOS (Legacy)'
    try { if ($env:firmware_type -eq 'UEFI' -or (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop).PEFirmwareType -eq 2) { $firmware = 'UEFI' } } catch { }
    $secureBoot = 'Unsupported'
    try { $secureBoot = if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'On' } else { 'Off' } } catch { }
    $tpm = [pscustomobject]@{ Present = $false; Version = '' }
    try {
        $t = Get-CimInstance -Namespace root\cimv2\Security\MicrosoftTpm -ClassName Win32_Tpm -ErrorAction Stop
        if ($t) { $tpm = [pscustomobject]@{ Present = $true; Version = (($t.SpecVersion -split ',')[0]).Trim() } }
    } catch { }

    $sysDrive = $env:SystemDrive.TrimEnd(':')
    $vol = Get-Volume -DriveLetter $sysDrive -ErrorAction SilentlyContinue
    $uptime = (Get-Date) - $os.LastBootUpTime

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        OSCaption    = $os.Caption
        OSVersion    = $os.Version
        OSBuild      = [int]$os.BuildNumber
        DisplayVer   = $cv.DisplayVersion
        EditionID    = $cv.EditionID
        Is64Bit      = [Environment]::Is64BitOperatingSystem
        InstallDate  = $os.InstallDate
        UptimeDays   = [math]::Round($uptime.TotalDays, 1)
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        CPU          = ($cpu.Name -replace '\s+', ' ').Trim()
        CPUCores     = [int]$cpu.NumberOfCores
        CPUThreads   = [int]$cpu.NumberOfLogicalProcessors
        CPUMaxMHz    = [int]$cpu.MaxClockSpeed
        CPUArch64    = ($cpu.AddressWidth -eq 64 -or $cpu.DataWidth -eq 64)
        RAMGB        = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        RAMType      = $memType
        RAMSpeed     = if ($mem.Count) { [int]$mem[0].Speed } else { 0 }
        RAMSlotsUsed = $mem.Count
        RAMSlotsTotal= $slotsTotal
        RAMMaxGB     = $maxRamGB
        GPU          = ($gpu | ForEach-Object { $_.Name }) -join ', '
        HasDedicatedGPU = [bool]($gpu | Where-Object { $_.Name -match 'NVIDIA|GeForce|Radeon RX|Radeon Pro|Arc A' })
        IsLaptop     = $isLaptop
        Firmware     = $firmware
        SecureBoot   = $secureBoot
        TPM          = $tpm
        SystemDrive  = $env:SystemDrive
        SysSizeGB    = if ($vol) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
        SysFreeGB    = if ($vol) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
        SysFreePct   = if ($vol -and $vol.Size) { [math]::Round(100 * $vol.SizeRemaining / $vol.Size, 1) } else { 0 }
        Disks        = @(Get-PDDiskHealth)
    }
}

function Get-PDDiskHealth {
    $sysDiskNum = $null
    try { $sysDiskNum = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber } catch { }
    $out = @()
    foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        if ($pd.BusType -eq 'USB') { continue }
        $rel = $null
        try { $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        $media = [string]$pd.MediaType
        if ($media -eq 'Unspecified' -or -not $media) {
            if ($pd.BusType -eq 'NVMe') { $media = 'SSD' }
            elseif ($pd.FriendlyName -match 'SSD|NVMe|Solid') { $media = 'SSD' }
            else { $media = 'Unknown' }
        }
        $out += [pscustomobject]@{
            Number      = $pd.DeviceId
            Model       = $pd.FriendlyName
            MediaType   = $media
            BusType     = [string]$pd.BusType
            SizeGB      = [math]::Round($pd.Size / 1GB)
            Health      = [string]$pd.HealthStatus
            IsSystem    = ([string]$pd.DeviceId -eq [string]$sysDiskNum)
            TempC       = if ($rel) { $rel.Temperature } else { $null }
            WearPct     = if ($rel) { $rel.Wear } else { $null }
            ReadErrors  = if ($rel) { $rel.ReadErrorsTotal } else { $null }
            PowerOnHrs  = if ($rel) { $rel.PowerOnHours } else { $null }
        }
    }
    # SMART failure prediction (works on many SATA disks even when Get-PhysicalDisk says Healthy)
    try {
        $pred = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Where-Object { $_.PredictFailure })
        if ($pred.Count -gt 0) { foreach ($d in $out) { if ($d.Health -eq 'Healthy') { $d.Health = 'SMART-Warning' } } }
    } catch { }
    return $out
}

function Get-PDStartupItems {
    $items = @()
    $sources = @(
        @{ Reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Loc = 'HKCU Run' },
        @{ Reg = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Loc = 'HKLM Run' },
        @{ Reg = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Loc = 'HKLM Run32' }
    )
    foreach ($s in $sources) {
        $key = Get-Item -Path $s.Reg -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($n in $key.GetValueNames()) {
            if (-not $n) { continue }
            $items += [pscustomobject]@{
                Name = $n; Command = [string]$key.GetValue($n); Location = $s.Loc
                ApprovedKey = $s.Approved; ValueName = $n
                Enabled = (Test-PDStartupEnabled $s.Approved $n)
            }
        }
    }
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Loc = 'Startup folder (user)' },
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Loc = 'Startup folder (all users)' }
    )
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
            $items += [pscustomobject]@{
                Name = [IO.Path]::GetFileNameWithoutExtension($file.Name); Command = $file.FullName; Location = $f.Loc
                ApprovedKey = $f.Approved; ValueName = $file.Name
                Enabled = (Test-PDStartupEnabled $f.Approved $file.Name)
            }
        }
    }
    return $items
}

function Test-PDStartupEnabled {
    param([string]$ApprovedKey, [string]$ValueName)
    try {
        $v = (Get-ItemProperty -Path $ApprovedKey -Name $ValueName -ErrorAction Stop).$ValueName
        if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 0) }   # 02/06 enabled, 03/07 disabled
    } catch { }
    return $true
}

function Get-PDInstalledApps {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $seen = @{}
    $apps = @()
    foreach ($p in $paths) {
        foreach ($a in @(Get-ItemProperty -Path $p -ErrorAction SilentlyContinue)) {
            if (-not $a.DisplayName -or $a.SystemComponent -eq 1 -or $a.ParentKeyName) { continue }
            if ($a.DisplayName -match '^(Security Update|Update for|Hotfix)') { continue }
            $k = $a.DisplayName + '|' + $a.DisplayVersion
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $apps += [pscustomobject]@{
                Name = [string]$a.DisplayName; Version = [string]$a.DisplayVersion; Publisher = [string]$a.Publisher
                SizeMB = if ($a.EstimatedSize) { [math]::Round($a.EstimatedSize / 1024) } else { 0 }
                InstallDate = [string]$a.InstallDate
                Uninstall = [string]$a.UninstallString; QuietUninstall = [string]$a.QuietUninstallString
            }
        }
    }
    return ($apps | Sort-Object Name)
}

function Get-PDLoadSnapshot {
    param([int]$Samples = 3)
    Write-PDLog 'Measuring CPU / RAM / disk load ...' 'STEP'
    $cpu = @(); $disk = @()
    for ($i = 0; $i -lt $Samples; $i++) {
        $cpu += (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
        $d = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
        if ($d) { $disk += [math]::Min(100, 100 - [double]$d.PercentIdleTime) }
        Start-Sleep -Milliseconds 700
    }
    $os = Get-CimInstance Win32_OperatingSystem
    $procs = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin '_Total', 'Idle' })
    $cores = [Environment]::ProcessorCount
    $topCpu = $procs | Sort-Object PercentProcessorTime -Descending | Select-Object -First 8 |
        ForEach-Object { [pscustomobject]@{ Name = ($_.Name -replace '#\d+$', ''); CPU = [math]::Round($_.PercentProcessorTime / $cores, 1); RAMMB = [math]::Round($_.WorkingSetPrivate / 1MB) } }
    $topRam = $procs | Sort-Object WorkingSetPrivate -Descending | Select-Object -First 8 |
        ForEach-Object { [pscustomobject]@{ Name = ($_.Name -replace '#\d+$', ''); CPU = [math]::Round($_.PercentProcessorTime / $cores, 1); RAMMB = [math]::Round($_.WorkingSetPrivate / 1MB) } }
    [pscustomobject]@{
        CPUPct  = [math]::Round(($cpu | Measure-Object -Average).Average)
        DiskPct = if ($disk.Count) { [math]::Round(($disk | Measure-Object -Average).Average) } else { $null }
        RAMPct  = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
        TopCPU  = @($topCpu)
        TopRAM  = @($topRam)
        ProcessCount = $procs.Count
    }
}

# Disk / NTFS problems, counted separately for the Windows disk and for other disks (USB sticks, card readers).
# Only error/warning levels: Ntfs 98 is mostly an informational "volume is healthy" message at every mount.
function Get-PDDiskEventCounts {
    param([datetime]$Since)
    $sysDisk = $null
    try { $sysDisk = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber } catch { }
    $sysRx = if ($null -ne $sysDisk) { '\\Harddisk' + $sysDisk + '\\' } else { '\\Harddisk0\\' }
    $drvRx = [regex]::Escape($env:SystemDrive)
    $sys = 0; $other = 0
    $ev = @()
    try { $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk'; Id = 7, 51, 153; Level = 1, 2, 3; StartTime = $Since } -MaxEvents 500 -ErrorAction Stop) } catch { }
    foreach ($e in $ev) { if ($e.Message -match $sysRx) { $sys++ } else { $other++ } }
    $nt = @()
    try { $nt += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Ntfs', 'Microsoft-Windows-Ntfs'; Id = 55, 98; Level = 1, 2, 3; StartTime = $Since } -MaxEvents 500 -ErrorAction Stop) } catch { }
    foreach ($e in $nt) { if ($e.Message -match $drvRx) { $sys++ } else { $other++ } }
    return [pscustomobject]@{ System = $sys; Other = $other }
}

function Get-PDEventSummary {
    param([int]$Days = 14)
    Write-PDLog "Checking the error logs of the last $Days days ..." 'STEP'
    $since = (Get-Date).AddDays(-$Days)
    function _count($filter) {
        try { return @(Get-WinEvent -FilterHashtable $filter -MaxEvents 500 -ErrorAction Stop).Count } catch { return 0 }
    }
    $disk = Get-PDDiskEventCounts -Since $since
    [pscustomobject]@{
        Days               = $Days
        UnexpectedShutdown = _count @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since }
        BlueScreens        = _count @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since }
        DiskErrors         = $disk.System
        OtherDiskErrors    = $disk.Other
        HardwareErrors     = _count @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = 2, 3; StartTime = $since }
        AppCrashes         = _count @{ LogName = 'Application'; Id = 1000; StartTime = $since }
    }
}

# Device Manager problem codes, in plain words (en / mr / hi)
$script:CmCodes = @{
    1 = @('the device is not configured correctly', 'device नीट configure झाले नाही', 'device ठीक से configure नहीं हुआ')
    3 = @('the driver is damaged or memory is short', 'driver खराब आहे किंवा memory कमी पडते', 'driver खराब है या memory कम पड़ती है')
    10 = @('the device cannot start', 'device सुरू होत नाही', 'device शुरू नहीं होता')
    12 = @('a resource conflict with another device', 'दुसऱ्या device शी resources चा संघर्ष', 'दूसरे device से resources का टकराव')
    14 = @('the PC must be restarted', 'PC restart करावा लागेल', 'PC restart करना होगा')
    18 = @('reinstall the driver', 'driver पुन्हा install करा', 'driver फिर से install करें')
    19 = @('a registry error', 'registry मध्ये चूक', 'registry में गड़बड़')
    24 = @('the device is not connected properly', 'device नीट जोडलेले नाही', 'device ठीक से जुड़ा नहीं है')
    28 = @('no driver installed', 'driver install केलेला नाही', 'driver install नहीं है')
    31 = @('the driver does not load', 'driver load होत नाही', 'driver load नहीं होता')
    32 = @('the driver is disabled', 'driver बंद (disabled) आहे', 'driver बंद (disabled) है')
    37 = @('the driver does not start', 'driver सुरू होत नाही', 'driver शुरू नहीं होता')
    39 = @('the driver is damaged or missing', 'driver खराब आहे किंवा सापडत नाही', 'driver खराब है या नहीं मिलता')
    43 = @('the hardware reported a fault (check the device / cable)', 'hardware ने बिघाड कळवला (device / cable तपासा)', 'hardware ने खराबी बताई (device / cable जाँचें)')
    48 = @('Windows has blocked this driver', 'हा driver Windows ने block केला आहे', 'यह driver Windows ने block किया है')
    52 = @('the driver''s digital signature cannot be verified', 'driver ची digital signature पडताळता येत नाही', 'driver की digital signature जाँची नहीं जा सकती')
}

function Get-PDDriverProblems {
    # 22 = disabled by the user, 45 = device not plugged in right now: not problems
    @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -notin 0, 22, 45 } |
        ForEach-Object {
            $c = [int]$_.ConfigManagerErrorCode
            [pscustomobject]@{
                Name = $(if ($_.Name) { $_.Name } else { $_.DeviceID }); Code = $c; Class = [string]$_.PNPClass
                Meaning = $(if ($script:CmCodes[$c]) { $m = $script:CmCodes[$c]; L $m[0] $m[1] $m[2] } else { (L 'problem code ' 'समस्या code ' 'समस्या code ') + $c })
                HardwareId = @($_.HardwareID)[0]
            }
        })
}

# Installed third-party drivers for the classes that matter most; flags old and unsigned ones.
function Get-PDDriverAge {
    param([int]$OldYears = 3)
    $classes = 'DISPLAY', 'NET', 'MEDIA', 'BLUETOOTH', 'HDC', 'SCSIADAPTER', 'USB', 'CAMERA', 'IMAGE', 'BIOMETRIC', 'MOUSE', 'KEYBOARD'
    $cut = (Get-Date).AddYears(-$OldYears)
    $out = @()
    foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) {
        if (-not $d.DeviceName -or -not $d.DriverVersion) { continue }
        if ($classes -notcontains ([string]$d.DeviceClass).ToUpper()) { continue }
        if ($d.DriverProviderName -match '^Microsoft') { continue }   # inbox drivers are serviced by Windows Update
        $date = $d.DriverDate
        $out += [pscustomobject]@{
            Name = $d.DeviceName; Class = [string]$d.DeviceClass; Provider = [string]$d.DriverProviderName
            Version = [string]$d.DriverVersion; Date = $date
            Old = [bool]($date -and $date -lt $cut); Unsigned = ($d.IsSigned -eq $false)
        }
    }
    return ($out | Sort-Object Date)
}

# Driver updates Microsoft offers for this PC (Windows Update "Optional updates"). Read-only; installs nothing.
function Get-PDWindowsUpdateDrivers {
    Write-PDLog 'Looking for drivers on Windows Update (1-2 minutes, needs internet) ...' 'STEP'
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $res = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        $list = @()
        foreach ($u in $res.Updates) {
            $list += [pscustomobject]@{ Title = [string]$u.Title; Class = [string]$u.DriverClass; Date = $u.DriverVerDate }
        }
        Write-PDLog ("Windows Update: {0} driver updates available" -f $list.Count) 'OK'
        return $list
    } catch {
        Write-PDLog ('Windows Update could not be reached: ' + $_.Exception.Message) 'WARN'
        return $null
    }
}

function Get-PDSecurityStatus {
    $av = @()
    try { $av = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $_.displayName }) } catch { }
    $def = $null
    try { $def = Get-MpComputerStatus -ErrorAction Stop } catch { }
    [pscustomobject]@{
        AntivirusProducts = @($av | Select-Object -Unique)
        DefenderRealtime  = if ($def) { [bool]$def.RealTimeProtectionEnabled } else { $null }
        DefenderMode      = if ($def) { [string]$def.AMRunningMode } else { '' }
        SignatureAgeDays  = if ($def) { [int]$def.AntivirusSignatureAge } else { $null }
    }
}

function Test-PDPendingReboot {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    try {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
        if ($v) { return $true }
    } catch { }
    return $false
}

function Get-PDImageHealth {
    Write-PDLog 'Checking the Windows image (component store) ...' 'STEP'
    try {
        $r = Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop
        Write-PDLog ('Image health: ' + $r.ImageHealthState)
        return [string]$r.ImageHealthState     # Healthy / Repairable / NonRepairable
    } catch {
        Write-PDLog ('Image health check failed: ' + $_.Exception.Message) 'WARN'
        return 'Unknown'
    }
}

# Deep check: sfc /verifyonly (read-only), then read CBS.log for violations.
function Test-PDSystemFiles {
    Write-PDLog 'Checking system files (sfc /verifyonly) - can take 10 to 20 minutes ...' 'STEP'
    $start = Get-Date
    $null = Invoke-PDProcess -FilePath "$env:WINDIR\System32\sfc.exe" -Arguments '/verifyonly' -Unicode -ProgressLabel 'System files'
    return (Read-PDCbsResult -Since $start)
}

function Read-PDCbsResult {
    param([datetime]$Since)
    $cbs = "$env:WINDIR\Logs\CBS\CBS.log"
    $res = [pscustomobject]@{ Corrupt = 0; Repaired = 0; Unrepaired = 0; Files = @() }
    if (-not (Test-Path $cbs)) { return $res }
    $lines = @()
    try {
        $fs = [IO.File]::Open($cbs, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs)
        while (-not $sr.EndOfStream) {
            $l = $sr.ReadLine()
            if ($l -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' -and $l.Contains('[SR]')) {
                $t = [datetime]::ParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $null)
                if ($t -ge $Since.AddSeconds(-5)) { $lines += $l }
            }
        }
        $sr.Close(); $fs.Close()
    } catch { Write-PDLog ('CBS.log could not be read: ' + $_.Exception.Message) 'WARN' }
    foreach ($l in $lines) {
        if ($l -match 'Cannot repair member file') { $res.Unrepaired++ }
        elseif ($l -match 'Repairing corrupted file|Repaired file') { $res.Repaired++ }
        elseif ($l -match 'do not match|corrupt') { $res.Corrupt++ }
        $m = [regex]::Match($l, 'file \[l:\d+\]"([^"]+)"')
        if ($m.Success -and $res.Files.Count -lt 30) { $res.Files += $m.Groups[1].Value }
    }
    $res.Files = @($res.Files | Select-Object -Unique)
    return $res
}

function Get-PDTempSize {
    $paths = @($env:TEMP, "$env:WINDIR\Temp", "$env:WINDIR\SoftwareDistribution\Download",
               "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue")
    $sum = 0
    foreach ($p in $paths) { $sum += Get-PDFolderSize $p }
    return $sum
}

function Get-PDActivePowerPlan {
    try {
        $p = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -Filter 'IsActive=True' -ErrorAction Stop
        return [pscustomobject]@{ Name = $p.ElementName; Guid = ($p.InstanceID -replace '.*\{(.*)\}', '$1') }
    } catch { return [pscustomobject]@{ Name = 'Unknown'; Guid = '' } }
}

function Test-PDVisualEffectsDefault {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -ErrorAction SilentlyContinue).VisualFXSetting
    return ($null -eq $v -or $v -eq 0 -or $v -eq 1)
}

# ------------------------------------------------------------------------
# Full scan: collects everything and turns it into a list of findings.
# ------------------------------------------------------------------------
function Invoke-PDScan {
    param([switch]$Deep, [string]$DataDir)
    $t0 = Get-Date
    Set-PDProgress 5 (L 'System information' 'System माहिती' 'System जानकारी')
    $info = Get-PDSystemInfo
    Set-PDProgress 20 'Startup programs'
    $startup = @(Get-PDStartupItems)
    Set-PDProgress 30 'Installed apps'
    $apps = @(Get-PDInstalledApps)
    Set-PDProgress 40 (L 'Measuring speed' 'वेग मोजणी' 'स्पीड माप')
    $load = Get-PDLoadSnapshot
    Set-PDProgress 55 'Error logs'
    $events = Get-PDEventSummary
    Set-PDProgress 65 'Drivers / Security'
    $drivers = @(Get-PDDriverProblems)
    $drvAge = @(Get-PDDriverAge)
    $wuDrivers = $null
    if ($Deep) { $wuDrivers = Get-PDWindowsUpdateDrivers }
    $sec = Get-PDSecurityStatus
    $pending = Test-PDPendingReboot
    Set-PDProgress 72 'Temp files'
    $junkCats = @()
    if (Get-Command Get-PDJunkCategories -ErrorAction SilentlyContinue) {
        $junkCats = @(Get-PDJunkCategories | Where-Object { $_.Id -ne 'winold' } | ForEach-Object { [pscustomobject]@{ Mr = $_.Mr; En = $_.En; Hi = $_.Hi; Bytes = (Get-PDPathBytes $_.Paths $_.Filter) } } | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending)
        $tempBytes = [double]($junkCats | Measure-Object Bytes -Sum).Sum
    } else { $tempBytes = Get-PDTempSize }
    $winOld = Get-PDFolderSize "$env:SystemDrive\Windows.old"
    $power = Get-PDActivePowerPlan
    Set-PDProgress 80 'Windows image'
    $image = Get-PDImageHealth
    $sfc = $null
    if ($Deep) { $sfc = Test-PDSystemFiles }
    Set-PDProgress 95 (L 'Analysis' 'विश्लेषण' 'विश्लेषण')

    $bloat = @()
    if ($DataDir -and (Test-Path (Join-Path $DataDir 'bloat.json'))) {
        $bl = Get-Content (Join-Path $DataDir 'bloat.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $installedAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        foreach ($b in $bl.packages) { foreach ($n in $installedAppx) { if ($n -like $b.name) { $bloat += [pscustomobject]@{ Name = $n; Label = $b.label; Default = [bool]$b.default } } } }
    }
    $appAdvice = @()
    if ($DataDir) { $appAdvice = @(Get-PDAppAdvice -Apps $apps -Info $info -DataDir $DataDir) }

    $f = New-Object System.Collections.ArrayList
    # Kind = who can fix it: auto (One-Click Optimize), button (a PC Doctor button), restart, you (the user),
    #        hw (hardware / OS upgrade needed), none (information only - costs no points)
    function add($sev, $cat, $title, $detail, $fix, $kind = $null, $pts = $null) {
        if ($null -eq $pts) { $pts = switch ($sev) { 'Critical' { 15 } 'Warning' { 6 } 'Info' { 2 } default { 0 } } }
        if (-not $kind) {
            $kind = if ($fix -in 'cleanup', 'startup', 'power', 'visual', 'debloat') { 'auto' }
                    elseif ($fix -in 'repair-os', 'chkdsk', 'wureset', 'defender', 'drivers', 'bsod', 'storage', 'registry') { 'button' }
                    else { 'you' }
        }
        if ($kind -eq 'none') { $pts = 0 }
        [void]$f.Add([pscustomobject]@{ Severity = $sev; Category = $cat; Title = $title; Detail = $detail; FixId = $fix; Kind = $kind; Points = [int]$pts })
    }

    # --- storage
    if ($info.SysFreeGB -lt 10 -or $info.SysFreePct -lt 10) {
        add 'Critical' 'Storage' ((L '{0} drive is almost full' '{0} drive जवळजवळ भरला आहे' '{0} drive लगभग भर गया है') -f $info.SystemDrive) ((L 'Only {0} GB ({1}%) left. This makes the PC very slow and updates fail.' 'फक्त {0} GB ({1}%) जागा शिल्लक. यामुळे PC खूप slow होतो आणि updates fail होतात.' 'सिर्फ़ {0} GB ({1}%) जगह बची है। इससे PC बहुत slow होता है और updates fail होते हैं।') -f $info.SysFreeGB, $info.SysFreePct) 'storage'
    } elseif ($info.SysFreePct -lt 20) {
        add 'Warning' 'Storage' ((L 'Low space on the {0} drive' '{0} drive वर जागा कमी आहे' '{0} drive पर जगह कम है') -f $info.SystemDrive) ((L '{0} GB ({1}%) left. Keep at least 20% free.' '{0} GB ({1}%) शिल्लक. किमान 20% जागा मोकळी ठेवा.' '{0} GB ({1}%) बची है। कम से कम 20% जगह खाली रखें।') -f $info.SysFreeGB, $info.SysFreePct) 'storage'
    }
    if ($tempBytes -gt 1GB) {
        $parts = ($junkCats | Select-Object -First 4 | ForEach-Object { "$((Get-PDJunkName $_) -replace ' - .*$', '') $(Format-PDSize $_.Bytes)" }) -join ' · '
        add 'Info' 'Storage' ("Junk files: {0}" -f (Format-PDSize $tempBytes)) ((L 'One-Click Optimize can free them. {0}' 'One-Click Optimize ने मोकळे करता येतील. {0}' 'One-Click Optimize से खाली हो सकती हैं। {0}') -f $parts) 'cleanup'
    }
    if ($winOld -gt 1GB) { add 'Info' 'Storage' (L 'Files of the previous Windows (Windows.old) are present' 'जुन्या Windows (Windows.old) च्या files आहेत' 'पुराने Windows (Windows.old) की files हैं') ((L '{0} can be freed (going back to the old Windows will no longer be possible).' '{0} जागा मोकळी करता येईल (पुन्हा जुन्या Windows वर जाता येणार नाही).' '{0} जगह खाली हो सकती है (पुराने Windows पर वापस नहीं जा सकेंगे)।') -f (Format-PDSize $winOld)) 'cleanup' }

    # --- disks
    foreach ($d in $info.Disks) {
        if ($d.Health -ne 'Healthy') {
            add 'Critical' 'Hardware' ((L 'Disk at risk: {0}' 'Disk धोक्यात: {0}' 'Disk खतरे में: {0}') -f $d.Model) ((L 'Disk health: {0}. Back up the data now and plan to replace the disk.' 'Disk health: {0}. लगेच data backup घ्या आणि disk बदलण्याचा विचार करा.' 'Disk health: {0}. तुरंत data का backup लें और disk बदलने की सोचें।') -f $d.Health) 'backup'
        }
        if ($d.TempC -and $d.TempC -ge 55) { add 'Warning' 'Hardware' ((L 'Disk is hot ({0}°C): {1}' 'Disk गरम आहे ({0}°C): {1}' 'Disk गर्म है ({0}°C): {1}') -f $d.TempC, $d.Model) (L 'Check the cooling / fan / airflow.' 'Cooling / fan / हवा खेळती आहे का ते तपासा.' 'Cooling / fan / हवा का बहाव जाँचें।') $null }
        if ($d.WearPct -and $d.WearPct -ge 80) { add 'Warning' 'Hardware' ((L 'SSD is worn ({0}% wear)' 'SSD झिजली आहे ({0}% wear)' 'SSD घिस गई है ({0}% wear)') -f $d.WearPct) (L 'Keep a backup and get ready to replace the SSD soon.' 'Backup ठेवा आणि लवकरच SSD बदलण्याची तयारी करा.' 'Backup रखें और जल्द SSD बदलने की तैयारी करें।') 'backup' }
    }
    $sysDisk = @($info.Disks | Where-Object { $_.IsSystem })[0]
    if ($sysDisk -and $sysDisk.MediaType -eq 'HDD') {
        add 'Warning' 'Speed' (L 'Windows is on an old hard disk (HDD)' 'Windows जुन्या Hard Disk (HDD) वर आहे' 'Windows पुराने Hard Disk (HDD) पर है') (L 'This is the biggest reason for a slow PC. With an SSD the PC runs 3 to 5 times faster (see the advice page).' 'PC slow असण्याचे हे सर्वात मोठे कारण आहे. SSD लावल्यास PC 3 ते 5 पट वेगाने चालेल (सल्ला page पहा).' 'PC slow होने का यह सबसे बड़ा कारण है। SSD लगाने पर PC 3 से 5 गुना तेज़ चलेगा (सलाह page देखें)।') 'advisor'
    }

    # --- memory / load
    if ($info.RAMGB -lt 3.5) { add 'Critical' 'Speed' ((L 'Only {0} GB RAM' 'RAM फक्त {0} GB आहे' 'RAM सिर्फ़ {0} GB है') -f $info.RAMGB) (L 'Windows 10/11 needs at least 8 GB RAM. Add RAM or use a light OS (advice page).' 'Windows 10/11 साठी किमान 8 GB RAM योग्य. RAM वाढवा किंवा हलकी OS वापरा (सल्ला page).' 'Windows 10/11 के लिए कम से कम 8 GB RAM सही है। RAM बढ़ाएँ या हल्का OS लें (सलाह page)।') 'advisor' 'hw' }
    elseif ($info.RAMGB -lt 7) { add 'Warning' 'Speed' ((L '{0} GB RAM' 'RAM {0} GB आहे' 'RAM {0} GB है') -f $info.RAMGB) (L '8 GB is better for today''s browsers / apps. Add RAM if there is a free slot.' 'आजच्या browsers/apps साठी 8 GB चांगली. Free slot असल्यास RAM वाढवा.' 'आज के browsers/apps के लिए 8 GB अच्छी है। Free slot हो तो RAM बढ़ाएँ।') 'advisor' 'hw' }
    if ($load.RAMPct -ge 85) { add 'Warning' 'Speed' ((L 'RAM {0}% in use' 'RAM {0}% वापरली जात आहे' 'RAM {0}% इस्तेमाल हो रही है') -f $load.RAMPct) ((L 'Using the most RAM: ' 'सर्वात जास्त RAM वापरणारे: ' 'सबसे ज़्यादा RAM लेने वाले: ') + (($load.TopRAM | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.RAMMB) MB)" }) -join ', ')) 'startup' }
    if ($load.CPUPct -ge 60) { add 'Warning' 'Speed' ((L 'CPU constantly {0}% busy' 'CPU सतत {0}% busy आहे' 'CPU लगातार {0}% busy है') -f $load.CPUPct) ((L 'Most CPU: ' 'सर्वात जास्त CPU: ' 'सबसे ज़्यादा CPU: ') + (($load.TopCPU | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.CPU)%)" }) -join ', ')) $null }
    if ($load.DiskPct -ge 80) { add 'Warning' 'Speed' ((L 'Disk {0}% busy' 'Disk {0}% busy आहे' 'Disk {0}% busy है') -f $load.DiskPct) (L 'On an HDD this is the main cause of slowness. Reduce startup programs / fit an SSD.' 'HDD असल्यास हे slowness चे मुख्य कारण. Startup programs कमी करा / SSD लावा.' 'HDD हो तो यह slowness का मुख्य कारण है। Startup programs कम करें / SSD लगाएँ।') 'startup' }

    $enabledStartup = @($startup | Where-Object { $_.Enabled }).Count
    if ($enabledStartup -gt 6) { add 'Warning' 'Speed' ((L '{0} programs start with Windows' '{0} programs Windows सोबत सुरू होतात' '{0} programs Windows के साथ शुरू होते हैं') -f $enabledStartup) (L 'Turning off unneeded startup programs makes the PC start faster and saves RAM.' 'अनावश्यक startup programs बंद केल्यास PC लवकर सुरू होईल आणि RAM वाचेल.' 'बेकार startup programs बंद करने से PC जल्दी शुरू होगा और RAM बचेगी।') 'startup' }
    if ($power.Guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') { add 'Info' 'Speed' (L 'Power plan is set to "Power saver"' 'Power plan "Power saver" वर आहे' 'Power plan "Power saver" पर है') (L 'This deliberately slows the CPU down.' 'यामुळे CPU मुद्दाम हळू चालतो.' 'इससे CPU जानबूझकर धीमा चलता है।') 'power' }
    if ((Test-PDVisualEffectsDefault) -and ($info.RAMGB -le 4 -or -not $info.HasDedicatedGPU)) { add 'Info' 'Speed' (L 'Animations / transparency effects are on' 'Animations / transparency effects चालू आहेत' 'Animations / transparency effects चालू हैं') (L 'On a light PC, windows open faster with them off.' 'हलक्या PC वर हे बंद केल्याने windows लवकर उघडतात.' 'हल्के PC पर इन्हें बंद करने से windows जल्दी खुलती हैं।') 'visual' }
    if ($bloat.Count -gt 0) { add 'Info' 'Speed' ((L '{0} unneeded pre-installed apps' '{0} अनावश्यक pre-installed apps आहेत' '{0} बेकार pre-installed apps हैं') -f $bloat.Count) (($bloat | Select-Object -First 5 | ForEach-Object { $_.Label }) -join ', ') 'debloat' }
    $pup = @($appAdvice | Where-Object { $_.Kind -eq 'pup' })
    if ($pup.Count -gt 0) { add 'Warning' 'Software' ((L '{0} unwanted / dangerous programs found' '{0} नको असलेले / धोकादायक programs सापडले' '{0} अनचाहे / खतरनाक programs मिले') -f $pup.Count) (($pup | ForEach-Object { $_.App }) -join ', ') 'advisor' }

    # --- system health
    switch ($image) {
        'Repairable'    { add 'Critical' 'Repair' (L 'The Windows system image is damaged (repairable)' 'Windows system image खराब आहे (दुरुस्त होऊ शकतो)' 'Windows system image खराब है (ठीक हो सकता है)') (L 'Run the DISM + SFC repair.' 'DISM + SFC repair चालवा.' 'DISM + SFC repair चलाएँ।') 'repair-os' }
        'NonRepairable' { add 'Critical' 'Repair' (L 'The Windows system image is damaged beyond repair' 'Windows system image दुरुस्त होण्यापलीकडे खराब आहे' 'Windows system image मरम्मत से परे खराब है') (L 'Do a "Repair install" from a Windows 11 ISO (data stays) or a fresh install.' 'Windows 11 ISO वापरून "Repair install" करा (data राहतो) किंवा fresh install.' 'Windows 11 ISO से "Repair install" करें (data रहता है) या fresh install.') 'repair-os' }
    }
    if ($sfc -and ($sfc.Corrupt + $sfc.Unrepaired) -gt 0) { add 'Critical' 'Repair' (L 'Corrupt system files found' 'खराब (corrupt) system files सापडल्या' 'खराब (corrupt) system files मिलीं') ((L '{0} files. Repair them from the Repair page.' '{0} files. Repair page मधून दुरुस्त करा.' '{0} files. Repair page से ठीक करें।') -f ($sfc.Corrupt + $sfc.Unrepaired)) 'repair-os' }
    if ($events.DiskErrors -gt 0) { add 'Critical' 'Hardware' ((L 'Errors on the Windows disk: {1} times in the last {0} days' 'Windows disk वर errors: मागील {0} दिवसांत {1} वेळा' 'Windows disk पर errors: पिछले {0} दिनों में {1} बार') -f $events.Days, $events.DiskErrors) (L 'Run a disk check (chkdsk), see the health in Tools guide → CrystalDiskInfo, and back up first.' 'Disk check (chkdsk) चालवा, Tools मार्गदर्शक → CrystalDiskInfo ने health पहा, आणि आधी backup घ्या.' 'Disk check (chkdsk) चलाएँ, Tools गाइड → CrystalDiskInfo से health देखें, और पहले backup लें।') 'chkdsk' }
    if ($events.OtherDiskErrors -gt 0) { add 'Info' 'Hardware' ((L 'Errors on another disk / pendrive: {0} times' 'दुसऱ्या disk / pendrive वर errors: {0} वेळा' 'दूसरे disk / pendrive पर errors: {0} बार') -f $events.OtherDiskErrors) (L 'Errors of a USB pendrive / card reader / external disk - they appear when it is unplugged without "Safely remove". No risk to the Windows disk.' 'USB pendrive / card reader / external disk चे errors. "Safely remove" न करता काढल्यास असे येतात. Windows disk ला धोका नाही.' 'USB pendrive / card reader / external disk के errors। "Safely remove" किए बिना निकालने पर ऐसे आते हैं। Windows disk को खतरा नहीं।') $null 'none' }
    if ($events.BlueScreens -gt 0) { add 'Warning' 'Stability' ((L 'Blue screen crash: {0} times' 'Blue screen crash: {0} वेळा' 'Blue screen crash: {0} बार') -f $events.BlueScreens) (L 'Find the cause (driver) with Tools guide → BlueScreenView. Run a RAM test (MemTest86).' 'Tools मार्गदर्शक → BlueScreenView ने कारण (driver) शोधा. RAM test (MemTest86) चालवा.' 'Tools गाइड → BlueScreenView से कारण (driver) खोजें। RAM test (MemTest86) चलाएँ।') 'bsod' }
    if ($events.UnexpectedShutdown -gt 2) { add 'Warning' 'Stability' ((L 'Sudden shutdowns: {0} times' 'अचानक बंद पडणे: {0} वेळा' 'अचानक बंद होना: {0} बार') -f $events.UnexpectedShutdown) (L 'Check the power supply / battery / overheating (Tools guide → HWiNFO, Prime95).' 'Power supply / battery / overheating तपासा (Tools मार्गदर्शक → HWiNFO, Prime95).' 'Power supply / battery / overheating जाँचें (Tools गाइड → HWiNFO, Prime95)।') $null 'hw' }
    if ($events.HardwareErrors -gt 0) { add 'Warning' 'Hardware' "Hardware (WHEA) errors: $($events.HardwareErrors)" (L 'CPU / RAM / PCIe hardware trouble. Run a stress test and a RAM test (Tools guide).' 'CPU/RAM/PCIe hardware त्रास. Stress test आणि RAM test चालवा (Tools मार्गदर्शक).' 'CPU/RAM/PCIe hardware की दिक्कत। Stress test और RAM test चलाएँ (Tools गाइड)।') $null 'hw' }
    if ($drivers.Count -gt 0) { add 'Warning' 'Drivers' ((L 'Drivers of {0} devices are not right' '{0} devices चे drivers नीट नाहीत' '{0} devices के drivers ठीक नहीं हैं') -f $drivers.Count) (($drivers | Select-Object -First 4 | ForEach-Object { "$($_.Name): $($_.Meaning)" }) -join ' · ') 'drivers' }
    $unsigned = @($drvAge | Where-Object { $_.Unsigned })
    if ($unsigned.Count -gt 0) { add 'Warning' 'Drivers' ((L 'Unsigned drivers: {0}' 'Signature नसलेले drivers: {0}' 'बिना signature के drivers: {0}') -f $unsigned.Count) ((($unsigned | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ') + (L ' - nobody has verified them; install the driver from the maker''s site.' ' - कोणी तपासलेले नाहीत; निर्मात्याच्या site वरचा driver लावा.' ' - किसी ने जाँचे नहीं; निर्माता की site का driver लगाएँ।')) 'drivers' }
    $old = @($drvAge | Where-Object { $_.Old })
    if ($old.Count -gt 0) { add 'Info' 'Drivers' ((L '{0} important drivers older than 3 years' '{0} महत्त्वाचे drivers 3 वर्षांपेक्षा जुने' '{0} ज़रूरी drivers 3 साल से पुराने') -f $old.Count) ((($old | Select-Object -First 4 | ForEach-Object { "$($_.Name) ($(if ($_.Date) { $_.Date.Year }))" }) -join ', ') + (L '. If the device works well there is no need to change them.' '. Device नीट चालत असेल तर बदलायची गरज नाही.' '। Device ठीक चल रहा हो तो बदलने की ज़रूरत नहीं।')) 'drivers' 'none' }
    if ($wuDrivers -and $wuDrivers.Count -gt 0) { add 'Info' 'Drivers' ((L '{0} driver updates available in Windows Update' 'Windows Update मध्ये {0} driver updates उपलब्ध' 'Windows Update में {0} driver updates उपलब्ध') -f $wuDrivers.Count) ((($wuDrivers | Select-Object -First 3 | ForEach-Object { $_.Title }) -join ' · ') + (L ' - checked by Microsoft, the safest.' ' - Microsoft ने तपासलेले, सर्वात सुरक्षित.' ' - Microsoft द्वारा जाँचे, सबसे सुरक्षित।')) 'drivers' }

    # --- security
    $avs = @($sec.AntivirusProducts | Where-Object { $_ -notmatch 'Windows Defender|Microsoft Defender' })
    if ($avs.Count -gt 1) { add 'Warning' 'Security' (L 'More than one antivirus is installed' 'एकापेक्षा जास्त antivirus install आहेत' 'एक से ज़्यादा antivirus install हैं') (($avs -join ', ') + (L ' - two antivirus programs fight each other and slow the PC. Keep one.' ' - दोन antivirus एकमेकांशी भांडतात आणि PC slow करतात. एकच ठेवा.' ' - दो antivirus आपस में टकराते हैं और PC slow करते हैं। एक ही रखें।')) 'advisor' }
    if ($avs.Count -eq 0 -and $sec.DefenderRealtime -eq $false) { add 'Critical' 'Security' (L 'Antivirus protection is off' 'Antivirus protection बंद आहे' 'Antivirus protection बंद है') (L 'Turn on Microsoft Defender real-time protection.' 'Microsoft Defender real-time protection चालू करा.' 'Microsoft Defender real-time protection चालू करें।') 'defender' }
    if ($sec.SignatureAgeDays -gt 7 -and $avs.Count -eq 0) { add 'Warning' 'Security' ((L 'Defender definitions are {0} days old' 'Defender definitions {0} दिवस जुने आहेत' 'Defender definitions {0} दिन पुरानी हैं') -f $sec.SignatureAgeDays) (L 'Update them.' 'Update करा.' 'Update करें।') 'defender' }

    # --- registry (targeted checks only - see Registry.psm1)
    $regIssues = @()
    if (Get-Command Get-PDRegistryIssues -ErrorAction SilentlyContinue) {
        try { $regIssues = @(Get-PDRegistryIssues) } catch { }
        $mal = @($regIssues | Where-Object { $_.Kind -eq 'malware' -and $_.Severity -eq 'Critical' })
        $brk = @($regIssues | Where-Object { $_.Kind -eq 'broken' })
        if ($mal.Count) { add 'Critical' 'Security' ((L 'Virus-like changes in the registry: {0}' 'Registry मध्ये virus सारखे बदल: {0}' 'Registry में virus जैसे बदलाव: {0}') -f $mal.Count) (($mal | Select-Object -First 3 | ForEach-Object { $_.Title }) -join ' · ') 'registry' }
        if ($brk.Count) { add 'Info' 'Registry' ((L '{0} broken registry entries' '{0} तुटलेल्या registry entries' '{0} टूटी registry entries') -f $brk.Count) (($brk | Select-Object -First 3 | ForEach-Object { $_.Title }) -join ' · ') 'registry' }
    }

    # --- OS lifecycle
    if ($info.OSBuild -lt 10240) { add 'Critical' 'OS' ((L '{0} no longer gets security updates' '{0} ला आता security updates मिळत नाहीत' '{0} को अब security updates नहीं मिलते') -f $info.OSCaption) (L 'See the right OS for this PC on the advice page.' 'सल्ला page मध्ये या PC साठी योग्य OS पहा.' 'सलाह page पर इस PC के लिए सही OS देखें।') 'advisor' 'hw' }
    elseif ($info.OSBuild -lt 22000) { add 'Warning' 'OS' (L 'Windows 10 support has ended (14 Oct 2025)' 'Windows 10 चा support संपला आहे (14 Oct 2025)' 'Windows 10 का support खत्म हो गया है (14 Oct 2025)') (L 'Only PCs enrolled in ESU get updates. See the advice page.' 'फक्त ESU मध्ये enroll केलेल्या PC ना updates मिळतात. सल्ला page पहा.' 'सिर्फ़ ESU में enroll PC को updates मिलते हैं। सलाह page देखें।') 'advisor' 'hw' }
    if ($pending) { add 'Info' 'OS' (L 'A restart is pending' 'Restart बाकी आहे' 'Restart बाकी है') (L 'Restart the PC to finish the updates.' 'Updates पूर्ण करण्यासाठी PC restart करा.' 'Updates पूरे करने के लिए PC restart करें।') $null 'restart' }
    if ($info.UptimeDays -gt 7) { add 'Info' 'OS' ((L 'The PC has not been restarted for {0} days' 'PC {0} दिवसांपासून restart झालेला नाही' 'PC {0} दिनों से restart नहीं हुआ') -f $info.UptimeDays) (L 'A restart once a week clears memory leaks.' 'आठवड्यातून एकदा restart केल्यास memory leaks साफ होतात.' 'हफ़्ते में एक बार restart करने से memory leaks साफ़ होते हैं।') $null 'restart' }
    $wu = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wu -and $wu.StartType -eq 'Disabled') { add 'Warning' 'OS' (L 'The Windows Update service is off (Disabled)' 'Windows Update service बंद (Disabled) आहे' 'Windows Update service बंद (Disabled) है') (L 'No security updates arrive.' 'Security updates मिळत नाहीत.' 'Security updates नहीं मिलते।') 'wureset' }

    # --- score
    $score = 100 - (($f | Measure-Object Points -Sum).Sum)
    $score = [math]::Max(5, $score)
    # the best score software alone can reach (hardware / OS-support problems stay)
    $reach = [math]::Max(5, 100 - (($f | Where-Object { $_.Kind -eq 'hw' } | Measure-Object Points -Sum).Sum))
    if ($f.Count -eq 0) { add 'OK' 'All' (L 'No major problems found' 'कोणतीही मोठी समस्या सापडली नाही' 'कोई बड़ी समस्या नहीं मिली') (L 'The PC is in good shape.' 'PC चांगल्या स्थितीत आहे.' 'PC अच्छी हालत में है।') $null }

    Set-PDProgress -1
    Write-PDLog ("Scan finished - {0} findings, score {1}/100 ({2:N0} sec)" -f $f.Count, $score, ((Get-Date) - $t0).TotalSeconds) 'OK'
    $sevOrder = @{ Critical = 0; Warning = 1; Info = 2; OK = 3 }
    [pscustomobject]@{
        Time = Get-Date; Score = $score; Reachable = $reach; Info = $info; Load = $load; Events = $events
        Startup = $startup; Apps = $apps; AppAdvice = $appAdvice; Bloat = $bloat
        Drivers = $drivers; DriverAge = $drvAge; WUDrivers = $wuDrivers; Security = $sec; ImageHealth = $image; Sfc = $sfc
        TempBytes = $tempBytes; Junk = $junkCats; Registry = $regIssues; WindowsOldBytes = $winOld; PowerPlan = $power; PendingReboot = $pending
        Findings = @($f | Sort-Object { $sevOrder[$_.Severity] })
    }
}

Export-ModuleMember -Function *
