# Sanjeevani PC Doctor - "Tools मार्गदर्शक": finds the USB tools, prepares their settings for this PC
# and runs automatic checks whose results are explained in Marathi and English.
# Every check is read-only except the stress test (which only loads the CPU) - nothing is changed on the PC.
Set-StrictMode -Off

# ------------------------------------------------------------------ result object
function New-TGResult {
    param([string]$Status = 'info', [string]$HeadMr, [string]$HeadEn)
    [pscustomobject]@{ Status = $Status; HeadMr = $HeadMr; HeadEn = $HeadEn
        LinesMr = (New-Object System.Collections.ArrayList); LinesEn = (New-Object System.Collections.ArrayList); File = $null }
}
function Add-TGLine($R, [string]$Mr, [string]$En) { [void]$R.LinesMr.Add($Mr); [void]$R.LinesEn.Add($(if ($En) { $En } else { $Mr })) }
function Set-TGWorse($R, [string]$Status) {
    $rank = @{ info = 0; ok = 1; warn = 2; bad = 3 }
    if ($rank[$Status] -gt $rank[$R.Status]) { $R.Status = $Status }
}
function Test-TGCancel { return [bool]($global:PDState -and $global:PDState.Cancel) }

# ------------------------------------------------------------------ catalog / tool lookup
function Get-TGCatalog([string]$UsbRoot) {
    $cat = $null; $inst = @{}
    $cf = Join-Path $UsbRoot 'Sanjeevani\tools.json'
    if (Test-Path -LiteralPath $cf) { $cat = Get-Content -LiteralPath $cf -Raw -Encoding UTF8 | ConvertFrom-Json }
    $if = Join-Path $UsbRoot 'Sanjeevani\installed.json'
    if (Test-Path -LiteralPath $if) { try { (Get-Content -LiteralPath $if -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $inst[$_.Name] = $_.Value } } catch { } }
    [pscustomobject]@{ Catalog = $cat; Installed = $inst }
}

function Get-TGGuide([string]$DataDir) {
    return (Get-Content -LiteralPath (Join-Path $DataDir 'toolguide.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# Full path of a tool's program (or installer) on the USB, or $null.
function Find-TGTool {
    param([Parameter(Mandatory)][string]$UsbRoot, [Parameter(Mandatory)][string]$Id, $Info)
    if (-not $Info) { $Info = Get-TGCatalog $UsbRoot }
    $i = $Info.Installed[$Id]
    if ($i -and $i.path) {
        $p = Join-Path $UsbRoot $i.path
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    if (-not $Info.Catalog) { return $null }
    $e = @($Info.Catalog.tools) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $e) { return $null }
    if ($e.exe) {
        $dirs = @((Join-Path $UsbRoot "Tools\$($e.category)"), (Join-Path $UsbRoot 'Tools')) | Where-Object { Test-Path -LiteralPath $_ }
        foreach ($d in $dirs) {
            $hit = Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $e.exe -and $_.FullName -notmatch '\\(drivers|indexes|update|SDIO_Update)\\' } |
                Sort-Object { $_.FullName.Length } | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    if ($e.installer -and $e.fileMatch) {
        $hit = Get-ChildItem -LiteralPath (Join-Path $UsbRoot 'Installers') -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $e.fileMatch } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# ------------------------------------------------------------------ settings prepared for this PC ("auto set")
function Set-TGIniValue([string]$File, [string]$Section, [hashtable]$Values) {
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $File) { foreach ($l in (Get-Content -LiteralPath $File -ErrorAction SilentlyContinue)) { [void]$lines.Add($l) } }
    $start = -1
    for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k].Trim() -ieq "[$Section]") { $start = $k; break } }
    if ($start -lt 0) { [void]$lines.Add("[$Section]"); $start = $lines.Count - 1 }
    foreach ($key in $Values.Keys) {
        $end = $lines.Count
        for ($k = $start + 1; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '^\s*\[') { $end = $k; break } }
        $found = $false
        for ($k = $start + 1; $k -lt $end; $k++) {
            if ($lines[$k] -match ('^\s*' + [regex]::Escape($key) + '\s*=')) { $lines[$k] = "$key=$($Values[$key])"; $found = $true; break }
        }
        if (-not $found) { $lines.Insert($end, "$key=$($Values[$key])") }
    }
    Set-Content -LiteralPath $File -Value $lines -Encoding ASCII
}

# Writes the settings a tool needs to open straight into the useful view with no first-run questions.
function Initialize-TGToolConfig([string]$Id, [string]$Exe) {
    if (-not $Exe) { return }
    $dir = Split-Path $Exe
    try {
        switch ($Id) {
            'hwinfo' {
                # straight into the Sensors window, no welcome screen, no update check
                Set-TGIniValue (Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($Exe) + '.INI')) 'Settings' @{ SensorsOnly = 1; ShowWelcomeAndProgress = 0; AutoUpdate = 0 }
            }
            'prime95' {
                # stress testing only - no GIMPS account question
                $p = Join-Path $dir 'prime.txt'
                $t = if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw } else { '' }
                if ($t -notmatch '(?m)^StressTester=') { $t = "StressTester=1`r`nUsePrimenet=0`r`n" + $t }
                Set-Content -LiteralPath $p -Value $t.TrimEnd() -Encoding ASCII
            }
            'bluescreenview' { Set-Content -LiteralPath (Join-Path $dir 'BlueScreenView.cfg') -Value "[General]`r`nAddExportHeaderLine=1" -Encoding ASCII }
        }
    } catch { Write-PDLog "settings for $Id could not be written: $($_.Exception.Message)" 'WARN' }
}

function Invoke-TGProcess([string]$Exe, [string[]]$Arguments, [int]$TimeoutSec = 300, [switch]$Hidden) {
    $sp = @{ FilePath = $Exe; WorkingDirectory = (Split-Path $Exe); PassThru = $true }
    if ($Arguments) { $sp.ArgumentList = $Arguments }
    if ($Hidden) { $sp.WindowStyle = 'Hidden' }
    $p = Start-Process @sp
    $t0 = Get-Date
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 500
        if ((Test-TGCancel) -or ((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) { try { $p.Kill() } catch { }; return $null }
    }
    return $p.ExitCode
}

function Get-TGThermalC {
    # ACPI thermal zone (many laptops); $null when the PC does not report it
    try {
        $z = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
        $v = $z | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) } | Where-Object { $_ -gt 0 -and $_ -lt 130 }
        if ($v) { return ($v | Measure-Object -Maximum).Maximum }
    } catch { }
    return $null
}

