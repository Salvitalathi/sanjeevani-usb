# Sanjeevani PC Doctor - storage: analyse C:, create a DATA partition, move user data off C:.
# Safety rules: copy first, verify every file, only then delete the source copy.
Set-StrictMode -Off

if (-not ('PDKnownFolder' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PDKnownFolder {
    [DllImport("shell32.dll")] static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, [MarshalAs(UnmanagedType.LPWStr)] string pszPath);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr ppszPath);
    public static string Get(Guid g) {
        IntPtr p;
        if (SHGetKnownFolderPath(ref g, 0, IntPtr.Zero, out p) != 0) return null;
        string s = Marshal.PtrToStringUni(p);
        Marshal.FreeCoTaskMem(p);
        return s;
    }
    public static int Set(Guid g, string path) { return SHSetKnownFolderPath(ref g, 0, IntPtr.Zero, path); }
}
'@
}

$script:KnownFolders = [ordered]@{
    Desktop   = 'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'
    Documents = 'FDD39AD0-238F-46AF-ADB4-6C85480369C7'
    Downloads = '374DE290-123F-4565-9164-39C4925E467B'
    Pictures  = '33E28130-4E1E-4676-835A-98395C3BC3BB'
    Videos    = '18989B1D-99B5-455B-841C-AB7C74E4DDFC'
    Music     = '4BD8D571-6D19-48D3-BE97-422220080E43'
}
$script:MarathiNames = @{ Desktop = 'Desktop'; Documents = 'Documents (कागदपत्रे)'; Downloads = 'Downloads'; Pictures = 'Pictures (फोटो)'; Videos = 'Videos'; Music = 'Music (गाणी)' }

# Never offered for moving from the root of C:
$script:SystemRootFolders = @(
    'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Recovery', 'PerfLogs',
    'System Volume Information', '$Recycle.Bin', '$WinREAgent', '$SysReset', '$Windows.~BT', '$Windows.~WS',
    '$GetCurrent', 'Config.Msi', 'Documents and Settings', 'Boot', 'EFI', 'MSOCache', 'Intel', 'AMD', 'NVIDIA',
    'Drivers', 'OneDriveTemp', 'inetpub', 'Windows.old', 'ESD', 'Dell', 'HP', 'SWSetup', 'Lenovo', 'OEM',
    'XboxGames', 'Microsoft', 'tmp', 'temp', 'DumpStack.log.tmp', 'Sanjeevani'
)

function Get-PDKnownFolderPath { param([string]$Name) return [PDKnownFolder]::Get([guid]$script:KnownFolders[$Name]) }

function Test-PDSameUserAsDesktop {
    # Elevated as a *different* account? Then HKCU/known folders would belong to the wrong user.
    try {
        $ex = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'")
        foreach ($e in $ex) {
            $o = Invoke-CimMethod -InputObject $e -MethodName GetOwner
            if ($o.User -and $o.User -ne $env:USERNAME) { return $false }
        }
    } catch { }
    return $true
}

