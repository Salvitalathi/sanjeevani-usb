# Tests for the boot-time rescue tool. Runs in Windows PowerShell 5.1 AND PowerShell 7 (Hiren's PE uses PS7).
# Uses only temp folders and a COPY of the SYSTEM registry hive - nothing on the runner is changed.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot
$failed = 0
function T([string]$Name, [scriptblock]$Body) {
    try { $r = & $Body; if ($r -is [bool] -and -not $r) { throw 'returned false' }; Write-Host "PASS  $Name" -ForegroundColor Green }
    catch { $script:failed++; Write-Host "FAIL  $Name : $($_.Exception.Message)" -ForegroundColor Red; Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
}
function Assert($c, [string]$m) { if (-not $c) { throw $m } }
Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
$tmp = Join-Path $env:TEMP ('sjv-rx-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp -Force | Out-Null

T 'Rescue module and menu script parse and import' {
    foreach ($f in 'Rescue.psm1', 'PCDoctor-Rescue.ps1') {
        $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root "kit\Sanjeevani\PCDoctor\Rescue\$f"), [ref]$null, [ref]$e)
        Assert (-not $e) ("$f : " + ($e | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ')
    }
    Import-Module (Join-Path $Root 'kit\Sanjeevani\PCDoctor\Rescue\Rescue.psm1') -Force -DisableNameChecking
    Set-RXLogFile (Join-Path $tmp 'log.txt')
    $true
}

T 'Finds installed Windows (skips the running system drive)' {
    $w = @(Get-RXWindows)
    Write-Host "      found: $(($w | ForEach-Object { $_.Drive }) -join ', ')"
    Assert (-not ($w | Where-Object { $_.Drive -eq $env:SystemDrive })) 'running system drive must be skipped'
    $true
}

T 'Matches missing devices to drivers in a driver store' {
    $store = Join-Path $tmp 'store'
    New-Item -ItemType Directory (Join-Path $store 'netwifi.inf_amd64_1'), (Join-Path $store 'other.inf_amd64_2') -Force | Out-Null
    Set-Content (Join-Path $store 'netwifi.inf_amd64_1\netwifi.inf') "[Version]`r`nClass=Net`r`n[Models]`r`n%Dev% = Install, PCI\VEN_8086&DEV_51F0&SUBSYS_00948086"
    Set-Content (Join-Path $store 'other.inf_amd64_2\other.inf') "[Version]`r`nClass=Media`r`n%x% = y, PCI\VEN_10EC&DEV_0287"
    $dev = [pscustomobject]@{ Name = 'Intel Wi-Fi 6'; HardwareIds = @('PCI\VEN_8086&DEV_51F0&SUBSYS_00948086&REV_01', 'PCI\VEN_8086&DEV_51F0') }
    $hits = @(Find-RXMatchingInfs -DriverStore $store -Devices @($dev))
    Assert ($hits.Count -eq 1) "expected 1 match, got $($hits.Count)"
    Assert ($hits[0].Inf -match 'netwifi\.inf$') 'wrong inf'
    $keys = Get-RXIdKeys @('USB\VID_0BDA&PID_8771&REV_0200', 'ACPI\ELAN0001')
    Assert (($keys -contains 'VID_0BDA&PID_8771') -and ($keys -contains 'ELAN0001')) "keys: $($keys -join ',')"
    $true
}

T 'Reads blue-screen dumps list (BlueScreenView CSV) and blames the right driver' {
    $csv = @'
Dump File,Crash Time,Bug Check String,Bug Check Code,Parameter 1,Parameter 2,Parameter 3,Parameter 4,Caused By Driver,Caused By Address,File Description,Product Name,Company,File Version
110326-1.dmp,03-11-2026 10:01:02,DRIVER_IRQL_NOT_LESS_OR_EQUAL,0x000000d1,0,2,0,0,rtwlane.sys,rtwlane.sys+1a2b,Realtek WLAN Driver,Realtek Wireless,Realtek Semiconductor Corp.,2024.0.10.218
110226-1.dmp,02-11-2026 21:11:00,DRIVER_IRQL_NOT_LESS_OR_EQUAL,0x000000d1,0,2,0,0,rtwlane.sys,rtwlane.sys+1a2b,Realtek WLAN Driver,Realtek Wireless,Realtek Semiconductor Corp.,2024.0.10.218
110126-1.dmp,01-11-2026 09:00:00,MEMORY_MANAGEMENT,0x0000001a,0,0,0,0,ntoskrnl.exe,ntoskrnl.exe+3f,NT Kernel & System,Microsoft Windows,Microsoft Corporation,10.0.26200
'@
    $c = @(ConvertFrom-RXCrashCsv $csv)
    Assert ($c.Count -eq 3) "rows: $($c.Count)"
    $s = @(Get-RXCrashSummary $c)
    Assert ($s[0].Driver -eq 'rtwlane.sys' -and $s[0].Count -eq 2 -and -not $s[0].IsMicrosoft) 'top offender wrong'
    Assert (($s | Where-Object Driver -eq 'ntoskrnl.exe').IsMicrosoft) 'ntoskrnl must count as Windows'
    $true
}

T 'Disables a crashing driver in an OFFLINE registry hive and undoes it; refuses boot drivers' {
    $hive = Join-Path $tmp 'SYSTEM'
    $null = & reg.exe save HKLM\SYSTEM $hive /y 2>&1
    Assert (Test-Path $hive) 'could not save a copy of the SYSTEM hive'
    $fakeWin = [pscustomobject]@{ Drive = 'Z:'; Root = (Join-Path $tmp 'fakewin') + '\' }
    Use-RXHive -HiveFile $hive -Name 'SJV_SYS' -Script {
        param($r) $cs = Get-RXControlSet $r
        New-Item "$cs\Services\SjvTestNet" -Force | Out-Null
        New-ItemProperty "$cs\Services\SjvTestNet" -Name ImagePath -Value '\SystemRoot\System32\drivers\sjvtestnet.sys' -PropertyType ExpandString -Force | Out-Null
        New-ItemProperty "$cs\Services\SjvTestNet" -Name Start -Value 3 -PropertyType DWord -Force | Out-Null
        New-ItemProperty "$cs\Services\SjvTestNet" -Name Type -Value 1 -PropertyType DWord -Force | Out-Null
        New-Item "$cs\Services\SjvTestBoot" -Force | Out-Null
        New-ItemProperty "$cs\Services\SjvTestBoot" -Name ImagePath -Value 'System32\drivers\sjvtestboot.sys' -PropertyType ExpandString -Force | Out-Null
        New-ItemProperty "$cs\Services\SjvTestBoot" -Name Start -Value 0 -PropertyType DWord -Force | Out-Null
    } | Out-Null
    $undo = Join-Path $tmp 'undo.json'
    $null = Disable-RXDriver -Win $fakeWin -SysFile 'sjvtestnet.sys' -UndoFile $undo -HiveFile $hive
    $start = Use-RXHive -HiveFile $hive -Name 'SJV_SYS' -Script { param($r) (Get-ItemProperty "$(Get-RXControlSet $r)\Services\SjvTestNet").Start }
    Assert ($start -eq 4) "not disabled (Start=$start)"
    $boot = $null
    try { $null = Disable-RXDriver -Win $fakeWin -SysFile 'sjvtestboot.sys' -UndoFile $undo -HiveFile $hive } catch { $boot = $_.Exception.Message }
    Assert ($boot -match 'boot') 'boot-start driver must be refused'
    $n = Undo-RXDriverChanges -Win $fakeWin -UndoFile $undo -HiveFile $hive
    $start = Use-RXHive -HiveFile $hive -Name 'SJV_SYS' -Script { param($r) (Get-ItemProperty "$(Get-RXControlSet $r)\Services\SjvTestNet").Start }
    Assert ($n -eq 1 -and $start -eq 3) "undo failed (n=$n Start=$start)"
    $true
}

T 'Copies personal files to the rescue folder' {
    $src = Join-Path $tmp 'fakewin\Users\Ravi\Documents'
    New-Item -ItemType Directory $src -Force | Out-Null
    Set-Content (Join-Path $src 'report.docx') 'data'
    $w = [pscustomobject]@{ Root = (Join-Path $tmp 'fakewin') + '\'; Users = @('Ravi') }
    $items = @(Get-RXUserData $w)
    Assert ($items.Count -eq 1 -and $items[0].Folder -eq 'Documents') 'user data not found'
    $dest = Join-Path $tmp 'rescue'
    $f = Copy-RXUserData -Items $items -Dest $dest
    Assert ($f -eq 0 -and (Test-Path (Join-Path $dest 'Ravi\Documents\report.docx'))) 'copy failed'
    $true
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "rescue tests: $failed failed"
exit $failed