# ------------------------------------------------------------------ auto checks
function Invoke-TGDiskHealth([string]$UsbRoot, $P) {
    $r = New-TGResult 'ok' 'Disk ची तब्येत' 'Disk health'
    $cdiDone = $false
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'crystaldiskinfo'
    if ($exe) {
        $txt = Join-Path (Split-Path $exe) 'DiskInfo.txt'
        Remove-Item -LiteralPath $txt -ErrorAction SilentlyContinue
        Set-PDProgress -1 'CrystalDiskInfo'
        [void](Invoke-TGProcess $exe @('/CopyExit') 180 -Hidden)
        if (Test-Path -LiteralPath $txt) {
            $disks = ConvertFrom-TGDiskInfo (Get-Content -LiteralPath $txt -Raw)
            foreach ($d in $disks) {
                $cdiDone = $true
                $tmp = if ($d.TempC) { " · $($d.TempC)°C" } else { '' }
                $pct = if ($d.Percent) { " ($($d.Percent)%)" } else { '' }
                switch -Regex ($d.Health) {
                    '^Good' { Add-TGLine $r "✔ $($d.Model): ठीक$pct$tmp" "✔ $($d.Model): Good$pct$tmp" }
                    '^Caution' { Set-TGWorse $r 'warn'; Add-TGLine $r "⚠ $($d.Model): Caution$pct$tmp - disk खराब होऊ लागली. महत्त्वाचा data लगेच copy करा आणि disk बदलायची तयारी करा." "⚠ $($d.Model): Caution$pct$tmp - the disk is starting to fail. Copy important data now and plan a replacement." }
                    '^Bad' { Set-TGWorse $r 'bad'; Add-TGLine $r "✖ $($d.Model): Bad$tmp - disk खराब. आत्ताच data copy करा, disk बदला." "✖ $($d.Model): Bad$tmp - the disk is failing. Copy the data now and replace the disk." }
                    default { Add-TGLine $r "• $($d.Model): $($d.Health)$tmp" }
                }
                if ($d.TempC -ge 55) { Set-TGWorse $r 'warn'; Add-TGLine $r "   तापमान जास्त ($($d.TempC)°C) - हवा खेळती ठेवा / laptop खाली कठीण पृष्ठभाग." "   Temperature is high ($($d.TempC)°C) - improve airflow / keep the laptop on a hard surface." }
            }
        }
    }
    if (-not $cdiDone) {
        # Windows' own view (works without CrystalDiskInfo)
        foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)) {
            $rc = $null; try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            $name = "$($d.FriendlyName) ($($d.MediaType), $([math]::Round($d.Size / 1GB)) GB)"
            $extra = @()
            if ($rc -and $rc.Temperature) { $extra += "$($rc.Temperature)°C" }
            if ($rc -and $null -ne $rc.Wear -and $rc.Wear -gt 0) { $extra += "wear $($rc.Wear)%" }
            $ex = if ($extra) { ' · ' + ($extra -join ' · ') } else { '' }
            if ($d.HealthStatus -eq 'Unhealthy') { Set-TGWorse $r 'bad'; Add-TGLine $r "✖ $name : खराब$ex - आत्ताच data copy करा." "✖ $name : Unhealthy$ex - copy the data now." }
            elseif ($d.HealthStatus -eq 'Warning' -or ($rc -and $rc.ReadErrorsUncorrected -gt 0) -or ($rc -and $rc.Wear -ge 80)) { Set-TGWorse $r 'warn'; Add-TGLine $r "⚠ $name : लक्ष द्या$ex - data चा backup घ्या." "⚠ $name : Warning$ex - back up the data." }
            else { Add-TGLine $r "✔ $name : ठीक$ex" "✔ $name : Healthy$ex" }
        }
        if (-not $r.LinesMr.Count) { $r.Status = 'info'; Add-TGLine $r 'Disk माहिती मिळाली नाही.' 'No disk information was available.' }
        else { Add-TGLine $r '(Windows ची माहिती. जास्त अचूक तपासणीसाठी CrystalDiskInfo pendrive वर ठेवा.)' '(From Windows. Keep CrystalDiskInfo on the USB for a more precise check.)' }
    }
    $r.HeadMr = switch ($r.Status) { 'bad' { 'Disk खराब आहे - data लगेच वाचवा' } 'warn' { 'Disk वर लक्ष द्या' } default { 'सगळे disks ठीक आहेत' } }
    $r.HeadEn = switch ($r.Status) { 'bad' { 'A disk is failing - save the data now' } 'warn' { 'A disk needs attention' } default { 'All disks are healthy' } }
    return $r
}

# CrystalDiskInfo's DiskInfo.txt: one block per disk with "Model :", "Health Status :", "Temperature :"
function ConvertFrom-TGDiskInfo([string]$Text) {
    $out = @()
    $ms = [regex]::Matches($Text, '(?m)^\s*Model\s*:\s*(.+?)\s*$')
    for ($k = 0; $k -lt $ms.Count; $k++) {
        $from = $ms[$k].Index; $to = if ($k + 1 -lt $ms.Count) { $ms[$k + 1].Index } else { $Text.Length }
        $chunk = $Text.Substring($from, $to - $from)
        $h = [regex]::Match($chunk, '(?m)^\s*Health Status\s*:\s*(\w+)(?:\s*\((\d+)\s*%\))?')
        $t = [regex]::Match($chunk, '(?m)^\s*Temperature\s*:\s*(\d+)\s*C')
        $out += [pscustomobject]@{
            Model = $ms[$k].Groups[1].Value; Health = $(if ($h.Success) { $h.Groups[1].Value } else { 'Unknown' })
            Percent = $(if ($h.Success -and $h.Groups[2].Success) { [int]$h.Groups[2].Value } else { $null })
            TempC = $(if ($t.Success) { [int]$t.Groups[1].Value } else { $null })
        }
    }
    return $out
}