function Get-PDStorageAnalysis {
    Write-PDLog "$env:SystemDrive drive चे विश्लेषण करत आहे..." 'STEP'
    $sys = $env:SystemDrive
    $vol = Get-Volume -DriveLetter $sys.TrimEnd(':')
    $folders = @()
    $i = 0
    foreach ($n in $script:KnownFolders.Keys) {
        $i++; Set-PDProgress ([int](40 * $i / 6)) "Folder: $n"
        $p = Get-PDKnownFolderPath $n
        if (-not $p) { continue }
        $onSys = $p.StartsWith($sys, [StringComparison]::OrdinalIgnoreCase)
        $folders += [pscustomobject]@{
            Kind = 'Known'; Name = $n; Label = $script:MarathiNames[$n]; Path = $p
            SizeBytes = (Get-PDFolderSize $p); OnSystem = $onSys; OneDrive = ($p -match 'OneDrive')
        }
    }
    $roots = @()
    $dirs = @(Get-ChildItem -LiteralPath ($sys + '\') -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $script:SystemRootFolders -notcontains $_.Name -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and -not ($_.Attributes -band [IO.FileAttributes]::System) })
    $i = 0
    foreach ($d in $dirs) {
        $i++; Set-PDProgress (40 + [int](40 * $i / [math]::Max(1, $dirs.Count))) "Folder: $($d.Name)"
        $roots += [pscustomobject]@{ Kind = 'Root'; Name = $d.Name; Label = $d.Name; Path = $d.FullName; SizeBytes = (Get-PDFolderSize $d.FullName); OnSystem = $true; OneDrive = $false }
    }
    $hiber = 0; $pagef = 0
    try { $hiber = (Get-Item -LiteralPath "$sys\hiberfil.sys" -Force -ErrorAction Stop).Length } catch { }
    try { $pagef = (Get-Item -LiteralPath "$sys\pagefile.sys" -Force -ErrorAction Stop).Length } catch { }
    Set-PDProgress 90 'Other drives'
    $targets = @(Get-PDStorageTargets)
    $sysPart = Get-Partition -DriveLetter $sys.TrimEnd(':')
    $disk = Get-Disk -Number $sysPart.DiskNumber
    Set-PDProgress -1
    [pscustomobject]@{
        Drive = $sys; SizeBytes = $vol.Size; FreeBytes = $vol.SizeRemaining
        UserFolders = $folders; RootFolders = @($roots | Where-Object { $_.SizeBytes -gt 50MB } | Sort-Object SizeBytes -Descending)
        HiberfilBytes = $hiber; PagefileBytes = $pagef
        Targets = $targets
        DiskNumber = $sysPart.DiskNumber; DiskStyle = [string]$disk.PartitionStyle
        UnallocatedBytes = [double]$disk.LargestFreeExtent
        ShrinkableBytes = (Get-PDShrinkable)
    }
}

function Get-PDStorageTargets {
    $sysLetter = $env:SystemDrive.TrimEnd(':')
    $usbLetter = $null
    if ($global:PDCtx) { $usbLetter = $global:PDCtx.UsbRoot.Substring(0, 1) }
    $out = @()
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -eq 'NTFS' })) {
        $l = [string]$v.DriveLetter
        if ($l -eq $sysLetter -or $l -eq $usbLetter) { continue }
        try {
            $bus = (Get-Partition -DriveLetter $l -ErrorAction Stop | Get-Disk).BusType
            if ([string]$bus -eq 'USB') { continue }
        } catch { continue }
        $out += [pscustomobject]@{ Letter = $l; Label = $v.FileSystemLabel; FreeBytes = $v.SizeRemaining; SizeBytes = $v.Size }
    }
    return $out
}

# How much C: can be shrunk while still leaving max(20 GB, 15%) free on it.
function Get-PDShrinkable {
    $l = $env:SystemDrive.TrimEnd(':')
    try {
        $part = Get-Partition -DriveLetter $l
        $sup = Get-PartitionSupportedSize -DriveLetter $l -ErrorAction Stop
        $vol = Get-Volume -DriveLetter $l
        $keep = [math]::Max([double]20GB, 0.15 * [double]$vol.Size)
        $byFree = $vol.SizeRemaining - $keep
        $byFs = $part.Size - $sup.SizeMin
        return [math]::Max([double]0, [math]::Min([double]$byFree, [double]$byFs))
    } catch { return 0 }
}

