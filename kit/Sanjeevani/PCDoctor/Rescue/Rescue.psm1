# Sanjeevani PC Doctor Rescue - functions for repairing a Windows that does not start.
# Runs inside Hiren's BootCD PE (PowerShell 7) and also in Windows PowerShell 5.1.
# Everything works on an OFFLINE Windows installation (e.g. C:\Windows while booted from the USB).
Set-StrictMode -Off

$script:RXLog = $null
function Set-RXLogFile([string]$Path) { $script:RXLog = $Path }
function Write-RX {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')][string]$Level = 'INFO')
    $color = @{ INFO = 'Gray'; OK = 'Green'; WARN = 'Yellow'; ERR = 'Red'; STEP = 'Cyan' }[$Level]
    $prefix = @{ INFO = '   '; OK = ' + '; WARN = ' ! '; ERR = ' x '; STEP = '>> ' }[$Level]
    Write-Host ($prefix + $Message) -ForegroundColor $color
    if ($script:RXLog) { try { Add-Content -LiteralPath $script:RXLog -Value ('[{0:HH:mm:ss}] {1,-4} {2}' -f (Get-Date), $Level, $Message) -Encoding UTF8 } catch { } }
}

function Invoke-RXTool {
    # runs a console program and shows its output live; returns the exit code
    param([string]$File, [string[]]$Arguments)
    Write-RX ("> {0} {1}" -f (Split-Path $File -Leaf), ($Arguments -join ' ')) 'STEP'
    & $File @Arguments 2>&1 | ForEach-Object { $l = "$_".Replace([string][char]0, '').TrimEnd(); if ($l) { Write-Host "     $l" -ForegroundColor DarkGray } }
    return $LASTEXITCODE
}

# ------------------------------------------------------------------ installed Windows
function Get-RXWindows {
    $pe = $env:SystemDrive.TrimEnd(':').ToUpper()
    $out = @()
    foreach ($l in [char[]]'CDEFGHIJKLMNOPQRSTUVWYZ') {
        $root = "${l}:\"
        if ("$l" -eq $pe) { continue }
        if (-not (Test-Path -LiteralPath "${root}Windows\System32\config\SYSTEM")) { continue }
        $build = 0; $ver = ''
        try { $vi = (Get-Item -LiteralPath "${root}Windows\System32\ntoskrnl.exe").VersionInfo; $build = $vi.FileBuildPart; $ver = $vi.ProductVersion } catch { }
        $drv = $null
        try { $drv = [IO.DriveInfo]::new($root) } catch { }
        $out += [pscustomobject]@{
            Drive = "${l}:"; Root = $root; Build = [int]$build; Version = $ver
            SizeGB = $(if ($drv) { [math]::Round($drv.TotalSize / 1GB) } else { 0 })
            FreeGB = $(if ($drv) { [math]::Round($drv.AvailableFreeSpace / 1GB, 1) } else { 0 })
            Users = @(Get-ChildItem -LiteralPath "${root}Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' } | ForEach-Object { $_.Name })
        }
    }
    return $out
}

# Loads a registry hive file under HKLM\<Name>, runs $Script with the PowerShell path, always unloads.
function Use-RXHive {
    param([Parameter(Mandatory)][string]$HiveFile, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Script)
    $null = & reg.exe load "HKLM\$Name" $HiveFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "could not load registry hive $HiveFile" }
    try { return (& $Script "HKLM:\$Name") }
    finally {
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        for ($i = 0; $i -lt 5; $i++) { $null = & reg.exe unload "HKLM\$Name" 2>&1; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep -Milliseconds 500; [GC]::Collect() }
    }
}

function Get-RXControlSet([string]$HiveRoot) {
    $cur = (Get-ItemProperty -Path "$HiveRoot\Select" -Name Current -ErrorAction Stop).Current
    return ('{0}\ControlSet{1:000}' -f $HiveRoot, [int]$cur)
}