function Invoke-TGBattery([string]$UsbRoot, $P) {
    $r = New-TGResult 'info' 'Battery' 'Battery'
    $xmlFile = Join-Path $env:TEMP 'sjv-battery.xml'
    Remove-Item -LiteralPath $xmlFile -ErrorAction SilentlyContinue
    & powercfg.exe /batteryreport /xml /output $xmlFile 2>$null | Out-Null
    $bats = @()
    if (Test-Path -LiteralPath $xmlFile) { try { [xml]$x = Get-Content -LiteralPath $xmlFile -Raw; $bats = @($x.BatteryReport.Batteries.Battery | Where-Object { $_ }) } catch { } }
    if (-not $bats.Count) {
        $r.HeadMr = 'Battery सापडली नाही'; $r.HeadEn = 'No battery found'
        Add-TGLine $r 'हा desktop PC आहे किंवा battery लावलेली / ओळखलेली नाही.' 'This is a desktop PC, or the battery is not fitted / not detected.'
        return $r
    }
    $worst = 0
    foreach ($b in $bats) {
        $design = [double]$b.DesignCapacity; $full = [double]$b.FullChargeCapacity
        if ($design -le 0) { continue }
        $wear = [math]::Max(0, [math]::Round(100 * (1 - $full / $design)))
        $worst = [math]::Max($worst, $wear)
        $cyc = if ($b.CycleCount) { " · $($b.CycleCount) cycles" } else { '' }
        Add-TGLine $r ("{0}: मूळ क्षमता {1:N0} mWh, आता {2:N0} mWh → झीज {3}%{4}" -f $b.Id, $design, $full, $wear, $cyc) ("{0}: design {1:N0} mWh, now {2:N0} mWh → wear {3}%{4}" -f $b.Id, $design, $full, $wear, $cyc)
    }
    if ($worst -ge 40) { $r.Status = 'bad'; $r.HeadMr = "Battery बदलण्याची वेळ (झीज $worst%)"; $r.HeadEn = "Time to replace the battery ($worst% wear)"
        Add-TGLine $r 'Battery मूळ क्षमतेच्या 60% पेक्षा कमी charge धरते. नवीन original battery लावा.' 'It holds less than 60% of its original charge. Fit a new original battery.' }
    elseif ($worst -ge 20) { $r.Status = 'warn'; $r.HeadMr = "Battery थोडी झिजली (झीज $worst%)"; $r.HeadEn = "Battery somewhat worn ($worst% wear)"
        Add-TGLine $r 'चालेल, पण backup कमी मिळेल. 100% वर सतत charger लावून ठेवणे टाळा.' 'Usable, with shorter backup. Avoid keeping it on the charger at 100% all the time.' }
    else { $r.Status = 'ok'; $r.HeadMr = "Battery चांगली (झीज $worst%)"; $r.HeadEn = "Battery is good ($worst% wear)" }
    return $r
}

function Get-TGRamType([int]$t) {
    switch ($t) { 20 { 'DDR' } 21 { 'DDR2' } 24 { 'DDR3' } 26 { 'DDR4' } 27 { 'LPDDR' } 28 { 'LPDDR2' } 29 { 'LPDDR3' } 30 { 'LPDDR4' } 34 { 'DDR5' } 35 { 'LPDDR5' } default { '' } }
}

function Invoke-TGSystemSummary([string]$UsbRoot, $P) {
    $r = New-TGResult 'ok' 'या PC ची माहिती आणि upgrade सल्ला' 'PC details and upgrade advice'
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $slots = (@(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue) | Measure-Object MemoryDevices -Sum).Sum
    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual' })
    $ramGB = [math]::Round(($cs.TotalPhysicalMemory) / 1GB)
    Add-TGLine $r "PC: $($cs.Manufacturer) $($cs.Model)" ''
    Add-TGLine $r "CPU: $($cpu.Name.Trim()) · $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads" ''
    $type = ($mods | ForEach-Object { Get-TGRamType ([int]$_.SMBIOSMemoryType) } | Where-Object { $_ } | Select-Object -First 1)
    $speed = ($mods | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Measure-Object -Maximum).Maximum
    $modTxt = ($mods | ForEach-Object { "$([math]::Round($_.Capacity / 1GB)) GB" }) -join ' + '
    Add-TGLine $r ("RAM: {0} GB {1} {2} MHz ({3}) · slots: {4}" -f $ramGB, $type, $speed, $modTxt, $(if ($slots) { $slots } else { '?' })) ''
    foreach ($g in $gpu) { Add-TGLine $r "Graphics: $($g.Name)" '' }
    Add-TGLine $r "Windows: $($os.Caption) ($($os.Version))" ''
    # system disk type
    $sysType = $null
    try {
        $dn = (Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction Stop).DiskNumber
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$dn } | Select-Object -First 1
        if ($pd) { $sysType = [string]$pd.MediaType; Add-TGLine $r "Windows disk: $($pd.FriendlyName) ($sysType, $([math]::Round($pd.Size / 1GB)) GB, $($pd.BusType))" '' }
    } catch { }
    # advice
    if ($ramGB -lt 4) { Set-TGWorse $r 'bad'; Add-TGLine $r '✖ RAM 4 GB पेक्षा कमी - Windows 10/11 खूप हळू चालेल. किमान 8 GB करा.' '✖ Less than 4 GB RAM - Windows 10/11 will be very slow. Upgrade to at least 8 GB.' }
    elseif ($ramGB -lt 8) { Set-TGWorse $r 'warn'; Add-TGLine $r '⚠ RAM 8 GB पेक्षा कमी - browser + office एकत्र हळू. 8 GB केल्यास फरक जाणवेल.' '⚠ Less than 8 GB RAM - browser + office together are slow. 8 GB makes a clear difference.' }
    if ($mods.Count -eq 1 -and $slots -gt 1) {
        Set-TGWorse $r 'warn'
        Add-TGLine $r ("⚠ एकच RAM stick (single channel). मोकळ्या slot मध्ये तशीच {0} {1} MHz RAM लावल्यास dual channel होऊन वेग वाढतो." -f $type, $speed) ("⚠ Only one RAM stick (single channel). Adding a matching {0} {1} MHz stick in the free slot enables dual channel and speeds it up." -f $type, $speed)
    }
    if ($sysType -eq 'HDD') { Set-TGWorse $r 'warn'; Add-TGLine $r '⚠ Windows hard disk (HDD) वर आहे. SSD लावल्यास PC 3-5 पट लवकर सुरू होतो - सगळ्यात मोठा फायदा.' '⚠ Windows runs from a hard disk (HDD). An SSD makes it start 3-5 times faster - the biggest single upgrade.' }
    if ($r.Status -eq 'ok') { Add-TGLine $r '✔ RAM आणि disk या कामांसाठी पुरेसे आहेत.' '✔ RAM and disk are adequate.' }
    # full CPU-Z report
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'cpuz'
    if ($exe -and $P.ReportDir) {
        $base = Join-Path $P.ReportDir ("cpuz-{0:yyyyMMdd-HHmm}" -f (Get-Date))
        Set-PDProgress -1 'CPU-Z report'
        [void](Invoke-TGProcess $exe @("-txt=$base") 120 -Hidden)
        if (Test-Path -LiteralPath "$base.txt") { $r.File = "$base.txt"; Add-TGLine $r 'CPU-Z चा पूर्ण report Reports folder मध्ये save केला.' 'The full CPU-Z report was saved in the Reports folder.' }
    }
    return $r
}