function New-PDDataPartition {
    param([Parameter(Mandatory)][double]$SizeGB, [string]$Label = 'DATA')
    $l = $env:SystemDrive.TrimEnd(':')
    $part = Get-Partition -DriveLetter $l
    $disk = Get-Disk -Number $part.DiskNumber
    $need = [uint64]([math]::Floor($SizeGB) * 1GB)
    if ($need -lt 10GB) { throw 'नवीन partition किमान 10 GB हवा.' }
    $primaryCount = @(Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -ne 'Logical' }).Count
    if ($disk.PartitionStyle -eq 'MBR' -and $primaryCount -ge 4) { throw 'या disk वर (MBR) आधीच 4 partitions आहेत; नवीन partition बनवता येणार नाही.' }

    $shrunk = $false
    $origSize = $part.Size
    if ([uint64]$disk.LargestFreeExtent -lt $need) {
        $can = Get-PDShrinkable
        if ($need -gt $can) {
            throw ("C: मधून फक्त {0} पर्यंत जागा सुरक्षितपणे काढता येईल (C: वर किमान 20 GB / 15% मोकळे राहिले पाहिजे). आधी Cleanup करा किंवा size कमी द्या." -f (Format-PDSize $can))
        }
        Write-PDLog ("C: partition {0} ने लहान करत आहे (data सुरक्षित राहतो)..." -f (Format-PDSize $need)) 'STEP'
        Set-PDProgress 30 'C: shrink'
        Resize-Partition -DriveLetter $l -Size ($part.Size - $need) -ErrorAction Stop
        $shrunk = $true
        Write-PDLog 'C: shrink पूर्ण.' 'OK'
    }
    Set-PDProgress 70 'New partition'
    try {
        $free = [uint64](Get-Disk -Number $disk.Number).LargestFreeExtent
        $size = [math]::Min([double]$need, [double]$free)
        $np = New-Partition -DiskNumber $disk.Number -Size $size -AssignDriveLetter -ErrorAction Stop
        $null = Format-Volume -Partition $np -FileSystem NTFS -NewFileSystemLabel $Label -Confirm:$false -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        if ($shrunk) {
            Write-PDLog 'नवीन partition बनला नाही - C: पूर्वीच्या size वर परत आणत आहे...' 'WARN'
            try { Resize-Partition -DriveLetter $l -Size $origSize -ErrorAction Stop; Write-PDLog 'C: परत पूर्वीसारखा केला.' 'OK' }
            catch { Write-PDLog ('C: परत मोठा करता आला नाही - Disk Management मध्ये C: > Extend Volume करा: ' + $_.Exception.Message) 'ERR' }
        }
        throw "नवीन partition बनवता आला नाही: $msg"
    }
    $np = Get-Partition -DiskNumber $disk.Number -PartitionNumber $np.PartitionNumber
    Set-PDProgress -1
    Write-PDLog ("नवीन drive तयार: {0}: ({1}, {2})" -f $np.DriveLetter, $Label, (Format-PDSize $size)) 'OK'
    return [string]$np.DriveLetter
}

# Copies $Source into $Dest with robocopy, then deletes only those source files that exist
# in $Dest with identical size. Returns number of files that could not be moved.
function Move-PDTree {
    param([string]$Source, [string]$Dest, [switch]$AllOrNothing)
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    $log = Join-Path $global:PDCtx.ReportDir ("robocopy-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    $rcArgs = ('"{0}" "{1}" /E /COPY:DAT /DCOPY:DAT /XJ /XC /XN /XO /R:1 /W:1 /MT:8 /NP /NFL /NDL /UNILOG+:"{2}"' -f $Source.TrimEnd('\'), $Dest.TrimEnd('\'), $log)
    $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\robocopy.exe" -Arguments $rcArgs -ProgressLabel 'Copy'
    $srcRoot = (Get-Item -LiteralPath $Source -Force).FullName.TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -Force -File -ErrorAction SilentlyContinue)
    if ($code -lt 0 -or $code -ge 8) {
        Write-PDLog "Copy पूर्ण झाली नाही (robocopy $code). काहीही delete केले नाही." 'WARN'
        if ($AllOrNothing) { return $files.Count }
    }
    Write-PDLog 'Copy तपासून मूळ files काढत आहे...' 'STEP'
    # a file counts as safely copied only if size AND modified time match
    $ok = New-Object System.Collections.ArrayList
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($srcRoot.Length).TrimStart('\')
        $di = Get-Item -LiteralPath (Join-Path $Dest $rel) -Force -ErrorAction SilentlyContinue
        if ($di -and $di.Length -eq $f.Length -and [math]::Abs(($di.LastWriteTimeUtc - $f.LastWriteTimeUtc).TotalSeconds) -lt 3) { [void]$ok.Add($f) }
    }
    $left = $files.Count - $ok.Count
    if ($AllOrNothing -and $left -gt 0) {
        Write-PDLog "$left files जुळल्या नाहीत (वापरात / destination वर वेगळी file). Folder जसाच्या तसा C: वर ठेवला." 'WARN'
        return $left
    }
    if ($code -lt 0 -or $code -ge 8) { return $files.Count }
    foreach ($f in $ok) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $left++ } }
    # remove now-empty directories, deepest first
    Get-ChildItem -LiteralPath $srcRoot -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } }
    return $left
}