function Get-RXOfflineInfo($Win) {
    $info = [pscustomobject]@{ ComputerName = ''; EditionID = ''; ProductName = ''; DisplayVersion = '' }
    try {
        Use-RXHive -HiveFile "$($Win.Root)Windows\System32\config\SYSTEM" -Name 'SJV_SYS' -Script {
            param($r) $cs = Get-RXControlSet $r
            $info.ComputerName = (Get-ItemProperty "$cs\Control\ComputerName\ComputerName" -ErrorAction SilentlyContinue).ComputerName
        } | Out-Null
    } catch { }
    try {
        Use-RXHive -HiveFile "$($Win.Root)Windows\System32\config\SOFTWARE" -Name 'SJV_SW' -Script {
            param($r) $cv = Get-ItemProperty "$r\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
            $info.EditionID = $cv.EditionID; $info.ProductName = $cv.ProductName; $info.DisplayVersion = $cv.DisplayVersion
        } | Out-Null
    } catch { }
    return $info
}

# ------------------------------------------------------------------ network / missing drivers
function Test-RXInternet {
    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8
        return ($r.Content -match 'Microsoft Connect Test')
    } catch { return $false }
}

# Devices that currently have no working driver (in the running PE)
function Get-RXDevicesWithoutDriver {
    @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -in 1, 10, 18, 28, 31, 37, 39 } |
        ForEach-Object { [pscustomobject]@{ Name = $(if ($_.Name) { $_.Name } else { $_.DeviceID }); Class = [string]$_.PNPClass; HardwareIds = @($_.HardwareID); Code = [int]$_.ConfigManagerErrorCode } })
}

# Turns full hardware ids into the short vendor/device keys that INF files list
function Get-RXIdKeys([string[]]$HardwareIds) {
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($h in $HardwareIds) {
        if (-not $h) { continue }
        $m = [regex]::Match($h, '(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})', 'IgnoreCase'); if ($m.Success) { $keys.Add($m.Value); continue }
        $m = [regex]::Match($h, '(VID_[0-9A-F]{4}&PID_[0-9A-F]{4})', 'IgnoreCase'); if ($m.Success) { $keys.Add($m.Value); continue }
        $m = [regex]::Match($h, '^(ACPI|HID)\\([^\\&]+)', 'IgnoreCase'); if ($m.Success) { $keys.Add($m.Groups[2].Value); continue }
        $keys.Add($h)
    }
    return @($keys | Where-Object { $_.Length -ge 6 } | Select-Object -Unique)
}

# Finds INF files in a driver store (normally the broken PC's own Windows) that support the given devices
function Find-RXMatchingInfs {
    param([Parameter(Mandatory)][string]$DriverStore, [Parameter(Mandatory)][object[]]$Devices)
    $want = @{}
    foreach ($d in $Devices) { foreach ($k in (Get-RXIdKeys $d.HardwareIds)) { $want[$k.ToUpper()] = $d.Name } }
    if ($want.Count -eq 0 -or -not (Test-Path -LiteralPath $DriverStore)) { return @() }
    $hits = @()
    foreach ($inf in Get-ChildItem -LiteralPath $DriverStore -Filter *.inf -Recurse -File -ErrorAction SilentlyContinue) {
        $txt = $null
        try { $txt = (Get-Content -LiteralPath $inf.FullName -Raw -ErrorAction Stop).ToUpper() } catch { continue }
        foreach ($k in $want.Keys) {
            if ($txt.Contains($k)) { $hits += [pscustomobject]@{ Inf = $inf.FullName; Device = $want[$k]; Key = $k }; break }
        }
    }
    return $hits
}

