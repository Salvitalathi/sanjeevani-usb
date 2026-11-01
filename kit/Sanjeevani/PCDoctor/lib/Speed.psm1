# Sanjeevani PC Doctor - speed-up / lightweight-OS actions.
# Every change is journaled in undo.json so "Undo" can restore it.
Set-StrictMode -Off

# ---------------- cleanup ----------------
$script:CleanHandlers = @(
    'Temporary Files', 'Update Cleanup', 'Windows Error Reporting Files', 'Delivery Optimization Files',
    'Previous Installations', 'Temporary Setup Files', 'Thumbnail Cache', 'Old ChkDsk Files', 'Setup Log Files',
    'System error memory dump files', 'System error minidump files', 'Downloaded Program Files',
    'Internet Cache Files', 'Windows Upgrade Log Files', 'D3D Shader Cache', 'Device Driver Packages',
    'Windows Defender', 'Language Pack', 'Temporary Sync Files', 'Diagnostic Data Viewer database files'
)

function Clear-PDJunk {
    param([switch]$RecycleBin, [switch]$ComponentStore)
    $drive = $env:SystemDrive.TrimEnd(':')
    $before = (Get-Volume -DriveLetter $drive).SizeRemaining
    Write-PDLog 'Temp files साफ करत आहे...' 'STEP'
    Set-PDProgress 10 'Temp files'
    foreach ($p in @($env:TEMP, "$env:WINDIR\Temp")) {
        Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { }
        }
    }
    try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { }

    $cleanmgr = "$env:WINDIR\System32\cleanmgr.exe"
    if (Test-Path $cleanmgr) {
        Write-PDLog 'Windows Disk Cleanup चालवत आहे (जुने updates, error reports, Windows.old)...' 'STEP'
        Set-PDProgress 30 'Disk Cleanup'
        $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        foreach ($h in $script:CleanHandlers) {
            if (Test-Path "$base\$h") { Set-ItemProperty -Path "$base\$h" -Name StateFlags0777 -Value 2 -Type DWord -ErrorAction SilentlyContinue }
        }
        $p = Start-Process -FilePath $cleanmgr -ArgumentList '/sagerun:777' -PassThru -WindowStyle Hidden
        # cleanmgr can hang on some PCs; cap at 45 minutes
        if (-not $p.WaitForExit(45 * 60 * 1000)) { try { $p.Kill() } catch { } ; Write-PDLog 'Disk Cleanup वेळेत संपला नाही, थांबवला.' 'WARN' }
        foreach ($h in $script:CleanHandlers) { Remove-ItemProperty -Path "$base\$h" -Name StateFlags0777 -ErrorAction SilentlyContinue }
    }
    if ($ComponentStore) {
        Set-PDProgress 60 'Component cleanup'
        [void](Invoke-PDProcess -FilePath "$env:WINDIR\System32\Dism.exe" -Arguments '/Online /Cleanup-Image /StartComponentCleanup' -ProgressLabel 'Old updates cleanup')
    }
    if ($RecycleBin) {
        Write-PDLog 'Recycle Bin रिकामा करत आहे...' 'STEP'
        try { Clear-RecycleBin -Force -ErrorAction Stop } catch { }
    }
    $after = (Get-Volume -DriveLetter $drive).SizeRemaining
    $freed = [math]::Max(0, $after - $before)
    Set-PDProgress -1
    Write-PDLog ("Cleanup पूर्ण - {0} जागा मोकळी झाली. आता {1} free." -f (Format-PDSize $freed), (Format-PDSize $after)) 'OK'
    return $freed
}

# ---------------- startup ----------------
function Set-PDStartupState {
    param([Parameter(Mandatory)]$Item, [bool]$Enabled, [switch]$NoUndo)
    $key = $Item.ApprovedKey
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    $first = if ($Enabled) { 2 } else { 3 }
    $bytes = [byte[]]($first, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    if (-not $Enabled) { $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime()); [Array]::Copy($ft, 0, $bytes, 4, 8) }
    Set-ItemProperty -Path $key -Name $Item.ValueName -Value $bytes -Type Binary
    if (-not $NoUndo) { Add-PDUndo @{ Type = 'Startup'; ApprovedKey = $key; ValueName = $Item.ValueName; WasEnabled = [bool]$Item.Enabled } }
    Write-PDLog ("Startup: {0} -> {1}" -f $Item.Name, $(if ($Enabled) { 'चालू' } else { 'बंद' })) 'OK'
}