function Invoke-TGTemps([string]$UsbRoot, $P) {
    $r = New-TGResult 'info' 'तापमान' 'Temperatures'
    $c = Get-TGThermalC
    if ($null -ne $c) {
        Add-TGLine $r "Windows नुसार सध्याचे तापमान: $c°C" "Current temperature reported by Windows: $c°C"
        if ($c -ge 90) { Set-TGWorse $r 'bad'; Add-TGLine $r '✖ खूप गरम. Fan / heatsink ची धूळ साफ करा, thermal paste बदला.' '✖ Very hot. Clean the fan / heatsink and renew the thermal paste.' }
        elseif ($c -ge 80) { Set-TGWorse $r 'warn'; Add-TGLine $r '⚠ गरम. Vents मोकळे आहेत ना ते पाहा.' '⚠ Hot. Check that the vents are not blocked.' }
    }
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'hwinfo'
    if ($exe) {
        Initialize-TGToolConfig 'hwinfo' $exe
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) | Out-Null
        Add-TGLine $r 'HWiNFO चा Sensors window उघडला आहे. त्यात हे पाहा:' 'HWiNFO''s Sensors window is open. Look at:'
    } else {
        Add-TGLine $r 'HWiNFO pendrive वर नाही - Setup चालवून घ्या. तोपर्यंत हे लक्षात ठेवा:' 'HWiNFO is not on the USB - run Setup to get it. Meanwhile:'
    }
    Add-TGLine $r '• "CPU Package" / "CPU (Tctl/Tdie)": 40-75°C ठीक · 80-90°C जास्त · 95°C+ धोका.' '• "CPU Package" / "CPU (Tctl/Tdie)": 40-75°C fine · 80-90°C high · 95°C+ dangerous.'
    Add-TGLine $r '• "Thermal Throttling" = Yes → गरमीमुळे PC हळू होतो; cooling साफ करा.' '• "Thermal Throttling" = Yes → heat is slowing the PC; clean the cooling.'
    Add-TGLine $r '• GPU 85°C पर्यंत, disk 55°C पर्यंत ठीक.' '• GPU up to 85°C and disks up to 55°C are fine.'
    $r.HeadMr = if ($r.Status -eq 'bad') { 'PC खूप गरम होत आहे' } elseif ($r.Status -eq 'warn') { 'PC गरम आहे' } else { 'तापमान तपासणी' }
    $r.HeadEn = if ($r.Status -eq 'bad') { 'The PC is overheating' } elseif ($r.Status -eq 'warn') { 'The PC runs hot' } else { 'Temperature check' }
    return $r
}

# known drivers -> plain advice
$script:TGDriverHints = @(
    @('^nvlddmkm|^nvkflt|^nvhda', 'nVIDIA display driver', 'nVIDIA display driver'),
    @('^atikmdag|^atikmpag|^amdkmdag|^amdkmpfd', 'AMD display driver', 'AMD display driver'),
    @('^igdkmd|^igdkmdn|^igfx', 'Intel display driver', 'Intel display driver'),
    @('^rt640x64|^rt68|^rtwlan|^rtwlane|^rtl8', 'Realtek LAN / WiFi driver', 'Realtek LAN / WiFi driver'),
    @('^netwtw|^netwlv|^netwsw|^netw', 'Intel WiFi driver', 'Intel WiFi driver'),
    @('^athw|^athr|^qcamain', 'Qualcomm Atheros WiFi driver', 'Qualcomm Atheros WiFi driver'),
    @('^bcmwl', 'Broadcom WiFi driver', 'Broadcom WiFi driver'),
    @('^iaStor|^iaStorA|^iaStorAC|^RstMwService', 'Intel storage (RST) driver', 'Intel storage (RST) driver'),
    @('^(ntoskrnl|ntkrnlmp|hal)\.', 'Windows kernel - हे स्वतः कारण नसते; बहुतेक RAM / disk / इतर driver', 'Windows kernel - rarely the cause itself; usually RAM / disk / another driver')
)
function Get-TGDriverHint([string]$Driver, [string]$Lang) {
    foreach ($h in $script:TGDriverHints) { if ($Driver -match $h[0]) { return $(if ($Lang -eq 'en') { $h[2] } else { $h[1] }) } }
    return $null
}