function Move-PDUserFolders {
    param([Parameter(Mandatory)][string[]]$Names, [Parameter(Mandatory)][string]$TargetDrive)
    if (-not (Test-PDSameUserAsDesktop)) { throw 'PC Doctor दुसऱ्या admin account ने चालू आहे. ज्या user चे folders हलवायचे त्याच user ने (admin म्हणून) चालवा.' }
    $root = Join-Path ($TargetDrive.TrimEnd(':\') + ':\') ('Users\' + $env:USERNAME)
    $report = @()
    $i = 0
    foreach ($n in $Names) {
        $i++
        $src = Get-PDKnownFolderPath $n
        if (-not $src) { continue }
        if (-not $src.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) { $report += "$n : आधीच दुसऱ्या drive वर आहे ($src)"; continue }
        if ($src -match 'OneDrive') { $report += "$n : OneDrive backup मध्ये आहे - OneDrive settings मधूनच बदला"; continue }
        $dest = Join-Path $root $n
        Write-PDLog ("[{0}/{1}] {2}: {3} -> {4}" -f $i, $Names.Count, $n, $src, $dest) 'STEP'
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\robocopy.exe" -Arguments ('"{0}" "{1}" /E /COPY:DAT /DCOPY:DAT /XJ /XC /XN /XO /R:1 /W:1 /MT:8 /NP /NFL /NDL' -f $src.TrimEnd('\'), $dest) -ProgressLabel "Copy $n"
        if ($code -lt 0 -or $code -ge 8) { $report += "$n : copy पूर्ण झाली नाही (काही files उघड्या असतील) - हलवले नाही"; continue }
        $hr = [PDKnownFolder]::Set([guid]$script:KnownFolders[$n], $dest)
        if ($hr -ne 0) { $report += ("$n : Windows ने नवीन location स्वीकारले नाही (0x{0:X})" -f $hr); continue }
        Add-PDUndo @{ Type = 'Note'; Text = "$n moved from $src to $dest (to undo: right-click folder > Properties > Location > Restore Default)" }
        $left = Move-PDTree -Source $src -Dest $dest
        if (-not (Get-ChildItem -LiteralPath $src -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue }
        if ($left -gt 0) { $report += "$n : हलवले. $left files (उघड्या / वापरात) जुन्या जागी राहिल्या - restart नंतर पुन्हा चालवा" }
        else { $report += "$n : यशस्वीरित्या $dest येथे हलवले" }
    }
    Write-PDLog 'Explorer restart करत आहे...' 'STEP'
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    for ($w = 0; $w -lt 10 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $w++) { Start-Sleep 1 }
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        # start the shell WITHOUT admin rights
        $null = & runas.exe /trustlevel:0x20000 explorer.exe 2>&1
    }
    foreach ($r in $report) { Write-PDLog $r 'OK' }
    return $report
}

# Moves a top-level folder like C:\Data and leaves a junction so old paths keep working.
function Move-PDRootFolders {
    param([Parameter(Mandatory)][string[]]$Paths, [Parameter(Mandatory)][string]$TargetDrive)
    $report = @()
    foreach ($p in $Paths) {
        $name = Split-Path $p -Leaf
        if ($script:SystemRootFolders -contains $name) { $report += "$name : system folder - हलवले नाही"; continue }
        $dest = Join-Path ($TargetDrive.TrimEnd(':\') + ':\') $name
        Write-PDLog "$p -> $dest" 'STEP'
        $left = Move-PDTree -Source $p -Dest $dest -AllOrNothing
        if ($left -eq 0) {
            try { [IO.Directory]::Delete($p, $false) } catch { }
            if (-not (Test-Path -LiteralPath $p)) {
                $null = & cmd.exe /c mklink /J "$p" "$dest" 2>&1
                $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                if ($it -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $report += "$name : $dest येथे हलवले (जुना path अजूनही चालतो - junction)" }
                else { $report += "$name : $dest येथे हलवले, पण junction बनले नाही - program चा path बदलावा लागेल" }
            } else { $report += "$name : हलवले, पण जुना रिकामा folder काढता आला नाही" }
        } else { $report += "$name : $left files वापरात / वेगळ्या असल्याने काहीच हलवले नाही. Program बंद करून पुन्हा करा." }
        Add-PDUndo @{ Type = 'Note'; Text = "$p moved to $dest" }
    }
    foreach ($r in $report) { Write-PDLog $r 'OK' }
    return $report
}

Export-ModuleMember -Function *