function Get-PDSafeStartupToDisable {
    param([object[]]$Items, [string]$DataDir, [double]$RamGB = 8)
    $rules = Get-Content (Join-Path $DataDir 'startup-rules.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $out = @()
    foreach ($it in $Items) {
        if (-not $it.Enabled) { continue }
        $text = $it.Name + ' ' + $it.Command
        $keep = $false
        foreach ($k in $rules.neverDisable) { if ($text -match $k) { $keep = $true; break } }
        if ($keep) { continue }
        foreach ($r in $rules.safeToDisable) {
            if ($text -match $r.match -and ($RamGB -le [double]$r.maxRamGB)) { $out += $it; break }
        }
    }
    return $out
}

# ---------------- visual effects ----------------
function Set-PDVisualPerformance {
    Write-PDLog 'Animations / transparency बंद करत आहे (fonts smooth राहतील)...' 'STEP'
    Set-PDRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 3
    Set-PDRegValue 'HKCU:\Control Panel\Desktop' UserPreferencesMask ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0)) 'Binary'
    Set-PDRegValue 'HKCU:\Control Panel\Desktop' FontSmoothing '2' 'String'
    Set-PDRegValue 'HKCU:\Control Panel\Desktop' MenuShowDelay '100' 'String'
    Set-PDRegValue 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '0' 'String'
    Set-PDRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 0
    Set-PDRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewShadow 0
    Set-PDRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0
    Set-PDRegValue 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek 0
    Write-PDLog 'Visual effects हलके केले. पूर्ण परिणामासाठी sign out / restart करा.' 'OK'
}

# ---------------- power ----------------
function Set-PDPowerPlan {
    param([bool]$IsLaptop)
    $current = Get-PDActivePowerPlan
    $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $target = $balanced
    if (-not $IsLaptop) {
        $list = (& powercfg.exe /list) -join "`n"
        if ($list -notmatch $high) { $null = & powercfg.exe -duplicatescheme $high $high 2>&1 }
        if (((& powercfg.exe /list) -join "`n") -match $high) { $target = $high }
    }
    if ($current.Guid -eq $target) { Write-PDLog "Power plan आधीच योग्य आहे ($($current.Name))." 'OK'; return }
    Add-PDUndo @{ Type = 'PowerPlan'; Guid = $current.Guid }
    $null = & powercfg.exe /setactive $target 2>&1
    $label = if ($target -eq $high) { 'High performance' } else { 'Balanced' }
    Write-PDLog "Power plan: $label" 'OK'
}

# ---------------- bloatware / suggestions ----------------
function Remove-PDBloat {
    param([string[]]$Packages)
    foreach ($name in $Packages) {
        Write-PDLog "Remove: $name" 'STEP'
        try {
            Get-AppxPackage -Name $name -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction Stop
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $name } |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            Add-PDUndo @{ Type = 'Appx'; Name = $name }
            Write-PDLog "$name काढले (हवे असल्यास Microsoft Store मधून परत install करता येते)." 'OK'
        } catch { Write-PDLog ("$name काढता आले नाही: " + $_.Exception.Message) 'WARN' }
    }
}

function Disable-PDSuggestions {
    Write-PDLog 'Windows tips, ads आणि auto-installed apps बंद करत आहे...' 'STEP'
    $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'PreInstalledAppsEnabled',
                   'OemPreInstalledAppsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled') {
        Set-PDRegValue $p $n 0
    }
    Write-PDLog 'Suggestions / ads बंद.' 'OK'
}

function Disable-PDBackgroundApps {
    Write-PDLog 'Store apps ना background मध्ये चालण्यापासून थांबवत आहे...' 'STEP'
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name LetAppsRunInBackground -Value 2 -Type DWord
    Add-PDUndo @{ Type = 'RegValueRemove'; Path = $p; Name = 'LetAppsRunInBackground' }
    Write-PDLog 'Background apps बंद (काही apps चे notifications उशिरा येऊ शकतात).' 'OK'
}

