# Sanjeevani PC Doctor - speed-up / lightweight-OS actions.
# Every change is journaled in undo.json so "Undo" can restore it.
Set-StrictMode -Off

# ---------------- cleanup ----------------
# Windows Disk Cleanup handlers used. Minidump files are kept on purpose: they tell which driver caused a blue screen.
$script:CleanHandlers = @(
    'Temporary Files', 'Update Cleanup', 'Windows Error Reporting Files', 'Delivery Optimization Files',
    'Previous Installations', 'Temporary Setup Files', 'Thumbnail Cache', 'Old ChkDsk Files', 'Setup Log Files',
    'System error memory dump files', 'Downloaded Program Files',
    'Internet Cache Files', 'Windows Upgrade Log Files', 'D3D Shader Cache', 'Device Driver Packages',
    'Windows Defender', 'Language Pack', 'Temporary Sync Files', 'Diagnostic Data Viewer database files'
)

function Get-PDUserDirs {
    @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin 'All Users', 'Default User', 'Public' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
}

# The junk categories PC Doctor measures (and, where marked Delete, removes itself).
function Get-PDJunkCategories {
    $users = Get-PDUserDirs
    $up = { param($rel) @($users | ForEach-Object { Join-Path $_.FullName $rel }) }
    $browser = @()
    foreach ($u in $users) {
        $l = Join-Path $u.FullName 'AppData\Local'
        foreach ($b in 'Google\Chrome\User Data', 'Microsoft\Edge\User Data', 'BraveSoftware\Brave-Browser\User Data') {
            foreach ($prof in @(Get-ChildItem -LiteralPath (Join-Path $l $b) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+)$' })) {
                foreach ($c in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { $browser += (Join-Path $prof.FullName $c) }
            }
        }
        foreach ($prof in @(Get-ChildItem -LiteralPath (Join-Path $l 'Mozilla\Firefox\Profiles') -Directory -ErrorAction SilentlyContinue)) { $browser += (Join-Path $prof.FullName 'cache2') }
    }
    @(
        [pscustomobject]@{ Id = 'usertemp'; Mr = 'Users चे temporary files'; En = 'User temporary files'; Paths = @(& $up 'AppData\Local\Temp'); Filter = $null; Delete = $true }
        [pscustomobject]@{ Id = 'wintemp'; Mr = 'Windows temporary files'; En = 'Windows temporary files'; Paths = @("$env:WINDIR\Temp"); Filter = $null; Delete = $true }
        [pscustomobject]@{ Id = 'browser'; Mr = 'Browser cache (Chrome / Edge / Brave / Firefox) - history, passwords, login राहतात'; En = 'Browser cache (Chrome / Edge / Brave / Firefox) - history, passwords and logins stay'; Paths = $browser; Filter = $null; Delete = $true }
        [pscustomobject]@{ Id = 'wer'; Mr = 'Error reports (crash reports)'; En = 'Error reports'; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue") + @(& $up 'AppData\Local\Microsoft\Windows\WER'); Filter = $null; Delete = $true }
        [pscustomobject]@{ Id = 'thumbs'; Mr = 'Photo thumbnails cache'; En = 'Thumbnail cache'; Paths = @(& $up 'AppData\Local\Microsoft\Windows\Explorer'); Filter = 'thumbcache_*.db'; Delete = $false }
        [pscustomobject]@{ Id = 'do'; Mr = 'Windows Update sharing cache (Delivery Optimization)'; En = 'Delivery Optimization cache'; Paths = @("$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache", "$env:WINDIR\SoftwareDistribution\DeliveryOptimization"); Filter = $null; Delete = $false }
        [pscustomobject]@{ Id = 'winold'; Mr = 'जुने Windows (Windows.old)'; En = 'Previous Windows (Windows.old)'; Paths = @("$env:SystemDrive\Windows.old"); Filter = $null; Delete = $false }
        [pscustomobject]@{ Id = 'dump'; Mr = 'Memory dump (MEMORY.DMP)'; En = 'Memory dump (MEMORY.DMP)'; Paths = @("$env:WINDIR\MEMORY.DMP"); Filter = $null; Delete = $false }
    )
}

function Get-PDPathBytes([string[]]$Paths, [string]$Filter) {
    $t = 0.0
    foreach ($p in $Paths) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it.PSIsContainer) { $t += $it.Length; continue }
        $files = if ($Filter) { Get-ChildItem -LiteralPath $p -Filter $Filter -File -Force -ErrorAction SilentlyContinue } else { Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue }
        $t += [double]($files | Measure-Object Length -Sum).Sum
    }
    return $t
}