function Install-RXDriversFromWindows($Win) {
    $devs = @(Get-RXDevicesWithoutDriver)
    if (-not $devs.Count) { Write-RX 'All devices already have a driver.' 'OK'; return 0 }
    Write-RX ("{0} device(s) without a driver: {1}" -f $devs.Count, (($devs | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', '))
    $store = "$($Win.Root)Windows\System32\DriverStore\FileRepository"
    Write-RX "Looking for their drivers inside the PC's own Windows ($store) ..." 'STEP'
    $hits = @(Find-RXMatchingInfs -DriverStore $store -Devices $devs)
    if (-not $hits.Count) { Write-RX 'No matching drivers found in this PC''s Windows.' 'WARN'; return 0 }
    $ok = 0
    foreach ($h in $hits) {
        Write-RX ("Loading driver for {0}: {1}" -f $h.Device, (Split-Path (Split-Path $h.Inf) -Leaf))
        $null = & drvload.exe $h.Inf 2>&1
        if ($LASTEXITCODE -eq 0) { $ok++ } else { Write-RX "drvload failed ($LASTEXITCODE)" 'WARN' }
    }
    Write-RX "$ok driver(s) loaded." 'OK'
    return $ok
}

# ------------------------------------------------------------------ blue screens
function Get-RXCrashes {
    param([Parameter(Mandatory)]$Win, [Parameter(Mandatory)][string]$BlueScreenView, [string]$WorkDir = $env:TEMP)
    $dumpDir = "$($Win.Root)Windows\Minidump"
    $dumps = @(Get-ChildItem -LiteralPath $dumpDir -Filter *.dmp -ErrorAction SilentlyContinue)
    if (-not $dumps.Count) { return @() }
    # header line in the CSV so columns can be read by name
    Set-Content -LiteralPath (Join-Path (Split-Path $BlueScreenView) 'BlueScreenView.cfg') -Value "[General]`r`nAddExportHeaderLine=1" -Encoding ASCII -ErrorAction SilentlyContinue
    $csv = Join-Path $WorkDir 'sjv-crashes.csv'
    Remove-Item -LiteralPath $csv -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $BlueScreenView -ArgumentList @('/MiniDumpFolder', "`"$dumpDir`"", '/scomma', "`"$csv`"") -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { } }
    if (-not (Test-Path -LiteralPath $csv)) { return @() }
    return ConvertFrom-RXCrashCsv (Get-Content -LiteralPath $csv -Raw)
}

function ConvertFrom-RXCrashCsv([string]$Text) {
    $rows = @($Text | ConvertFrom-Csv)
    @($rows | ForEach-Object {
        [pscustomobject]@{
            Time = $_.'Crash Time'; BugCheck = $_.'Bug Check String'; Code = $_.'Bug Check Code'
            Driver = $_.'Caused By Driver'; Company = $_.'Company'; Description = $_.'File Description'; Product = $_.'Product Name'
        }
    })
}

function Get-RXCrashSummary([object[]]$Crashes) {
    @($Crashes | Where-Object { $_.Driver } | Group-Object Driver | Sort-Object Count -Descending | ForEach-Object {
        $last = $_.Group | Select-Object -First 1
        [pscustomobject]@{
            Driver = $_.Name; Count = $_.Count; BugChecks = (($_.Group | ForEach-Object { $_.BugCheck } | Select-Object -Unique) -join ', ')
            Company = $last.Company; Description = $last.Description
            IsMicrosoft = [bool]($last.Company -match 'Microsoft' -or $_.Name -match '^(ntoskrnl|hal|ntkrnlmp|win32k\w*|Wdf01000|storport|classpnp|ndis|tcpip|fltmgr|ci|cng)\.(exe|sys|dll)$')
        }
    })
}

# ------------------------------------------------------------------ offline driver services
function Find-RXDriverService {
    param([Parameter(Mandatory)][string]$ServicesKey, [Parameter(Mandatory)][string]$SysFile)
    $base = [IO.Path]::GetFileNameWithoutExtension($SysFile)
    foreach ($k in Get-ChildItem -LiteralPath $ServicesKey -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        $img = [string]$p.ImagePath
        if (($img -and $img -match ('\\' + [regex]::Escape($SysFile) + '$')) -or ($k.PSChildName -eq $base -and $p.Type -in 1, 2)) {
            return [pscustomobject]@{ Name = $k.PSChildName; Start = [int]$p.Start; ImagePath = $img; Group = [string]$p.Group; Key = $k.PSPath }
        }
    }
    return $null
}

# Disables a crashing third-party driver in the offline Windows (Start = 4). Boot-start drivers are refused.
function Disable-RXDriver {
    param([Parameter(Mandatory)]$Win, [Parameter(Mandatory)][string]$SysFile, [Parameter(Mandatory)][string]$UndoFile, [string]$HiveFile)
    if (-not $HiveFile) { $HiveFile = "$($Win.Root)Windows\System32\config\SYSTEM" }
    $file = "$($Win.Root)Windows\System32\drivers\$SysFile"
    $company = ''
    try { $company = (Get-Item -LiteralPath $file -ErrorAction Stop).VersionInfo.CompanyName } catch { }
    if ($company -match 'Microsoft') { throw "$SysFile is a Microsoft driver - disabling it could stop Windows from starting. Test RAM and disk instead." }
    return Use-RXHive -HiveFile $HiveFile -Name 'SJV_SYS' -Script {
        param($r)
        $cs = Get-RXControlSet $r
        $svc = Find-RXDriverService -ServicesKey "$cs\Services" -SysFile $SysFile
        if (-not $svc) { throw "no driver service uses $SysFile" }
        if ($svc.Start -eq 0) { throw "$($svc.Name) starts at boot (storage / file system driver). Disabling it can make Windows unbootable - not changed." }
        if ($svc.Start -eq 4) { Write-RX "$($svc.Name) is already disabled." 'OK'; return $svc }
        $undo = @()
        if (Test-Path -LiteralPath $UndoFile) { foreach ($x in (Get-Content -LiteralPath $UndoFile -Raw | ConvertFrom-Json)) { $undo += $x } }
        $undo += [pscustomobject]@{ Service = $svc.Name; OldStart = $svc.Start; Sys = $SysFile; Time = (Get-Date).ToString('s') }
        ConvertTo-Json -InputObject @($undo) | Set-Content -LiteralPath $UndoFile -Encoding UTF8
        Set-ItemProperty -LiteralPath $svc.Key -Name Start -Value 4 -Type DWord
        Write-RX ("Driver service '{0}' ({1}) disabled. It was Start={2}." -f $svc.Name, $SysFile, $svc.Start) 'OK'
        return $svc
    }
}

function Undo-RXDriverChanges {
    param([Parameter(Mandatory)]$Win, [Parameter(Mandatory)][string]$UndoFile, [string]$HiveFile)
    if (-not (Test-Path -LiteralPath $UndoFile)) { Write-RX 'Nothing to undo.'; return 0 }
    if (-not $HiveFile) { $HiveFile = "$($Win.Root)Windows\System32\config\SYSTEM" }
    $list = @(); foreach ($x in (Get-Content -LiteralPath $UndoFile -Raw | ConvertFrom-Json)) { $list += $x }
    $n = Use-RXHive -HiveFile $HiveFile -Name 'SJV_SYS' -Script {
        param($r)
        $cs = Get-RXControlSet $r
        $c = 0
        foreach ($u in $list) {
            $k = "$cs\Services\$($u.Service)"
            if (Test-Path -LiteralPath $k) { Set-ItemProperty -LiteralPath $k -Name Start -Value ([int]$u.OldStart) -Type DWord; $c++; Write-RX "Re-enabled $($u.Service) (Start=$($u.OldStart))" 'OK' }
        }
        $c
    }
    Move-Item -LiteralPath $UndoFile -Destination ($UndoFile + '.done-' + (Get-Date -Format 'yyyyMMddHHmm')) -Force
    return $n
}

# ------------------------------------------------------------------ updates
function Get-RXRecentPackages {
    param([Parameter(Mandatory)]$Win, [int]$Days = 14)
    $out = & dism.exe "/Image:$($Win.Root)" /Get-Packages /Format:Table /English 2>&1
    $cut = (Get-Date).AddDays(-$Days)
    $list = @()
    foreach ($l in $out) {
        $c = "$l" -split '\s*\|\s*'
        if ($c.Count -lt 4 -or $c[0] -match '^Package Identity|^-+') { continue }
        $t = [datetime]::MinValue
        [void][datetime]::TryParse($c[3].Trim(), [Globalization.CultureInfo]::GetCultureInfo('en-US'), 'None', [ref]$t)
        if ($t -ge $cut -and $c[0] -notmatch 'LanguagePack|FodMetadata|Client-Language|Package_for_ServicingStack') {
            $list += [pscustomobject]@{ Id = $c[0].Trim(); State = $c[1].Trim(); Type = $c[2].Trim(); Installed = $t }
        }
    }
    return ($list | Sort-Object Installed -Descending)
}

# ------------------------------------------------------------------ Windows ISO as repair source
function Find-RX7z([string]$UsbRoot) {
    foreach ($c in @((Join-Path $UsbRoot 'Sanjeevani\bin\7z.exe'), "$env:ProgramFiles\7-Zip\7z.exe", 'X:\Program Files\7-Zip\7z.exe')) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    $f = Get-ChildItem -LiteralPath ($env:SystemDrive + '\') -Filter 7z.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

function Get-RXWimBuild([string]$Wim, [int]$Index) {
    $o = & dism.exe /Get-WimInfo "/WimFile:$Wim" "/Index:$Index" /English 2>&1
    $m = [regex]::Match(($o -join "`n"), 'Version\s*:\s*10\.0\.(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Get-RXWimIndexes([string]$Wim) {
    $o = (& dism.exe /Get-WimInfo "/WimFile:$Wim" /English 2>&1) -join "`n"
    @([regex]::Matches($o, 'Index\s*:\s*(\d+)\s*\n\s*Name\s*:\s*([^\n]+)') | ForEach-Object { [pscustomobject]@{ Index = [int]$_.Groups[1].Value; Name = $_.Groups[2].Value.Trim() } })
}

function Export-RXInstallImage {
    # extracts sources\install.wim|esd from a Windows ISO with 7-Zip; returns the file path
    param([Parameter(Mandatory)][string]$Iso, [Parameter(Mandatory)][string]$SevenZip, [Parameter(Mandatory)][string]$Dest)
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    foreach ($n in 'install.wim', 'install.esd') {
        $existing = Join-Path $Dest $n
        if (Test-Path -LiteralPath $existing) { return $existing }
    }
    Write-RX "Extracting the Windows image from $(Split-Path $Iso -Leaf) (5-15 minutes) ..." 'STEP'
    & $SevenZip e $Iso ("-o" + $Dest) 'sources\install.wim' 'sources\install.esd' -y 2>&1 | Out-Null
    foreach ($n in 'install.wim', 'install.esd') { $f = Join-Path $Dest $n; if (Test-Path -LiteralPath $f) { return $f } }
    return $null
}

# ------------------------------------------------------------------ data rescue
function Get-RXUserData($Win) {
    $names = 'Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music', 'Favorites'
    $out = @()
    foreach ($u in $Win.Users) {
        foreach ($n in $names) {
            $p = "$($Win.Root)Users\$u\$n"
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $size = 0
            Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $size += $_.Length }
            if ($size -gt 0) { $out += [pscustomobject]@{ User = $u; Folder = $n; Path = $p; Bytes = [double]$size } }
        }
    }
    return $out
}

function Copy-RXUserData {
    param([Parameter(Mandatory)][object[]]$Items, [Parameter(Mandatory)][string]$Dest)
    $fail = 0
    foreach ($i in $Items) {
        $to = Join-Path $Dest "$($i.User)\$($i.Folder)"
        Write-RX ("Copying {0}\{1} -> {2}" -f $i.User, $i.Folder, $to) 'STEP'
        $null = & robocopy.exe $i.Path $to /E /COPY:DT /DCOPY:T /XJ /R:1 /W:1 /NP /NFL /NDL /NJH 2>&1
        if ($LASTEXITCODE -ge 8) { $fail++; Write-RX "some files could not be copied (robocopy $LASTEXITCODE)" 'WARN' }
    }
    return $fail
}

function Format-RXSize([double]$b) {
    if ($b -ge 1GB) { return '{0:N1} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    return '{0:N0} KB' -f ($b / 1KB)
}

Export-ModuleMember -Function *
