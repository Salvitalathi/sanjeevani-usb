#Requires -Version 5.1
<#
    Sanjeevani Rescue USB - cleaner
    Finds space wasted on the pendrive and, only after you say Y, moves it to <USB>\_to_delete
    (instant on the same drive, and you can still get it back). A second question deletes that folder.

    What it looks for:
      * extra copies of the Snappy Driver Installer driver packs (update\SDIO_Update, SDIO_Update ...)
        - a pack is dropped only when drivers\ holds the same file, or a tested-good copy of it
      * older versions of the same driver pack, older SDIO program versions
      * exact duplicate files anywhere on the USB (same size and same content)
      * half-finished downloads (.part, .!qB, .crdownload ...), archives already unpacked, the Recycle Bin
      * on request: driver packs a Windows 10/11 repair never needs (XP, Server, TV, modem) and the
        Windows 7/8-only video packs - each asked separately
    Never touched: ventoy\, Sanjeevani\, Reports\ and Rescue\ (customer reports, driver backups, rescued files)
    and every file Setup registered in Sanjeevani\installed.json.

    Usage:  CLEAN.cmd            (finds the Sanjeevani USB by itself)
            Clean-Sanjeevani.ps1 -Usb F: [-ReportOnly] [-Yes]
#>
param(
    [string]$Usb,
    [switch]$ReportOnly,   # only show what would be removed
    [switch]$Yes,          # do not ask (moves to _to_delete, keeps it)
    [switch]$SlimDrivers,  # with -Yes: also remove driver packs a Windows 10/11 repair never needs (XP, Server, TV, modem)
    [switch]$NoWin7Drivers # with -Yes: also remove the Windows 7/8-only (-NT) video packs
)
$ErrorActionPreference = 'Stop'
function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Fmt([double]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }

Say ''
Say '  ================================================================' Cyan
Say '     SANJEEVANI RESCUE USB  -  Cleaner (duplicates / leftovers)' Cyan
Say '  ================================================================' Cyan