# ---------------- services ----------------
function Optimize-PDServices {
    param([string]$DataDir, [bool]$SystemOnHdd, [double]$RamGB)
    $rules = Get-Content (Join-Path $DataDir 'services.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($r in $rules.services) {
        if ($r.onlyIfHdd -and -not $SystemOnHdd) { continue }
        if ($r.maxRamGB -and $RamGB -gt [double]$r.maxRamGB) { continue }
        $svc = Get-Service -Name $r.name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ([string]$svc.StartType -eq $r.startType) { continue }
        Add-PDUndo @{ Type = 'Service'; Name = $r.name; StartType = [string]$svc.StartType }
        try {
            Set-Service -Name $r.name -StartupType $r.startType -ErrorAction Stop
            if ($r.startType -eq 'Disabled') { Stop-Service -Name $r.name -Force -ErrorAction SilentlyContinue }
            Write-PDLog ("Service {0} ({1}) -> {2}" -f $r.name, $r.label, $r.startType) 'OK'
        } catch { Write-PDLog ("Service {0}: {1}" -f $r.name, $_.Exception.Message) 'WARN' }
    }
}

function Set-PDPagefileAuto {
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.AutomaticManagedPagefile) { return }
    $pf = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
    if ($pf.Count -eq 0) {
        Write-PDLog 'Page file बंद होती - Windows managed केली (restart नंतर लागू).' 'STEP'
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } | Out-Null
        Add-PDUndo @{ Type = 'Note'; Text = 'Pagefile set to automatic' }
    }
}

function Disable-PDHibernation {
    Write-PDLog 'Hibernation बंद करत आहे (hiberfil.sys ची जागा मोकळी होईल)...' 'STEP'
    $null = & powercfg.exe /h off 2>&1
    Add-PDUndo @{ Type = 'Hibernate' }
    Write-PDLog 'Hibernation बंद.' 'OK'
}

# ---------------- undo ----------------
function Undo-PDChanges {
    $list = @(Get-PDUndo)
    if ($list.Count -eq 0) { Write-PDLog 'Undo करण्यासारखे काही नाही.' 'INFO'; return }
    [array]::Reverse($list)
    foreach ($u in $list) {
        try {
            switch ($u.Type) {
                'Startup'        { Set-PDStartupState -Item ([pscustomobject]@{ ApprovedKey = $u.ApprovedKey; ValueName = $u.ValueName; Name = $u.ValueName; Enabled = $false }) -Enabled ([bool]$u.WasEnabled) -NoUndo }
                'Service'        { Set-Service -Name $u.Name -StartupType $u.StartType -ErrorAction Stop; Write-PDLog "Service $($u.Name) -> $($u.StartType)" 'OK' }
                'RegFile'        { $null = & reg.exe import $u.File 2>&1; Write-PDLog "Registry restore: $($u.Label)" 'OK' }
                'PowerPlan'      { if ($u.Guid) { $null = & powercfg.exe /setactive $u.Guid 2>&1; Write-PDLog 'Power plan restore' 'OK' } }
                'Hibernate'      { $null = & powercfg.exe /h on 2>&1; Write-PDLog 'Hibernation परत चालू' 'OK' }
                'RegValue'       {
                    if ($u.Existed) {
                        $v = $u.Old
                        if ($u.Kind -eq 'Binary') { $v = [Convert]::FromBase64String([string]$u.Old) }
                        elseif ($u.Kind -eq 'MultiString') { $v = [string[]]@($u.Old) }
                        Set-ItemProperty -Path $u.Path -Name $u.Name -Value $v -Type $u.Kind
                    } else { Remove-ItemProperty -Path $u.Path -Name $u.Name -ErrorAction SilentlyContinue }
                }
                'RegValueRemove' { Remove-ItemProperty -Path $u.Path -Name $u.Name -ErrorAction SilentlyContinue; Write-PDLog "Removed $($u.Path)\$($u.Name)" 'OK' }
                'Appx'           { Write-PDLog "$($u.Name) - Microsoft Store मधून परत install करा." 'INFO' }
                default          { }
            }
        } catch { Write-PDLog ("Undo {0}: {1}" -f $u.Type, $_.Exception.Message) 'WARN' }
    }
    Move-Item -LiteralPath $global:PDCtx.UndoFile -Destination ($global:PDCtx.UndoFile -replace '\.json$', ("-undone-{0:yyyyMMddHHmm}.json" -f (Get-Date))) -Force
    Write-PDLog 'Undo पूर्ण. PC restart करा.' 'OK'
}

Export-ModuleMember -Function *