function Get-PDRecycleBinBytes {
    return (Get-PDPathBytes @("$env:SystemDrive\`$Recycle.Bin") $null)
}

# Cleans junk and reports, per category, how much there was and how much was freed.
function Clear-PDJunk {
    param([switch]$RecycleBin, [switch]$ComponentStore)
    $drive = $env:SystemDrive.TrimEnd(':')
    $before = [double](Get-Volume -DriveLetter $drive).SizeRemaining
    Write-PDLog 'Junk किती आहे ते मोजत आहे...' 'STEP'
    Set-PDProgress 5 'Measuring junk'
    $cats = Get-PDJunkCategories
    foreach ($c in $cats) { $c | Add-Member -NotePropertyName Before -NotePropertyValue (Get-PDPathBytes $c.Paths $c.Filter) -Force }
    $rbBefore = Get-PDRecycleBinBytes
    Write-PDLog ("सापडलेले junk: " + (($cats | Where-Object { $_.Before -gt 0 } | ForEach-Object { "$($_.En) $(Format-PDSize $_.Before)" }) -join ', ')) 'INFO'

    Write-PDLog 'Temp files आणि browser cache साफ करत आहे...' 'STEP'
    Set-PDProgress 15 'Temp files'
    foreach ($c in ($cats | Where-Object { $_.Delete })) {
        foreach ($p in $c.Paths) {
            if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { }   # files in use stay
            }
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
    Set-PDProgress 90 'Measuring'
    $after = [double](Get-Volume -DriveLetter $drive).SizeRemaining
    $freed = [math]::Max([double]0, $after - $before)
    $items = @()
    $sumCat = 0.0
    foreach ($c in $cats) {
        $now = Get-PDPathBytes $c.Paths $c.Filter
        $gone = [math]::Max([double]0, $c.Before - $now)
        $sumCat += $gone
        if ($c.Before -gt 0) { $items += [pscustomobject]@{ Id = $c.Id; Mr = $c.Mr; En = $c.En; Found = $c.Before; Freed = $gone; Left = $now } }
    }
    $rbAfter = Get-PDRecycleBinBytes
    if ($RecycleBin -and $rbBefore -gt 0) { $g = [math]::Max([double]0, $rbBefore - $rbAfter); $sumCat += $g; $items += [pscustomobject]@{ Id = 'recycle'; Mr = 'Recycle Bin'; En = 'Recycle Bin'; Found = $rbBefore; Freed = $g; Left = $rbAfter } }
    $other = [math]::Max([double]0, $freed - $sumCat)
    if ($other -ge 1MB) { $items += [pscustomobject]@{ Id = 'other'; Mr = 'Windows Disk Cleanup: जुने updates (WinSxS), setup files व इतर'; En = 'Windows Disk Cleanup: superseded updates (WinSxS), setup files and more'; Found = $other; Freed = $other; Left = 0 } }
    Set-PDProgress -1
    Write-PDLog ("Cleanup पूर्ण - {0} जागा मोकळी झाली. आता {1} free." -f (Format-PDSize $freed), (Format-PDSize $after)) 'OK'
    foreach ($i in $items) { Write-PDLog ("   {0}: {1} सापडले, {2} साफ{3}" -f $i.Mr, (Format-PDSize $i.Found), (Format-PDSize $i.Freed), $(if ($i.Left -ge 1MB) { " (वापरात असल्याने $(Format-PDSize $i.Left) राहिले)" } else { '' })) 'INFO' }
    return [pscustomobject]@{ Freed = $freed; FreeAfter = $after; Items = $items; RecycleBinBytes = $rbAfter }
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