# ------------------------------------------------------------------ find the USB
if (-not $Usb) {
    $Usb = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -and (Test-Path -LiteralPath (Join-Path $_.Root 'Sanjeevani\installed.json')) } |
        Select-Object -First 1 -ExpandProperty Root
}
if (-not $Usb) { Say '  Sanjeevani USB not found. Plug it in, or run:  Clean-Sanjeevani.ps1 -Usb F:' Red; exit 1 }
$Root = $Usb.TrimEnd('\', ':') ; if ($Root.Length -eq 1) { $Root += ':' } ; $Root = $Root.TrimEnd('\') + '\'
if (-not (Test-Path -LiteralPath (Join-Path $Root 'Sanjeevani\installed.json'))) {
    Say "  $Root is not a Sanjeevani USB (Sanjeevani\installed.json missing). Nothing done." Red; exit 1
}
$Bin = Join-Path $Root '_to_delete'
Say "  USB: $Root" White

# files Setup registered - never removed
$refs = New-Object 'System.Collections.Generic.HashSet[string]'
try {
    $inst = Get-Content -LiteralPath (Join-Path $Root 'Sanjeevani\installed.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $inst.PSObject.Properties) { if ($p.Value.path) { [void]$refs.Add((Join-Path $Root $p.Value.path).ToLower()) } }
} catch { Say '  (could not read installed.json - continuing carefully)' DarkYellow }

$protected = '^' + [regex]::Escape($Root) + '(ventoy|sanjeevani|reports|rescue|mytools|_to_delete|system volume information|\$recycle\.bin)(\\|$)'
function Test-Protected([string]$p) { return ($p -imatch $protected) -or $refs.Contains($p.ToLower()) }

$plan = New-Object System.Collections.ArrayList   # @{ Op; Path; Dest; Bytes; Why }
$planned = New-Object 'System.Collections.Generic.HashSet[string]'
function Add-Plan([string]$Op, [string]$Path, [double]$Bytes, [string]$Why, [string]$Dest = '') {
    if ($planned.Contains($Path.ToLower())) { return }
    [void]$planned.Add($Path.ToLower())
    [void]$plan.Add([pscustomobject]@{ Op = $Op; Path = $Path; Dest = $Dest; Bytes = $Bytes; Why = $Why })
}
function Test-UnderPlanned([string]$p) {
    foreach ($x in $planned) { if ($p.ToLower().StartsWith($x.TrimEnd('\') + '\')) { return $true } }
    return $false
}
function Get-DirBytes([string]$d) { [double](Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }

$sevenZip = Get-ChildItem (Join-Path $Root 'Sanjeevani') -Recurse -Filter '7z.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
function Test-Archive([string]$f) {
    if (-not $sevenZip) { return $null }
    & $sevenZip t $f -bso0 -bse0 -bsp0 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ------------------------------------------------------------------ 0. viruses that reached the USB
$sjMod = Join-Path $Root 'Sanjeevani\PCDoctor\lib\Integrity.psm1'
$sjOk = $false
if (Test-Path -LiteralPath $sjMod) {
    try {
        Import-Module $sjMod -Force -DisableNameChecking
        $sjOk = $true
        Say "`n  Checking for changes made by viruses (checksums) ..." White
        $chk = Test-SJIntegrity -Root $Root -Full
        foreach ($l in (Format-SJResult $chk 'en')) { Say "   $l" $(if ($l -match '^✖') { 'Red' } elseif ($l -match '^✔') { 'Green' } else { 'DarkGray' }) }
        $quarMy = $false
        if (@($chk.NewMyTools).Count -and -not $ReportOnly) {
            $a = if ($Yes) { 'Y' } else { Read-Host '  Did YOU put the new MyTools programs there? Y = record them as trusted, N = quarantine them' }
            if ($a -match '^[yY]') { [void](Add-SJTrusted -Root $Root -Rel @($chk.NewMyTools)); Say '  Recorded.' Green } else { $quarMy = $true }
        }
        if (((Get-SJIssueCount $chk) -or $quarMy) -and -not $ReportOnly) {
            $go = $Yes -or ((Read-Host '  Quarantine these files and un-hide the folders now? Y/N') -match '^[yY]')
            if ($go) {
                $fix = Repair-SJIntegrity $chk -IncludeMyTools:$quarMy
                Say ("  Quarantined {0} file(s) in _to_delete\quarantine, un-hid {1} folder(s)." -f @($fix.Quarantined).Count, @($fix.Unhidden).Count) Green
                if (@($fix.Redownload).Count) { Say '  Changed tools were quarantined - run UPDATE.cmd to download clean copies.' Yellow }
            }
        }
    } catch { Say "  (virus check skipped: $($_.Exception.Message))" DarkYellow }
}

# ------------------------------------------------------------------ 1. Snappy Driver Installer copies
$toolsDir = Join-Path $Root 'Tools'
$sdioExe = Get-ChildItem $toolsDir -Recurse -File -Filter 'SDIO_x64*.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(update|SDIO_Update|_to_delete)\\' } |
    Sort-Object { $_.FullName.Length } | Select-Object -First 1
if ($sdioExe) {
    $sdioDir = $sdioExe.DirectoryName
    $main = Join-Path $sdioDir 'drivers'
    Say "`n  Checking driver packs in $($sdioDir.Substring($Root.Length)) ..." White
    $mainFiles = @{}
    if (Test-Path -LiteralPath $main) { Get-ChildItem -LiteralPath $main -File -Filter '*.7z' | ForEach-Object { $mainFiles[$_.Name.ToLower()] = $_ } }

    # newest version of each pack in drivers\ (DP_Sound_Intel_26082.7z -> base DP_Sound_Intel, ver 26082)
    $newest = @{}
    foreach ($f in $mainFiles.Values) {
        if ($f.Name -match '^(.+)_(\d{5})\.7z$') {
            $b = $Matches[1].ToLower(); $v = [int]$Matches[2]
            if (-not $newest.ContainsKey($b) -or $newest[$b] -lt $v) { $newest[$b] = $v }
        }
    }

    $copies = @(Get-ChildItem -LiteralPath $sdioDir -Recurse -Directory -Filter 'drivers' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $main -and @(Get-ChildItem -LiteralPath $_.FullName -File -Filter 'DP_*.7z' -ErrorAction SilentlyContinue).Count })
    foreach ($c in $copies) {
        $copyRoot = Split-Path $c.FullName      # e.g. ...\update\SDIO_Update
        $unresolved = 0
        foreach ($f in @(Get-ChildItem -LiteralPath $c.FullName -File -Filter '*.7z')) {
            $m = $mainFiles[$f.Name.ToLower()]
            if ($m -and $m.Length -eq $f.Length) { continue }                    # same pack - copy is spare
            if ($m) {
                Say "    $($f.Name): two different copies - testing ..." DarkGray
                $okMain = Test-Archive $m.FullName
                if ($okMain) { continue }
                if ($okMain -eq $false -and (Test-Archive $f.FullName)) {
                    Add-Plan 'replace' $f.FullName $f.Length "good copy replaces broken $($m.Name) in drivers" $m.FullName
                    continue
                }
                $unresolved++; continue
            }
            # pack missing from drivers\: keep it only if it is newer and not broken
            $older = $false
            if ($f.Name -match '^(.+)_(\d{5})\.7z$' -and $newest.ContainsKey($Matches[1].ToLower()) -and $newest[$Matches[1].ToLower()] -ge [int]$Matches[2]) { $older = $true }
            if ($older) { continue }
            $ok = Test-Archive $f.FullName
            if ($ok) { Add-Plan 'adopt' $f.FullName $f.Length 'pack missing from drivers - moved into drivers' (Join-Path $main $f.Name) }
            elseif ($ok -eq $false) { continue }                                  # broken partial download
            else { $unresolved++ }                                               # no 7-Zip to test it
        }
        if ($unresolved -eq 0) {
            Add-Plan 'bin' $copyRoot (Get-DirBytes $copyRoot) 'extra copy of the driver packs (drivers\ already has them)'
        } else {
            Say "    $($copyRoot.Substring($Root.Length)): $unresolved pack(s) could not be checked - folder kept" DarkYellow
        }
    }

    # older versions of the same pack inside drivers\
    foreach ($f in $mainFiles.Values) {
        if ($f.Name -match '^(.+)_(\d{5})\.7z$' -and $newest[$Matches[1].ToLower()] -gt [int]$Matches[2]) {
            Add-Plan 'bin' $f.FullName $f.Length 'older version of a driver pack (newer one is in drivers)'
        }
    }
    # older SDIO program files (SDIO_x64_R887.exe next to SDIO_x64_R889.exe)
    $exes = @(Get-ChildItem -LiteralPath $sdioDir -File -Filter 'SDIO*_R*.exe' | Where-Object { $_.Name -match '^(.+)_R(\d+)\.exe$' })
    foreach ($g in ($exes | Group-Object { ($_.Name -replace '_R\d+\.exe$', '').ToLower() })) {
        $keep = $g.Group | Sort-Object { [int]($_.Name -replace '^.+_R(\d+)\.exe$', '$1') } -Descending | Select-Object -First 1
        foreach ($x in $g.Group) { if ($x.FullName -ne $keep.FullName -and -not (Test-Protected $x.FullName)) { Add-Plan 'bin' $x.FullName $x.Length "older SDIO program (newer: $($keep.Name))" } }
    }
}

# driver packs that a Windows 10/11 technician USB does not need - offered separately, never removed silently
$slim1 = @(); $slim2 = @()
if ($sdioExe -and (Test-Path -LiteralPath $main)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $main -File -Filter 'DP_*.7z')) {
        if ($planned.Contains($f.FullName.ToLower())) { continue }
        if ($f.Name -match '-XP_|_Server|^DP_TV_|^DP_Modem_|^DP_xMobile_Telephone_') { $slim1 += $f }
        elseif ($f.Name -match '^DP_Videos?_.*-NT_') { $slim2 += $f }
    }
}

# ------------------------------------------------------------------ 2. leftovers
Say "`n  Looking for leftovers and duplicates ..." White
$all = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { -not ($_.FullName -imatch $protected) -and -not (Test-UnderPlanned $_.FullName) })

foreach ($f in $all) {
    if ($f.Name -match '\.(part|partial|!qb|crdownload|aria2|bc!|tmp)$' -and -not (Test-Protected $f.FullName)) {
        Add-Plan 'bin' $f.FullName $f.Length 'unfinished download / temporary file'
    }
}
# archives already unpacked: a .zip/.7z/.rar in a tool folder that also holds a program
foreach ($f in $all) {
    if ($f.Extension -notmatch '^\.(zip|7z|rar)$' -or (Test-Protected $f.FullName)) { continue }
    if ($f.FullName -match '\\(drivers|indexes|update|SDIO_Update)\\') { continue }
    if (-not $f.FullName.StartsWith($toolsDir + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
    $hasExe = @(Get-ChildItem -LiteralPath $f.DirectoryName -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).Count
    if ($hasExe) { Add-Plan 'bin' $f.FullName $f.Length 'archive already unpacked (the program is next to it)' }
}
# Ventoy cannot boot a .zip from the ISO folder
foreach ($f in $all) {
    if ($f.DirectoryName -ieq (Join-Path $Root 'ISO') -and $f.Extension -match '^\.(zip|7z|rar)$' -and -not (Test-Protected $f.FullName)) {
        Add-Plan 'bin' $f.FullName $f.Length 'archive in the ISO folder (cannot boot; Setup unpacks the ISO itself)'
    }
}

# exact duplicates (same size, same content) - keep the copy Setup uses / the one in its proper place
function Get-QuickHash([IO.FileInfo]$f) {
    if ($f.Length -le 48MB) { return (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
    $sha = [Security.Cryptography.SHA256]::Create(); $fs = [IO.File]::OpenRead($f.FullName)
    try {
        $chunk = 16MB; $buf = New-Object byte[] $chunk
        foreach ($o in @(0, [long]($f.Length / 2), ($f.Length - $chunk))) {
            $fs.Position = $o; $got = 0
            while ($got -lt $chunk) { $n = $fs.Read($buf, $got, $chunk - $got); if ($n -le 0) { break }; $got += $n }
            [void]$sha.TransformBlock($buf, 0, $got, $null, 0)
        }
        [void]$sha.TransformFinalBlock($buf, 0, 0)
        return [BitConverter]::ToString($sha.Hash)
    } finally { $fs.Close(); $sha.Dispose() }
}
function Get-KeepRank([string]$p) {
    $r = $p.Length
    if ($refs.Contains($p.ToLower())) { $r -= 100000 }
    if ($p -match '\\(update|SDIO_Update|backup|old)\\|\(\d+\)|[ _-]copy\b|- Copy') { $r += 1000 }
    return $r
}
$left = @($all | Where-Object { $_.Length -ge 1MB -and -not $planned.Contains($_.FullName.ToLower()) })
foreach ($g in ($left | Group-Object Length | Where-Object Count -gt 1)) {
    foreach ($h in ($g.Group | Group-Object { Get-QuickHash $_ } | Where-Object Count -gt 1)) {
        $keep = $h.Group | Sort-Object { Get-KeepRank $_.FullName } | Select-Object -First 1
        foreach ($d in $h.Group) {
            if ($d.FullName -ne $keep.FullName -and -not (Test-Protected $d.FullName)) {
                Add-Plan 'bin' $d.FullName $d.Length ("same file as " + $keep.FullName.Substring($Root.Length))
            }
        }
    }
}

# Recycle Bin on the USB
$rb = Join-Path $Root '$RECYCLE.BIN'
if (Test-Path -LiteralPath $rb) {
    $rbBytes = Get-DirBytes $rb
    if ($rbBytes -ge 1MB) { Add-Plan 'empty-recycle' $rb $rbBytes 'Recycle Bin of the USB' }
}

# ------------------------------------------------------------------ report
function Show-Slim([object[]]$files, [string]$title) {
    $b = ($files | Measure-Object Length -Sum).Sum
    Say ''
    Say ("  {0}  ({1}, {2} packs):" -f $title, (Fmt $b), $files.Count) White
    Say ('     ' + (($files | Sort-Object Length -Descending | ForEach-Object { $_.Name -replace '_\d{5}\.7z$', '' }) -join ', ')) DarkGray
    return $b
}
$addSlim = { param($files, $why) foreach ($f in $files) { Add-Plan 'bin' $f.FullName $f.Length $why } }
if ($slim1.Count) {
    [void](Show-Slim $slim1 'Driver packs never needed for Windows 10/11 (Windows XP, Windows Server, TV tuner, modem)')
    $take = if ($ReportOnly) { $false } elseif ($Yes) { [bool]$SlimDrivers } else { (Read-Host '  Remove these too? Y/N') -match '^[yY]' }
    if ($take) { & $addSlim $slim1 'driver pack not needed for Windows 10/11 PCs' }
}
if ($slim2.Count) {
    [void](Show-Slim $slim2 'Video driver packs for old Windows 7/8 PCs only (-NT)')
    Say '     Keep these if you still repair Windows 7/8 PCs.' DarkGray
    $take = if ($ReportOnly) { $false } elseif ($Yes) { [bool]$NoWin7Drivers } else { (Read-Host '  Remove these too? Y/N') -match '^[yY]' }
    if ($take) { & $addSlim $slim2 'video driver pack for Windows 7/8 only' }
}

$free = ($plan | Where-Object { $_.Op -in 'bin', 'empty-recycle' } | Measure-Object Bytes -Sum).Sum
Say ''
if (-not $plan.Count) { Say '  Nothing to clean - no duplicates or leftovers found.' Green; exit 0 }
Say '  Will clean:' White
foreach ($p in $plan) {
    $verb = switch ($p.Op) { 'bin' { 'remove ' } 'empty-recycle' { 'empty  ' } 'adopt' { 'keep   ' } 'replace' { 'repair ' } }
    Say ("   {0} {1,9}  {2}" -f $verb, (Fmt $p.Bytes), $p.Path.Substring($Root.Length)) $(if ($p.Op -in 'adopt', 'replace') { 'Green' } else { 'Yellow' })
    Say ("                       {0}" -f $p.Why) DarkGray
}
Say ''
Say ("  Space that can be freed: {0}" -f (Fmt $free)) Cyan
if ($ReportOnly) { Say '  (report only - nothing changed)' DarkGray; exit 0 }

if (-not $Yes) {
    $a = Read-Host "  Move these to $Bin ? Y/N"
    if ($a -notmatch '^[yY]') { Say '  Nothing changed.' DarkGray; exit 0 }
}

# ------------------------------------------------------------------ do it (moves only - same drive, instant)
function Move-ToBin([string]$p) {
    $dest = Join-Path $Bin $p.Substring($Root.Length)
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    $i = 1; $d0 = $dest; while (Test-Path -LiteralPath $dest) { $dest = "$d0.$i"; $i++ }
    Move-Item -LiteralPath $p -Destination $dest
}
$done = 0
foreach ($p in ($plan | Where-Object { $_.Op -in 'adopt', 'replace' })) {
    try {
        if ($p.Op -eq 'replace') { Move-ToBin $p.Dest }
        New-Item -ItemType Directory -Path (Split-Path $p.Dest) -Force | Out-Null
        Move-Item -LiteralPath $p.Path -Destination $p.Dest
        $done++
    } catch { Say "   could not move $($p.Path): $($_.Exception.Message)" Red }
}
foreach ($p in ($plan | Where-Object { $_.Op -eq 'bin' })) {
    try { if (Test-Path -LiteralPath $p.Path) { Move-ToBin $p.Path; $done++ } } catch { Say "   could not move $($p.Path): $($_.Exception.Message)" Red }
}
foreach ($p in ($plan | Where-Object { $_.Op -eq 'empty-recycle' })) {
    Get-ChildItem -LiteralPath $p.Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $done++
}
Say ("  Done: {0} item(s) cleaned." -f $done) Green
if ($sjOk) { try { [void](Update-SJManifest -Root $Root) } catch { } }

if (Test-Path -LiteralPath $Bin) {
    $binBytes = Get-DirBytes $Bin
    Say ("  {0} is now in {1}" -f (Fmt $binBytes), $Bin) White
    if ($Yes) { Say '  Check the USB still works, then delete that folder.' DarkGray; exit 0 }
    $a = Read-Host '  Delete it permanently now to free the space? Y = delete now, N = keep it to check first'
    if ($a -match '^[yY]') {
        Remove-Item -LiteralPath $Bin -Recurse -Force
        Say ("  Freed {0}." -f (Fmt $binBytes)) Green
    } else {
        Say "  Kept. After checking the USB, delete $Bin (or run CLEAN again)." DarkGray
    }
}
