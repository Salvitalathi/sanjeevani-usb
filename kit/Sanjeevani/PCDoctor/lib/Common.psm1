# Sanjeevani PC Doctor - common helpers (Windows PowerShell 5.1 compatible)
Set-StrictMode -Off

function Initialize-PDContext {
    param([Parameter(Mandatory)][string]$UsbRoot)
    $reportDir = Join-Path $UsbRoot ("Reports\" + $env:COMPUTERNAME)
    try {
        New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
        $probe = Join-Path $reportDir '.write-test'
        Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force
    } catch {
        # USB read-only / full: keep reports on the PC instead
        $reportDir = Join-Path $env:PUBLIC ("Documents\Sanjeevani\" + $env:COMPUTERNAME)
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    New-Item -ItemType Directory -Path (Join-Path $reportDir 'backup') -Force | Out-Null
    $ctx = [hashtable]::Synchronized(@{
        UsbRoot   = $UsbRoot
        KitRoot   = Join-Path $UsbRoot 'Sanjeevani'
        ReportDir = $reportDir
        BackupDir = Join-Path $reportDir 'backup'
        LogFile   = Join-Path $reportDir ("log-{0:yyyyMMdd}.txt" -f (Get-Date))
        UndoFile  = Join-Path $reportDir 'undo.json'
    })
    $global:PDCtx = $ctx
    return $ctx
}

function Write-PDLog {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')][string]$Level = 'INFO')
    $line = '[{0:HH:mm:ss}] {1,-4} {2}' -f (Get-Date), $Level, $Message
    if ($global:PDLogQueue) { $global:PDLogQueue.Enqueue($line) }
    if ($global:PDCtx -and $global:PDCtx.LogFile) {
        try { Add-Content -LiteralPath $global:PDCtx.LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

function Set-PDProgress {
    param([int]$Percent, [string]$Status)
    if ($global:PDState) {
        $global:PDState.Progress = $Percent
        if ($Status) { $global:PDState.Status = $Status }
    }
}

function Test-PDAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-PDSize {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return ('{0:N0} B' -f $Bytes)
}

function Get-PDFolderSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = 0
    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { $sum += $_.Length }
    } catch { }
    return [double]$sum
}

# Runs a console program, streams its output into the log and turns
# "45%" style progress (DISM/SFC/chkdsk) into the progress bar.
function Invoke-PDProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments = '',
        [switch]$Unicode,
        [string]$ProgressLabel
    )
    Write-PDLog ("> {0} {1}" -f $FilePath, $Arguments) 'STEP'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($Unicode) {
        $psi.StandardOutputEncoding = [Text.Encoding]::Unicode
    } else {
        $oem = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        $psi.StandardOutputEncoding = [Text.Encoding]::GetEncoding($oem)
    }
    try { $p = [Diagnostics.Process]::Start($psi) } catch {
        Write-PDLog ("Start failed: " + $_.Exception.Message) 'ERR'; return -1
    }
    $errTask = $p.StandardError.ReadToEndAsync()
    $reader = $p.StandardOutput
    $sb = New-Object System.Text.StringBuilder
    $lastPct = -1
    $buf = New-Object char[] 1
    $started = Get-Date
    $lastBeat = Get-Date
    $pending = $reader.ReadAsync($buf, 0, 1)
    while ($true) {
        # heartbeat: DISM can sit on one percentage (e.g. 62-63%) for a long time while it works
        if (-not $pending.Wait(5000)) {
            if (((Get-Date) - $lastBeat).TotalSeconds -ge 60) {
                $lastBeat = Get-Date
                $pctTxt = if ($lastPct -ge 0) { " ($lastPct%)" } else { '' }
                Write-PDLog ("अजून चालू आहे{0} - {1:N0} मिनिटे झाली. PC बंद करू नका." -f $pctTxt, ((Get-Date) - $started).TotalMinutes)
            }
            continue
        }
        if ($pending.Result -le 0) { break }
        $c = $buf[0]
        $pending = $reader.ReadAsync($buf, 0, 1)
        if ($c -eq "`r" -or $c -eq "`n") {
            $line = $sb.ToString().Replace([string][char]0, '').Trim()
            [void]$sb.Clear()
            if (-not $line) { continue }
            $m = [regex]::Match($line, '(\d{1,3})(?:[\.,]\d)?\s*%')
            if ($m.Success) {
                $pct = [int]$m.Groups[1].Value
                if ($pct -le 100) {
                    Set-PDProgress $pct $ProgressLabel
                    if ([math]::Floor($pct / 10) -ne [math]::Floor($lastPct / 10)) { Write-PDLog $line }
                    $lastPct = $pct
                    continue
                }
            }
            Write-PDLog $line
        } else {
            [void]$sb.Append($c)
        }
    }
    $rest = $sb.ToString().Replace([string][char]0, '').Trim()
    if ($rest) { Write-PDLog $rest }
    $p.WaitForExit()
    $err = $errTask.Result
    if ($err -and $err.Trim()) { Write-PDLog $err.Trim() 'WARN' }
    Set-PDProgress -1
    Write-PDLog ("Exit code: {0}" -f $p.ExitCode)
    return $p.ExitCode
}

function New-PDRestorePoint {
    param([string]$Description = 'Sanjeevani PC Doctor')
    Write-PDLog 'System Restore point तयार करत आहे...' 'STEP'
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = $null
    try {
        $old = (Get-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-PDLog 'Restore point तयार झाला.' 'OK'
        return $true
    } catch {
        Write-PDLog ('Restore point तयार झाला नाही: ' + $_.Exception.Message) 'WARN'
        return $false
    } finally {
        if ($null -eq $old) {
            Remove-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction SilentlyContinue
        }
    }
}

# ---- undo journal -------------------------------------------------------
function Get-PDUndo {
    if ($global:PDCtx -and (Test-Path -LiteralPath $global:PDCtx.UndoFile)) {
        try {
            $o = Get-Content -LiteralPath $global:PDCtx.UndoFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $items = @(); foreach ($x in $o) { $items += $x }   # unroll: PS 5.1 emits a JSON array as one object
            return $items     # emitted one by one; callers wrap with @()
        } catch { }
    }
}

function Add-PDUndo {
    param([Parameter(Mandatory)][hashtable]$Entry)
    $Entry.Time = (Get-Date).ToString('s')
    $list = @(Get-PDUndo) + @([pscustomobject]$Entry)
    ConvertTo-Json -InputObject @($list) -Depth 6 | Set-Content -LiteralPath $global:PDCtx.UndoFile -Encoding UTF8
}

# Sets a registry value and journals the exact previous state (value + type, or "did not exist")
function Set-PDRegValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $key = Get-Item -Path $Path
    if ($key.GetValueNames() -contains $Name) {
        $old = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
        $kind = $key.GetValueKind($Name).ToString()
        if ($old -is [byte[]]) { $old = [Convert]::ToBase64String($old) }
        Add-PDUndo @{ Type = 'RegValue'; Path = $Path; Name = $Name; Existed = $true; Old = $old; Kind = $kind }
    } else {
        Add-PDUndo @{ Type = 'RegValue'; Path = $Path; Name = $Name; Existed = $false }
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

function Save-PDRegBackup {
    param([Parameter(Mandatory)][string]$RegPath, [Parameter(Mandatory)][string]$Name)
    $file = Join-Path $global:PDCtx.BackupDir ("{0}-{1:yyyyMMdd-HHmmss}.reg" -f $Name, (Get-Date))
    $null = & reg.exe export $RegPath $file /y 2>&1
    if (Test-Path -LiteralPath $file) { return $file }
    return $null
}

# Registry backup that does not need reg.exe (reg.exe refuses to run when a virus set DisableRegistryTools).
function ConvertTo-PDRegTree([string]$Key, [int]$Depth = 0) {
    $k = Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $k) { return [pscustomobject]@{ Key = $Key; Exists = $false } }
    $vals = @(foreach ($n in $k.GetValueNames()) {
            $kind = $k.GetValueKind($n).ToString()
            $d = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
            if ($d -is [byte[]]) { $d = [Convert]::ToBase64String($d) }
            [pscustomobject]@{ Name = $n; Kind = $kind; Data = $d }
        })
    $subs = @()
    if ($Depth -lt 8) { $subs = @(foreach ($c in @(Get-ChildItem -LiteralPath $Key -ErrorAction SilentlyContinue)) { ConvertTo-PDRegTree ($Key.TrimEnd('\') + '\' + $c.PSChildName) ($Depth + 1) }) }
    [pscustomobject]@{ Key = $Key; Exists = $true; Values = $vals; Subkeys = $subs }
}

function Save-PDRegTree {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Name)
    $file = Join-Path $global:PDCtx.BackupDir ("{0}-{1:yyyyMMdd-HHmmss-fff}.regtree.json" -f $Name, (Get-Date))
    ConvertTo-Json -InputObject (ConvertTo-PDRegTree $Key) -Depth 30 | Set-Content -LiteralPath $file -Encoding UTF8
    return $file
}

function Restore-PDRegTree {
    param([Parameter(Mandatory)]$Tree)
    if ($Tree -is [string]) { $Tree = Get-Content -LiteralPath $Tree -Raw -Encoding UTF8 | ConvertFrom-Json }
    if (-not $Tree.Exists) { return }
    if (-not (Test-Path -LiteralPath $Tree.Key)) { New-Item -Path $Tree.Key -Force | Out-Null }
    foreach ($v in @($Tree.Values)) {
        if ($null -eq $v) { continue }
        $data = $v.Data
        switch ($v.Kind) {
            'Binary'      { $data = [Convert]::FromBase64String([string]$v.Data) }
            'MultiString' { $data = [string[]]@($v.Data) }
            'DWord'       { $data = [int64]$v.Data; if ($data -gt [int]::MaxValue) { $data = [int]($data - 4294967296) } }
            'QWord'       { $data = [int64]$v.Data }
        }
        $nm = if ($v.Name) { $v.Name } else { '(default)' }
        $kind = if ($v.Kind -in 'String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString') { $v.Kind } else { 'String' }
        Set-ItemProperty -LiteralPath $Tree.Key -Name $nm -Value $data -Type $kind -ErrorAction Stop
    }
    foreach ($c in @($Tree.Subkeys)) { if ($c) { Restore-PDRegTree $c } }
}

Export-ModuleMember -Function *