function Invoke-TGCrashes([string]$UsbRoot, $P) {
    $r = New-TGResult 'ok' 'Blue screen इतिहास' 'Blue-screen history'
    $since = (Get-Date).AddDays(-60)
    $bug = @(); $kp = @()
    try { $bug = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = $since } -ErrorAction Stop | Where-Object { $_.ProviderName -match 'WER-SystemErrorReporting|BugCheck' }) } catch { }
    try { $kp = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction Stop) } catch { }
    $dumpDir = Join-Path $env:SystemRoot 'Minidump'
    $dumps = @(Get-ChildItem -LiteralPath $dumpDir -Filter *.dmp -ErrorAction SilentlyContinue)
    Add-TGLine $r ("मागच्या 60 दिवसांत: {0} blue screen, {1} वेळा अचानक बंद / restart (power cut धरून)." -f $bug.Count, $kp.Count) ("Last 60 days: {0} blue screens, {1} sudden shutdowns / restarts (power cuts included)." -f $bug.Count, $kp.Count)
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'bluescreenview'
    $crashes = @()
    if ($exe -and $dumps.Count) {
        Initialize-TGToolConfig 'bluescreenview' $exe
        $csv = Join-Path $env:TEMP 'sjv-bsod.csv'
        Remove-Item -LiteralPath $csv -ErrorAction SilentlyContinue
        [void](Invoke-TGProcess $exe @('/MiniDumpFolder', "`"$dumpDir`"", '/scomma', "`"$csv`"") 120 -Hidden)
        if (Test-Path -LiteralPath $csv) { $crashes = @(Get-Content -LiteralPath $csv -Raw | ConvertFrom-Csv) }
    }
    if ($crashes.Count) {
        $groups = @($crashes | Where-Object { $_.'Caused By Driver' } | Group-Object 'Caused By Driver' | Sort-Object Count -Descending)
        foreach ($g in ($groups | Select-Object -First 4)) {
            $hintMr = Get-TGDriverHint $g.Name 'mr'; $hintEn = Get-TGDriverHint $g.Name 'en'
            $bc = ($g.Group | ForEach-Object { $_.'Bug Check String' } | Select-Object -Unique) -join ', '
            Add-TGLine $r ("• {0} - {1} वेळा ({2}){3}" -f $g.Name, $g.Count, $bc, $(if ($hintMr) { " → $hintMr" } else { '' })) ("• {0} - {1} times ({2}){3}" -f $g.Name, $g.Count, $bc, $(if ($hintEn) { " → $hintEn" } else { '' }))
        }
        $top = $groups | Select-Object -First 1
        if ($top -and $top.Name -notmatch '^(ntoskrnl|ntkrnlmp|hal)\.' -and $top.Count -ge 2) {
            Set-TGWorse $r 'bad'
            Add-TGLine $r "उपाय: $($top.Name) चा driver कंपनीच्या website वरून नवीन install करा (किंवा PC Doctor → दुरुस्ती → Drivers)." "Fix: install a fresh driver for $($top.Name) from the maker's website (or PC Doctor → Repair → Drivers)."
        } else {
            Set-TGWorse $r 'warn'
            Add-TGLine $r 'वेगवेगळे / Windows चे files दोषी दिसतात - RAM (Windows Memory Diagnostic / MemTest86+) आणि disk (CrystalDiskInfo) तपासा.' 'Different or Windows files are blamed - test the RAM (Windows Memory Diagnostic / MemTest86+) and the disk (CrystalDiskInfo).'
        }
    } elseif ($bug.Count) {
        Set-TGWorse $r 'warn'
        Add-TGLine $r 'Blue screens झाले, पण dump files नाहीत / BlueScreenView नाही. RAM आणि disk तपासा; drivers update करा.' 'Blue screens happened, but there are no dump files / no BlueScreenView. Test RAM and disk; update drivers.'
    }
    if ($kp.Count -ge 3 -and -not $bug.Count) {
        Set-TGWorse $r 'warn'
        Add-TGLine $r 'Blue screen शिवाय वारंवार अचानक बंद = गरम होणे, power supply / charger किंवा battery. HWiNFO ने तापमान पाहा.' 'Repeated sudden shutdowns without a blue screen = overheating, power supply / charger or battery. Check temperatures in HWiNFO.'
    }
    $r.HeadMr = switch ($r.Status) { 'bad' { 'Crash चे कारण सापडले' } 'warn' { 'Crash झाले - पुढील तपासणी करा' } default { 'मागच्या 60 दिवसांत crash नाहीत' } }
    $r.HeadEn = switch ($r.Status) { 'bad' { 'Crash cause found' } 'warn' { 'Crashes happened - more checks needed' } default { 'No crashes in the last 60 days' } }
    return $r
}

function Invoke-TGMsert([string]$UsbRoot, $P) {
    $r = New-TGResult 'info' 'Virus scan' 'Virus scan'
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'msert'
    if (-not $exe) { $r.HeadMr = 'Microsoft Safety Scanner pendrive वर नाही'; $r.HeadEn = 'Microsoft Safety Scanner is not on the USB'; Add-TGLine $r 'Setup चालवून tools update करा, किंवा PC Doctor → दुरुस्ती → "Antivirus चालू करा + quick scan".' 'Run Setup to update the tools, or PC Doctor → Repair → "Turn on antivirus + quick scan".'; return $r }
    $log = Join-Path $env:SystemRoot 'debug\msert.log'
    $before = if (Test-Path -LiteralPath $log) { (Get-Item -LiteralPath $log).Length } else { 0 }
    Write-PDLog 'Microsoft Safety Scanner: quick scan (detection only) - 10-20 मिनिटे' 'STEP'
    Set-PDProgress -1 'virus scan'
    $code = Invoke-TGProcess $exe @('/Q', '/N') 3600
    if ($null -eq $code) { $r.HeadMr = 'Scan थांबवला'; $r.HeadEn = 'Scan stopped'; return $r }
    $txt = ''
    if (Test-Path -LiteralPath $log) {
        $all = [IO.File]::ReadAllBytes($log)
        $enc = if ($all.Length -ge 2 -and $all[0] -eq 0xFF -and $all[1] -eq 0xFE) { [Text.Encoding]::Unicode } else { [Text.Encoding]::Default }
        $txt = $enc.GetString($all)
        if ($before -gt 0 -and $before -lt $all.Length) { $txt = $enc.GetString($all, [int]$before, $all.Length - [int]$before) }
    }
    if ($txt -match 'No infection found') { $r.Status = 'ok'; $r.HeadMr = 'Virus सापडला नाही'; $r.HeadEn = 'No virus found' }
    elseif ($txt -match '(?i)infect|threat|detected') {
        $r.Status = 'bad'; $r.HeadMr = 'Virus / malware सापडला'; $r.HeadEn = 'Virus / malware found'
        foreach ($l in ($txt -split "`r?`n" | Where-Object { $_ -match '(?i)threat|infect|detected' } | Select-Object -First 8)) { Add-TGLine $r ('• ' + $l.Trim()) '' }
        Add-TGLine $r 'काढण्यासाठी: "उघडा" → Full scan → सापडलेले काढू द्या. नंतर Kaspersky Virus Removal Tool ने पुन्हा तपासा.' 'To remove: "Open" → Full scan → let it remove them. Then check again with the Kaspersky Virus Removal Tool.'
    } else { $r.HeadMr = 'Scan पूर्ण'; $r.HeadEn = 'Scan finished'; Add-TGLine $r "Exit code $code. Log: $log" '' }
    return $r
}

function Invoke-TGBigFolders([string]$UsbRoot, $P) {
    $r = New-TGResult 'info' 'C: वरचे सगळ्यात मोठे folders' 'Biggest folders on C:'
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'wiztree'
    if (-not $exe) { $r.HeadMr = 'WizTree pendrive वर नाही'; $r.HeadEn = 'WizTree is not on the USB'; Add-TGLine $r 'PC Doctor → "C: drive जागा" → "C: drive तपासा" वापरा.' 'Use PC Doctor → "C: drive space" → "Check C: drive".'; return $r }
    $csv = Join-Path $env:TEMP 'sjv-wiztree.csv'
    Remove-Item -LiteralPath $csv -ErrorAction SilentlyContinue
    Set-PDProgress -1 'WizTree'
    [void](Invoke-TGProcess $exe @("$($env:SystemDrive)\", "/export=`"$csv`"", '/admin=1', '/exportfolders=1', '/exportfiles=0', '/exportmaxdepth=3') 600 -Hidden)
    if (-not (Test-Path -LiteralPath $csv)) { $r.HeadMr = 'WizTree चा निकाल मिळाला नाही'; $r.HeadEn = 'WizTree gave no result'; return $r }
    $rows = ConvertFrom-TGWizTreeCsv (Get-Content -LiteralPath $csv -Raw)
    $sys = '^' + [regex]::Escape($env:SystemDrive) + '\\(Windows|Program Files|Program Files \(x86\)|ProgramData|Recovery|System Volume Information|\$Recycle\.Bin)\\?$'
    $drive = [regex]::Escape($env:SystemDrive)
    $userDirs = @($rows | Where-Object {
            $_.Depth -ge 1 -and $_.Path -notmatch $sys -and $_.Path -notmatch '\\(Windows|Program Files[^\\]*|ProgramData)\\' -and
            $_.Path -notmatch ('^' + $drive + '\\Users(\\[^\\]+)?$')     # list inside the user folders, not the whole profile
        } | Sort-Object Size -Descending)
    # keep the biggest folders that are not inside an already listed one
    $pick = @()
    foreach ($f in $userDirs) {
        if ($pick.Count -ge 15) { break }
        if ($pick | Where-Object { $f.Path.StartsWith($_.Path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }) { continue }
        $pick += $f
    }
    foreach ($f in $pick) { Add-TGLine $r ("{0,9}  {1}" -f (Format-PDSize $f.Size), $f.Path) '' }
    $win = $rows | Where-Object { $_.Path -match ('^' + [regex]::Escape($env:SystemDrive) + '\\Windows\\?$') } | Select-Object -First 1
    if ($win) { Add-TGLine $r ("(Windows folder: {0} - तो हाताने साफ करू नका; PC Doctor → वेग → cleanup वापरा.)" -f (Format-PDSize $win.Size)) ("(Windows folder: {0} - do not clean it by hand; use PC Doctor → Speed → cleanup.)" -f (Format-PDSize $win.Size)) }
    Add-TGLine $r 'हलवण्यासाठी: PC Doctor → "C: drive जागा" (files सुरक्षितपणे दुसऱ्या drive वर, Undo सह).' 'To move them: PC Doctor → "C: drive space" (moves files safely to another drive, with Undo).'
    $r.Status = 'ok'
    return $r
}

# WizTree export: first line is a "Generated by WizTree" comment, then a CSV header with "File Name","Size"...
function ConvertFrom-TGWizTreeCsv([string]$Text) {
    $lines = $Text -split "`r?`n"
    $start = 0
    for ($k = 0; $k -lt [math]::Min(5, $lines.Count); $k++) { if ($lines[$k] -match '^"?File Name"?,') { $start = $k; break } }
    $data = ($lines[$start..($lines.Count - 1)] -join "`n") | ConvertFrom-Csv
    @($data | Where-Object { $_.'File Name' } | ForEach-Object {
        $pth = $_.'File Name'.TrimEnd('\')
        [pscustomobject]@{ Path = $pth; Size = [double]$_.Size; Depth = ($pth.Split('\').Count - 1) }
    })
}

function Invoke-TGKeys([string]$UsbRoot, $P) {
    $r = New-TGResult 'ok' 'Product keys' 'Product keys'
    $lines = @()
    try {
        $k = (Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop).OA3xOriginalProductKey
        if ($k) { $lines += "Windows (BIOS): $k"; Add-TGLine $r "Windows key BIOS मध्ये आहे: $k - reinstall नंतर आपोआप activate होईल." "Windows key stored in the BIOS: $k - it activates by itself after a reinstall." }
        else { Add-TGLine $r 'BIOS मध्ये Windows key नाही (जुना PC / retail key).' 'No Windows key in the BIOS (older PC / retail key).' }
    } catch { }
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'produkey'
    if ($exe) {
        $out = Join-Path $env:TEMP 'sjv-keys.txt'
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        [void](Invoke-TGProcess $exe @('/stext', "`"$out`"") 60 -Hidden)
        if (Test-Path -LiteralPath $out) {
            $blocks = (Get-Content -LiteralPath $out -Raw) -split '(?m)^={5,}\s*$'
            foreach ($b in $blocks) {
                $n = [regex]::Match($b, '(?m)^Product Name\s*:\s*(.+?)\s*$'); $kk = [regex]::Match($b, '(?m)^Product Key\s*:\s*(.+?)\s*$')
                if ($n.Success -and $kk.Success) { $lines += "$($n.Groups[1].Value): $($kk.Groups[1].Value)"; Add-TGLine $r "$($n.Groups[1].Value): $($kk.Groups[1].Value)" '' }
            }
        }
    }
    if ($lines.Count -and $P.ReportDir) {
        $f = Join-Path $P.ReportDir 'product-keys.txt'
        Set-Content -LiteralPath $f -Value (@("Product keys - $env:COMPUTERNAME - $(Get-Date)") + $lines) -Encoding UTF8
        $r.File = $f
        Add-TGLine $r 'Keys Reports folder मध्ये product-keys.txt मध्ये save केल्या - customer शिवाय कोणाला देऊ नका.' 'Keys saved to product-keys.txt in the Reports folder - share them only with the customer.'
    }
    if (-not $lines.Count) { $r.Status = 'info' }
    return $r
}

function Invoke-TGNetwork([string]$UsbRoot, $P) {
    $r = New-TGResult 'ok' 'Internet तपासणी' 'Internet check'
    $gw = $null
    try { $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1).NextHop } catch { }
    $ping = { param($h)
        $t = @(Test-Connection -ComputerName $h -Count 4 -ErrorAction SilentlyContinue)
        if (-not $t.Count) { return [pscustomobject]@{ Ok = $false; Ms = $null; Lost = 4 } }
        return [pscustomobject]@{ Ok = $true; Ms = [math]::Round(($t | Measure-Object ResponseTime -Average).Average); Lost = 4 - $t.Count } }
    $up = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    if (-not $up.Count) {
        $r.Status = 'bad'; $r.HeadMr = 'Network जोडलेले नाही'; $r.HeadEn = 'Not connected to any network'
        Add-TGLine $r 'WiFi / LAN cable जोडलेले नाही, किंवा driver नाही. PC Doctor → दुरुस्ती → Drivers तपासा.' 'No WiFi / LAN connection, or no driver. Check PC Doctor → Repair → Drivers.'
        return $r
    }
    Add-TGLine $r ("जोडलेले: " + (($up | ForEach-Object { "$($_.Name) ($($_.LinkSpeed))" }) -join ', ')) ("Connected: " + (($up | ForEach-Object { "$($_.Name) ($($_.LinkSpeed))" }) -join ', '))
    if ($gw) {
        $g = & $ping $gw
        if ($g.Ok) { Add-TGLine $r "✔ Router ($gw): $($g.Ms) ms" '' } else { Set-TGWorse $r 'bad'; Add-TGLine $r "✖ Router ($gw) उत्तर देत नाही - router restart करा / WiFi password / cable तपासा." "✖ Router ($gw) does not answer - restart the router / check the WiFi password / cable." }
    } else { Set-TGWorse $r 'bad'; Add-TGLine $r '✖ Router (gateway) मिळाला नाही - IP मिळत नाही. PC Doctor → दुरुस्ती → "Internet / Network reset".' '✖ No router (gateway) - no IP address. PC Doctor → Repair → "Internet / Network reset".' }
    $i = & $ping '8.8.8.8'
    if ($i.Ok) {
        Add-TGLine $r "✔ Internet (8.8.8.8): $($i.Ms) ms$(if ($i.Lost) { ", $($i.Lost)/4 lost" })" ''
        if ($i.Lost -ge 1 -or $i.Ms -gt 150) { Set-TGWorse $r 'warn'; Add-TGLine $r '⚠ Internet हळू / packets हरवतात - WiFi signal कमी किंवा ISP.' '⚠ Slow internet / packet loss - weak WiFi signal or the ISP.' }
    } else { Set-TGWorse $r 'bad'; Add-TGLine $r '✖ Router चालतो पण internet नाही → ISP / recharge / router चा internet light तपासा.' '✖ The router works but there is no internet → check the ISP / recharge / the router''s internet light.' }
    $dnsOk = $false
    try { $null = Resolve-DnsName -Name 'www.google.com' -Type A -ErrorAction Stop -QuickTimeout; $dnsOk = $true } catch { }
    if ($dnsOk) { Add-TGLine $r '✔ DNS (website नावे) ठीक' '✔ DNS (website names) works' }
    elseif ($i.Ok) { Set-TGWorse $r 'bad'; Add-TGLine $r '✖ Internet आहे पण website नावे उघडत नाहीत (DNS). PC Doctor → दुरुस्ती → "Internet / Network reset".' '✖ Internet works but website names do not resolve (DNS). PC Doctor → Repair → "Internet / Network reset".' }
    $r.HeadMr = switch ($r.Status) { 'bad' { 'Internet मध्ये समस्या सापडली' } 'warn' { 'Internet चालते पण हळू' } default { 'Internet ठीक चालते' } }
    $r.HeadEn = switch ($r.Status) { 'bad' { 'Internet problem found' } 'warn' { 'Internet works but slowly' } default { 'Internet works fine' } }
    return $r
}

function Invoke-TGMemDiag([string]$UsbRoot, $P) {
    $r = New-TGResult 'info' 'RAM test निकाल' 'RAM test result'
    $ev = $null
    try { $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction Stop } catch { }
    if (-not $ev) {
        $r.HeadMr = 'या PC वर अजून RAM test झालेला नाही'; $r.HeadEn = 'No RAM test has run on this PC yet'
        Add-TGLine $r '"उघडा" दाबून "Restart now and check" निवडा. Test नंतर परत इथे निकाल पाहा.' 'Press "Open" and choose "Restart now and check". Come back here for the result afterwards.'
        return $r
    }
    $when = $ev.TimeCreated.ToString('dd-MM-yyyy HH:mm')
    if ($ev.Id -eq 1201) { $r.Status = 'ok'; $r.HeadMr = "RAM ठीक आहे ($when)"; $r.HeadEn = "RAM is fine ($when)"; Add-TGLine $r 'Windows Memory Diagnostic ला errors सापडल्या नाहीत.' 'Windows Memory Diagnostic found no errors.' }
    else { $r.Status = 'bad'; $r.HeadMr = "RAM मध्ये errors ($when)"; $r.HeadEn = "RAM errors found ($when)"; Add-TGLine $r 'RAM stick एक-एक काढून test करा; errors देणारी stick बदला. खात्रीसाठी pendrive वरून MemTest86+.' 'Test the sticks one at a time and replace the failing one. Confirm with MemTest86+ from the USB.' }
    return $r
}

function Invoke-TGStressCpu([string]$UsbRoot, $P) {
    $minutes = if ($P.Minutes) { [double]$P.Minutes } else { 10.0 }
    $r = New-TGResult 'info' 'CPU / RAM stress test' 'CPU / RAM stress test'
    $exe = Find-TGTool -UsbRoot $UsbRoot -Id 'prime95'
    if (-not $exe) { $r.HeadMr = 'Prime95 pendrive वर नाही'; $r.HeadEn = 'Prime95 is not on the USB'; return $r }
    $dir = Split-Path $exe
    Initialize-TGToolConfig 'prime95' $exe
    $res = Join-Path $dir 'results.txt'
    $before = if (Test-Path -LiteralPath $res) { (Get-Item -LiteralPath $res).Length } else { 0 }
    $t0Temp = Get-TGThermalC
    Write-PDLog "Stress test $minutes मिनिटे सुरू (Prime95)" 'STEP'
    $p = Start-Process -FilePath $exe -ArgumentList '-t' -WorkingDirectory $dir -PassThru -WindowStyle Minimized
    $t0 = Get-Date; $maxT = $t0Temp; $why = $null
    while (((Get-Date) - $t0).TotalMinutes -lt $minutes) {
        Start-Sleep -Seconds 5
        $el = ((Get-Date) - $t0).TotalSeconds
        Set-PDProgress ([int](100 * $el / ($minutes * 60))) ("{0:mm\:ss} / {1} min" -f ((Get-Date) - $t0), $minutes)
        if ($p.HasExited) { $why = 'exited'; break }
        if (Test-TGCancel) { $why = 'cancel'; break }
        $c = Get-TGThermalC
        if ($null -ne $c) { if ($null -eq $maxT -or $c -gt $maxT) { $maxT = $c }; if ($c -ge 95) { $why = 'hot'; break } }
    }
    try { if (-not $p.HasExited) { $p.Kill() } } catch { }
    $ran = ((Get-Date) - $t0)
    $txt = ''
    if (Test-Path -LiteralPath $res) {
        $all = Get-Content -LiteralPath $res -Raw
        $txt = if ($before -gt 0 -and $before -lt $all.Length) { $all.Substring([int]$before) } else { $all }
    }
    $errs = @($txt -split "`r?`n" | Where-Object { $_ -match '(?i)FATAL ERROR|Hardware failure|ROUNDING|SUM\(INPUTS\)|ILLEGAL SUMOUT|Possible hardware' })
    Add-TGLine $r ("चाललेला वेळ: {0:mm\:ss}" -f $ran) ("Ran for: {0:mm\:ss}" -f $ran)
    if ($null -ne $maxT) { Add-TGLine $r "सगळ्यात जास्त तापमान (Windows नुसार): $maxT°C" "Highest temperature (reported by Windows): $maxT°C" }
    if ($errs.Count) {
        $r.Status = 'bad'; $r.HeadMr = 'Stress test मध्ये errors - hardware दोष'; $r.HeadEn = 'Errors in the stress test - hardware fault'
        foreach ($e in ($errs | Select-Object -First 4)) { Add-TGLine $r ('• ' + $e.Trim()) '' }
        Add-TGLine $r 'कारण: RAM (MemTest86+ ने तपासा), गरम होणे (धूळ / thermal paste), किंवा overclock / BIOS settings. BIOS "Load defaults" करून पुन्हा test करा.' 'Likely causes: RAM (test with MemTest86+), overheating (dust / thermal paste), or overclock / BIOS settings. Load BIOS defaults and test again.'
    } elseif ($why -eq 'hot') {
        $r.Status = 'bad'; $r.HeadMr = 'CPU 95°C ओलांडला - test थांबवला'; $r.HeadEn = 'CPU passed 95°C - test stopped'
        Add-TGLine $r 'Cooling अपुरे: fan / heatsink ची धूळ साफ करा, thermal paste बदला, laptop ला cooling pad.' 'Cooling is not enough: clean the fan / heatsink, renew the thermal paste, use a cooling pad for laptops.'
    } elseif ($why -eq 'cancel') { $r.HeadMr = 'Test मध्येच थांबवला'; $r.HeadEn = 'Test stopped early' }
    elseif ($why -eq 'exited') { $r.Status = 'warn'; $r.HeadMr = 'Prime95 मध्येच बंद झाला'; $r.HeadEn = 'Prime95 closed early'; Add-TGLine $r 'Prime95 window बंद केली गेली किंवा तो crash झाला. पुन्हा प्रयत्न करा.' 'The Prime95 window was closed or it crashed. Try again.' }
    else {
        $r.Status = if ($null -ne $maxT -and $maxT -ge 90) { 'warn' } else { 'ok' }
        $r.HeadMr = "$minutes मिनिटे पूर्ण load - errors नाहीत (CPU / RAM stable)"; $r.HeadEn = "$minutes minutes at full load - no errors (CPU / RAM stable)"
        if ($r.Status -eq 'warn') { Add-TGLine $r '⚠ Stable आहे पण 90°C च्या वर गेला - cooling साफ करणे चांगले.' '⚠ Stable, but it went above 90°C - cleaning the cooling is advisable.' }
        if ($null -eq $maxT) { Add-TGLine $r 'हा PC Windows ला तापमान देत नाही - test चालू असताना HWiNFO मध्ये तापमान पाहणे चांगले.' 'This PC does not report temperatures to Windows - watch them in HWiNFO during the test.' }
    }
    return $r
}

# Single entry point used by the GUI job
function Invoke-TGAuto {
    param([Parameter(Mandatory)][string]$Handler, [Parameter(Mandatory)][string]$UsbRoot, $P = @{})
    if ($global:PDState) { $global:PDState.Cancel = $false }
    switch ($Handler) {
        'disk-health'    { return Invoke-TGDiskHealth $UsbRoot $P }
        'battery'        { return Invoke-TGBattery $UsbRoot $P }
        'system-summary' { return Invoke-TGSystemSummary $UsbRoot $P }
        'temps'          { return Invoke-TGTemps $UsbRoot $P }
        'crashes'        { return Invoke-TGCrashes $UsbRoot $P }
        'msert'          { return Invoke-TGMsert $UsbRoot $P }
        'bigfolders'     { return Invoke-TGBigFolders $UsbRoot $P }
        'keys'           { return Invoke-TGKeys $UsbRoot $P }
        'network'        { return Invoke-TGNetwork $UsbRoot $P }
        'memdiag'        { return Invoke-TGMemDiag $UsbRoot $P }
        'stress-cpu'     { return Invoke-TGStressCpu $UsbRoot $P }
        default          { throw "unknown check: $Handler" }
    }
}

Export-ModuleMember -Function New-TGResult, Add-TGLine, Get-TGCatalog, Get-TGGuide, Find-TGTool, Initialize-TGToolConfig, Set-TGIniValue,
    ConvertFrom-TGDiskInfo, ConvertFrom-TGWizTreeCsv, Get-TGDriverHint, Invoke-TGAuto
