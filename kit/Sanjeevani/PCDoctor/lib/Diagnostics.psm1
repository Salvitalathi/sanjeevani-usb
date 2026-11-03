# Sanjeevani PC Doctor - read-only diagnostics. Nothing in this file changes the PC.
Set-StrictMode -Off

function Get-PDSystemInfo {
    Write-PDLog 'System माहिती गोळा करत आहे...' 'STEP'
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
    Write-PDLog 'CPU / RAM / Disk वापर मोजत आहे...' 'STEP'
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
    Write-PDLog "मागील $Days दिवसांचे error logs तपासत आहे..." 'STEP'
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

function Get-PDDriverProblems {
    @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 } |
        ForEach-Object { [pscustomobject]@{ Name = $(if ($_.Name) { $_.Name } else { $_.DeviceID }); Code = $_.ConfigManagerErrorCode } })
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
    Write-PDLog 'Windows image (component store) तपासत आहे...' 'STEP'
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
    Write-PDLog 'System files तपासत आहे (sfc /verifyonly) - 10 ते 20 मिनिटे लागू शकतात...' 'STEP'
    $start = Get-Date
    $null = Invoke-PDProcess -FilePath "$env:WINDIR\System32\sfc.exe" -Arguments '/verifyonly' -Unicode -ProgressLabel 'System files तपासणी'
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
    } catch { Write-PDLog ('CBS.log वाचता आला नाही: ' + $_.Exception.Message) 'WARN' }
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
    Set-PDProgress 5 'System माहिती'
    $info = Get-PDSystemInfo
    Set-PDProgress 20 'Startup programs'
    $startup = @(Get-PDStartupItems)
    Set-PDProgress 30 'Installed apps'
    $apps = @(Get-PDInstalledApps)
    Set-PDProgress 40 'वेग मोजणी'
    $load = Get-PDLoadSnapshot
    Set-PDProgress 55 'Error logs'
    $events = Get-PDEventSummary
    Set-PDProgress 65 'Drivers / Security'
    $drivers = @(Get-PDDriverProblems)
    $sec = Get-PDSecurityStatus
    $pending = Test-PDPendingReboot
    Set-PDProgress 72 'Temp files'
    $tempBytes = Get-PDTempSize
    $winOld = Get-PDFolderSize "$env:SystemDrive\Windows.old"
    $power = Get-PDActivePowerPlan
    Set-PDProgress 80 'Windows image'
    $image = Get-PDImageHealth
    $sfc = $null
    if ($Deep) { $sfc = Test-PDSystemFiles }
    Set-PDProgress 95 'विश्लेषण'

    $bloat = @()
    if ($DataDir -and (Test-Path (Join-Path $DataDir 'bloat.json'))) {
        $bl = Get-Content (Join-Path $DataDir 'bloat.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $installedAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        foreach ($b in $bl.packages) { foreach ($n in $installedAppx) { if ($n -like $b.name) { $bloat += [pscustomobject]@{ Name = $n; Label = $b.label; Default = [bool]$b.default } } } }
    }
    $appAdvice = @()
    if ($DataDir) { $appAdvice = @(Get-PDAppAdvice -Apps $apps -Info $info -DataDir $DataDir) }

    $f = New-Object System.Collections.ArrayList
    function add($sev, $cat, $title, $detail, $fix) {
        [void]$f.Add([pscustomobject]@{ Severity = $sev; Category = $cat; Title = $title; Detail = $detail; FixId = $fix })
    }

    # --- storage
    if ($info.SysFreeGB -lt 10 -or $info.SysFreePct -lt 10) {
        add 'Critical' 'Storage' "$($info.SystemDrive) drive जवळजवळ भरला आहे" ("फक्त {0} GB ({1}%) जागा शिल्लक. यामुळे PC खूप slow होतो आणि updates fail होतात." -f $info.SysFreeGB, $info.SysFreePct) 'storage'
    } elseif ($info.SysFreePct -lt 20) {
        add 'Warning' 'Storage' "$($info.SystemDrive) drive वर जागा कमी आहे" ("{0} GB ({1}%) शिल्लक. किमान 20% जागा मोकळी ठेवा." -f $info.SysFreeGB, $info.SysFreePct) 'storage'
    }
    if ($tempBytes -gt 1GB) { add 'Info' 'Storage' 'Temporary files खूप जमा झाल्या आहेत' ("{0} जागा मोकळी करता येईल." -f (Format-PDSize $tempBytes)) 'cleanup' }
    if ($winOld -gt 1GB) { add 'Info' 'Storage' 'जुन्या Windows (Windows.old) च्या files आहेत' ("{0} जागा मोकळी करता येईल (पुन्हा जुन्या Windows वर जाता येणार नाही)." -f (Format-PDSize $winOld)) 'cleanup' }

    # --- disks
    foreach ($d in $info.Disks) {
        if ($d.Health -ne 'Healthy') {
            add 'Critical' 'Hardware' "Disk धोक्यात: $($d.Model)" "Disk health: $($d.Health). लगेच data backup घ्या आणि disk बदलण्याचा विचार करा." 'backup'
        }
        if ($d.TempC -and $d.TempC -ge 55) { add 'Warning' 'Hardware' "Disk गरम आहे ($($d.TempC)°C): $($d.Model)" 'Cooling / fan / हवा खेळती आहे का ते तपासा.' $null }
        if ($d.WearPct -and $d.WearPct -ge 80) { add 'Warning' 'Hardware' "SSD झिजली आहे ($($d.WearPct)% wear)" 'Backup ठेवा आणि लवकरच SSD बदलण्याची तयारी करा.' 'backup' }
    }
    $sysDisk = @($info.Disks | Where-Object { $_.IsSystem })[0]
    if ($sysDisk -and $sysDisk.MediaType -eq 'HDD') {
        add 'Warning' 'Speed' 'Windows जुन्या Hard Disk (HDD) वर आहे' 'PC slow असण्याचे हे सर्वात मोठे कारण आहे. SSD लावल्यास PC 3 ते 5 पट वेगाने चालेल (सल्ला tab पहा).' 'advisor'
    }

    # --- memory / load
    if ($info.RAMGB -lt 3.5) { add 'Critical' 'Speed' "RAM फक्त $($info.RAMGB) GB आहे" 'Windows 10/11 साठी किमान 8 GB RAM योग्य. RAM वाढवा किंवा हलकी OS वापरा (सल्ला tab).' 'advisor' }
    elseif ($info.RAMGB -lt 7) { add 'Warning' 'Speed' "RAM $($info.RAMGB) GB आहे" 'आजच्या browsers/apps साठी 8 GB चांगली. Free slot असल्यास RAM वाढवा.' 'advisor' }
    if ($load.RAMPct -ge 85) { add 'Warning' 'Speed' "RAM $($load.RAMPct)% वापरली जात आहे" ("सर्वात जास्त RAM वापरणारे: " + (($load.TopRAM | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.RAMMB) MB)" }) -join ', ')) 'startup' }
    if ($load.CPUPct -ge 60) { add 'Warning' 'Speed' "CPU सतत $($load.CPUPct)% busy आहे" ("सर्वात जास्त CPU: " + (($load.TopCPU | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.CPU)%)" }) -join ', ')) $null }
    if ($load.DiskPct -ge 80) { add 'Warning' 'Speed' "Disk $($load.DiskPct)% busy आहे" 'HDD असल्यास हे slowness चे मुख्य कारण. Startup programs कमी करा / SSD लावा.' 'startup' }

    $enabledStartup = @($startup | Where-Object { $_.Enabled }).Count
    if ($enabledStartup -gt 6) { add 'Warning' 'Speed' "$enabledStartup programs Windows सोबत सुरू होतात" 'अनावश्यक startup programs बंद केल्यास PC लवकर सुरू होईल आणि RAM वाचेल.' 'startup' }
    if ($power.Guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') { add 'Info' 'Speed' 'Power plan "Power saver" वर आहे' 'यामुळे CPU मुद्दाम हळू चालतो.' 'power' }
    if ((Test-PDVisualEffectsDefault) -and ($info.RAMGB -le 4 -or -not $info.HasDedicatedGPU)) { add 'Info' 'Speed' 'Animations / transparency effects चालू आहेत' 'हलक्या PC वर हे बंद केल्याने windows लवकर उघडतात.' 'visual' }
    if ($bloat.Count -gt 0) { add 'Info' 'Speed' "$($bloat.Count) अनावश्यक pre-installed apps आहेत" (($bloat | Select-Object -First 5 | ForEach-Object { $_.Label }) -join ', ') 'debloat' }
    $pup = @($appAdvice | Where-Object { $_.Kind -eq 'pup' })
    if ($pup.Count -gt 0) { add 'Warning' 'Software' "$($pup.Count) नको असलेले / धोकादायक programs सापडले" (($pup | ForEach-Object { $_.App }) -join ', ') 'advisor' }

    # --- system health
    switch ($image) {
        'Repairable'    { add 'Critical' 'Repair' 'Windows system image खराब आहे (दुरुस्त होऊ शकतो)' 'DISM + SFC repair चालवा.' 'repair-os' }
        'NonRepairable' { add 'Critical' 'Repair' 'Windows system image दुरुस्त होण्यापलीकडे खराब आहे' 'Windows 11 ISO वापरून "Repair install" करा (data राहतो) किंवा fresh install.' 'repair-os' }
    }
    if ($sfc -and ($sfc.Corrupt + $sfc.Unrepaired) -gt 0) { add 'Critical' 'Repair' 'खराब (corrupt) system files सापडल्या' ("{0} files. Repair tab मधून दुरुस्त करा." -f ($sfc.Corrupt + $sfc.Unrepaired)) 'repair-os' }
    if ($events.DiskErrors -gt 0) { add 'Critical' 'Hardware' "Windows disk वर errors: मागील $($events.Days) दिवसांत $($events.DiskErrors) वेळा" 'Disk check (chkdsk) चालवा, Toolbox मधील CrystalDiskInfo ने health पहा, आणि आधी backup घ्या.' 'chkdsk' }
    if ($events.OtherDiskErrors -gt 0) { add 'Info' 'Hardware' "दुसऱ्या disk / pendrive वर errors: $($events.OtherDiskErrors) वेळा" 'USB pendrive / card reader / external disk चे errors. "Safely remove" न करता काढल्यास असे येतात. Windows disk ला धोका नाही.' $null }
    if ($events.BlueScreens -gt 0) { add 'Warning' 'Stability' "Blue screen crash: $($events.BlueScreens) वेळा" 'Toolbox मधील BlueScreenView / WhoCrashed ने कारण (driver) शोधा. RAM test (MemTest86) चालवा.' 'bsod' }
    if ($events.UnexpectedShutdown -gt 2) { add 'Warning' 'Stability' "अचानक बंद पडणे: $($events.UnexpectedShutdown) वेळा" 'Power supply / battery / overheating तपासा.' $null }
    if ($events.HardwareErrors -gt 0) { add 'Warning' 'Hardware' "Hardware (WHEA) errors: $($events.HardwareErrors)" 'CPU/RAM/PCIe hardware त्रास. Stress test आणि RAM test चालवा.' $null }
    if ($drivers.Count -gt 0) { add 'Warning' 'Drivers' "$($drivers.Count) devices चे drivers नीट नाहीत" (($drivers | Select-Object -First 4 | ForEach-Object { $_.Name }) -join ', ') 'drivers' }

    # --- security
    $avs = @($sec.AntivirusProducts | Where-Object { $_ -notmatch 'Windows Defender|Microsoft Defender' })
    if ($avs.Count -gt 1) { add 'Warning' 'Security' 'एकापेक्षा जास्त antivirus install आहेत' (($avs -join ', ') + ' - दोन antivirus एकमेकांशी भांडतात आणि PC slow करतात. एकच ठेवा.') 'advisor' }
    if ($avs.Count -eq 0 -and $sec.DefenderRealtime -eq $false) { add 'Critical' 'Security' 'Antivirus protection बंद आहे' 'Microsoft Defender real-time protection चालू करा.' 'defender' }
    if ($sec.SignatureAgeDays -gt 7 -and $avs.Count -eq 0) { add 'Warning' 'Security' "Defender definitions $($sec.SignatureAgeDays) दिवस जुने आहेत" 'Update करा.' 'defender' }

    # --- OS lifecycle
    if ($info.OSBuild -lt 10240) { add 'Critical' 'OS' "$($info.OSCaption) ला आता security updates मिळत नाहीत" 'सल्ला tab मध्ये या PC साठी योग्य OS पहा.' 'advisor' }
    elseif ($info.OSBuild -lt 22000) { add 'Warning' 'OS' 'Windows 10 चा support संपला आहे (14 Oct 2025)' 'फक्त ESU मध्ये enroll केलेल्या PC ना updates मिळतात. सल्ला tab पहा.' 'advisor' }
    if ($pending) { add 'Info' 'OS' 'Restart बाकी आहे' 'Updates पूर्ण करण्यासाठी PC restart करा.' $null }
    if ($info.UptimeDays -gt 7) { add 'Info' 'OS' "PC $($info.UptimeDays) दिवसांपासून restart झालेला नाही" 'आठवड्यातून एकदा restart केल्यास memory leaks साफ होतात.' $null }
    $wu = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wu -and $wu.StartType -eq 'Disabled') { add 'Warning' 'OS' 'Windows Update service बंद (Disabled) आहे' 'Security updates मिळत नाहीत.' 'wureset' }

    # --- score
    $score = 100
    foreach ($x in $f) { switch ($x.Severity) { 'Critical' { $score -= 15 } 'Warning' { $score -= 6 } 'Info' { $score -= 2 } } }
    $score = [math]::Max(5, $score)
    if ($f.Count -eq 0) { add 'OK' 'All' 'कोणतीही मोठी समस्या सापडली नाही' 'PC चांगल्या स्थितीत आहे.' $null }

    Set-PDProgress -1
    Write-PDLog ("Scan पूर्ण - {0} findings, score {1}/100 ({2:N0} sec)" -f $f.Count, $score, ((Get-Date) - $t0).TotalSeconds) 'OK'
    $sevOrder = @{ Critical = 0; Warning = 1; Info = 2; OK = 3 }
    [pscustomobject]@{
        Time = Get-Date; Score = $score; Info = $info; Load = $load; Events = $events
        Startup = $startup; Apps = $apps; AppAdvice = $appAdvice; Bloat = $bloat
        Drivers = $drivers; Security = $sec; ImageHealth = $image; Sfc = $sfc
        TempBytes = $tempBytes; WindowsOldBytes = $winOld; PowerPlan = $power; PendingReboot = $pending
        Findings = @($f | Sort-Object { $sevOrder[$_.Severity] })
    }
}

Export-ModuleMember -Function *
