# Sanjeevani PC Doctor - automatic troubleshooter.
# For each likely problem (in the order the AI / matcher ranked them): CHECK whether it really exists on this PC ->
# only if it does, FIX it with PC Doctor's own safe actions -> CHECK again to confirm. A problem that is not there is
# reported as "checked, not found" and the next candidate is checked. The answer is always the truth: when nothing
# matching is found the user is told so - nothing is "fixed" that was not broken.
# Results are in English / मराठी / हिन्दी. One restore point is created before the first change. No user files are deleted.
Set-StrictMode -Off

# ------------------------------------------------------------------ results
function TT([string]$En, [string]$Mr, [string]$Hi) { [pscustomobject]@{ en = $En; mr = $(if ($Mr) { $Mr } else { $En }); hi = $(if ($Hi) { $Hi } else { $En }) } }
function Join-TT([object[]]$Items, [string]$Sep = '; ') {
    $Items = @($Items | Where-Object { $_ })
    if (-not $Items.Count) { return $null }
    TT (($Items | ForEach-Object { $_.en }) -join $Sep) (($Items | ForEach-Object { $_.mr }) -join $Sep) (($Items | ForEach-Object { $_.hi }) -join $Sep)
}
function Add-TT($A, $B, [string]$Sep = ' ') { if (-not $A) { return $B }; if (-not $B) { return $A }; TT ($A.en + $Sep + $B.en) ($A.mr + $Sep + $B.mr) ($A.hi + $Sep + $B.hi) }
function From-QuickFix($R) { TT $R.En $R.Mr $R.Hi }
function New-TSCheck($Found, $Text, $Data = $null) { [pscustomobject]@{ Found = $Found; Text = $Text; Data = $Data } }
function New-TSFix([object]$Fixed, $Text, [switch]$Restart, $Manual = $null) { [pscustomobject]@{ Fixed = $Fixed; Text = $Text; Restart = [bool]$Restart; Manual = $Manual } }

function Get-TSDataDir { return (Join-Path $global:PDCtx.KitRoot 'PCDoctor\data') }
# progress line (status bar) + an event the voice assistant can speak
function Step([string]$En, [string]$Mr, [string]$Hi) {
    Write-PDLog $En 'STEP'
    Set-PDProgress -1 (L $En $Mr $Hi)
}
function Send-TSEvent([string]$Kind, $Problem) {
    if ($global:PDState -and $global:PDState.Events) { $global:PDState.Events.Enqueue([pscustomobject]@{ Kind = $Kind; Problem = $Problem }) }
}
$script:RpDone = $false
function New-TSRestorePointOnce {
    if (-not $script:RpDone) {
        $script:RpDone = $true
        Send-TSEvent 'restorepoint' $null
        [void](New-PDRestorePoint 'Sanjeevani: auto troubleshoot')
    }
}

# ------------------------------------------------------------------ shared probes
function Test-TSWeb {
    for ($k = 0; $k -lt 2; $k++) {
        try { $w = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8; if ($w.Content -match 'Microsoft Connect Test') { return $true } } catch { }
        Start-Sleep 2
    }
    return $false
}
function Get-TSProblemDevices([string[]]$Classes) {
    @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 45 -and (-not $Classes -or $_.PNPClass -in $Classes)
        })
}
function Get-TSDeviceName($d) { if ($d.Name) { $d.Name } elseif ($d.Description) { $d.Description } else { $d.PNPDeviceID } }
function Repair-TSDevices($Devices) {
    $did = @()
    foreach ($d in $Devices) {
        try {
            if ($d.ConfigManagerErrorCode -eq 22) { Enable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop; $did += (Get-TSDeviceName $d) }
            else { $null = & pnputil.exe /restart-device "$($d.PNPDeviceID)" 2>&1; $did += (Get-TSDeviceName $d) }
        } catch { }
    }
    $null = & pnputil.exe /scan-devices 2>&1      # lets Windows pick a driver from its own driver store
    Start-Sleep 4
    return $did
}
function Get-TSWirelessAdapters { @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match '(?i)wi-?fi|wireless|wlan|802\.11' -and $_.InterfaceDescription -notmatch '(?i)virtual|direct|miniport' }) }
function Get-TSEventCount([string]$Log, [int[]]$Ids, [string]$Provider, [int]$Days) {
    $f = @{ LogName = $Log; Id = $Ids; StartTime = (Get-Date).AddDays(-$Days) }
    if ($Provider) { $f.ProviderName = $Provider }
    try { return @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop).Count } catch { return 0 }
}
function Get-TSManual($Problem) {
    if (-not $Problem) { return $null }
    TT (($Problem.en.steps | Select-Object -First 2) -join ' ') (($Problem.mr.steps | Select-Object -First 2) -join ' ') (($Problem.hi.steps | Select-Object -First 2) -join ' ')
}
function Test-TSIsLaptop { return [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) }

# antivirus products registered with Windows Security Center (third-party ones turn Defender off on purpose)
function Get-TSAntivirus {
    $list = @()
    foreach ($p in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)) {
        $st = [int]$p.productState
        $list += [pscustomobject]@{
            Name = $p.displayName
            Microsoft = ($p.displayName -match '(?i)windows defender|microsoft defender')
            Enabled = ((($st -shr 12) -band 0xF) -in 1, 3)
            UpToDate = ((($st -shr 4) -band 0xF) -eq 0)
        }
    }
    return $list
}
function Get-TSActiveThreats { $t = @(); try { $t = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.ThreatStatusID -notin 2, 3, 4, 6 }) } catch { }; return $t }

# programs that start by themselves the way malware does: scripts (vbs / js / hta), encoded / hidden PowerShell,
# or programs run from Temp. Ordinary apps in Program Files / AppData are not listed.
$script:SuspectCmd = '(?i)(wscript|cscript|mshta)(\.exe)?\s|\.(vbs|vbe|js|jse|hta|wsf)\b|powershell(\.exe)?\s.*(-enc\b|-e\s+[A-Za-z0-9+/=]{20}|-w(indowstyle)?\s+h(idden)?|downloadstring|iex\b|frombase64)|\\(appdata\\local\\)?temp\\[^\\]+\.(exe|bat|cmd|scr|pif|com)|\\users\\public\\[^\\]+\.(exe|bat|cmd|scr)|rundll32(\.exe)?\s+[^,]*\\(temp|appdata\\roaming|users\\public)\\'
function Get-TSSuspiciousAutostarts {
    $out = @()
    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    foreach ($k in $keys) {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($v in $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            if ([string]$v.Value -match $script:SuspectCmd) { $out += [pscustomobject]@{ Kind = 'run'; Key = $k; Name = $v.Name; Command = [string]$v.Value } }
        }
    }
    foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue) {
            $target = $f.FullName
            if ($f.Extension -eq '.lnk') { try { $sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($f.FullName); $target = "$($l.TargetPath) $($l.Arguments)" } catch { } }
            if ($f.Extension -match '^\.(vbs|vbe|js|jse|hta|wsf|bat|cmd)$' -or $target -match $script:SuspectCmd) { $out += [pscustomobject]@{ Kind = 'startup'; Key = $f.FullName; Name = $f.Name; Command = $target } }
        }
    }
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($a in @($t.Actions)) {
            $cmd = "$($a.Execute) $($a.Arguments)"
            if ($cmd -match $script:SuspectCmd) { $out += [pscustomobject]@{ Kind = 'task'; Key = "$($t.TaskPath)$($t.TaskName)"; Name = $t.TaskName; Command = $cmd }; break }
        }
    }
    return $out
}
# turns the suspicious autostarts off - reversible: registry values are backed up for Undo, tasks are only disabled,
# startup-folder files are moved to the report folder (not deleted)
function Disable-TSAutostarts($Items) {
    $n = 0
    $quar = Join-Path $global:PDCtx.ReportDir 'Quarantine'
    foreach ($i in $Items) {
        try {
            switch ($i.Kind) {
                'run' {
                    $bak = Save-PDRegTree -Key $i.Key -Name ('run-' + ($i.Name -replace '[^\w-]', '_'))
                    Add-PDUndo @{ Type = 'RegTree'; File = $bak; Label = "Autostart $($i.Name)" }
                    Remove-ItemProperty -Path $i.Key -Name $i.Name -ErrorAction Stop
                }
                'task' { $tp = Split-Path $i.Key -Parent; Disable-ScheduledTask -TaskPath ($tp.TrimEnd('\') + '\') -TaskName $i.Name -ErrorAction Stop | Out-Null }
                'startup' { New-Item -ItemType Directory -Path $quar -Force | Out-Null; Move-Item -LiteralPath $i.Key -Destination (Join-Path $quar ($i.Name + '.quarantine')) -Force -ErrorAction Stop }
            }
            Write-PDLog "Autostart turned off: $($i.Name) ($($i.Command))" 'OK'
            $n++
        } catch { Write-PDLog "Autostart $($i.Name) could not be turned off: $($_.Exception.Message)" 'WARN' }
    }
    return $n
}

# ------------------------------------------------------------------ doctors
# Each doctor: Check (Found = $true / $false / $null = cannot tell), Fix, optional Verify, Probe (a deeper check run
# when Check cannot tell, e.g. a virus scan), Refresh (a harmless restart of a service that may help even when nothing
# was found - reported honestly as "nothing found, refreshed as a precaution"), NoVerify (fix needs a restart).
$script:D = @{}

$script:D['no-internet'] = @{
    Check = {
        Step 'Checking the internet connection' 'Internet connection तपासत आहे' 'Internet connection जाँच रहे हैं'
        if (Test-TSWeb) { return (New-TSCheck $false (TT 'The internet works on this PC.' 'या PC वर internet चालू आहे.' 'इस PC पर internet चल रहा है।')) }
        $up = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
        if (-not $up.Count) { return (New-TSCheck $true (TT 'No network is connected (WiFi / cable).' 'कोणतेही network जोडलेले नाही (WiFi / cable).' 'कोई network जुड़ा नहीं है (WiFi / cable).') @{ NoLink = $true }) }
        return (New-TSCheck $true (TT 'A network is connected but the internet does not open.' 'Network जोडलेले आहे पण internet उघडत नाही.' 'Network जुड़ा है पर internet नहीं खुल रहा।'))
    }
    Fix = {
        param($chk)
        Step 'Clearing DNS and proxy settings' 'DNS आणि proxy साफ करत आहे' 'DNS और proxy साफ़ कर रहे हैं'
        $null = & ipconfig.exe /flushdns 2>&1
        $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if ((Get-ItemProperty $is -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable -eq 1 -and -not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
            New-TSRestorePointOnce
            $bak = Save-PDRegTree -Key $is -Name 'proxy'; Add-PDUndo @{ Type = 'RegTree'; File = $bak; Label = 'Proxy' }
            Set-ItemProperty $is -Name ProxyEnable -Value 0
        }
        if (Test-TSWeb) { return (New-TSFix $true (TT 'I cleared the DNS cache and the proxy setting; the internet opens now.' 'DNS cache आणि proxy setting साफ केली; आता internet उघडते.' 'DNS cache और proxy setting साफ़ की; अब internet खुलता है।')) }
        Step 'Restarting the network adapters' 'Network adapters पुन्हा सुरू करत आहे' 'Network adapters फिर से शुरू कर रहे हैं'
        Set-Service WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service WlanSvc -ErrorAction SilentlyContinue
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
            if ($a.Status -eq 'Disabled') { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
            elseif ($a.Status -eq 'Up') { Restart-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
        }
        $null = & ipconfig.exe /renew 2>&1
        Start-Sleep 8
        if (Test-TSWeb) { return (New-TSFix $true (TT 'I restarted the network adapters and took a new IP address; the internet works now.' 'Network adapters पुन्हा सुरू करून नवीन IP घेतला; आता internet चालते.' 'Network adapters फिर शुरू करके नया IP लिया; अब internet चलता है।')) }
        if ($chk.Data -and $chk.Data.NoLink) {
            return (New-TSFix $false (TT 'There is still no network connection.' 'अजूनही network connection नाही.' 'अभी भी network connection नहीं है।') -Manual (TT 'Connect to WiFi or plug in the cable. If the WiFi option is missing, the WiFi driver is missing (Repair, Drivers).' 'WiFi ला connect करा किंवा cable लावा. WiFi चा पर्यायच नसेल तर WiFi driver नाही (दुरुस्ती, Drivers).' 'WiFi से connect करें या cable लगाएँ। WiFi का विकल्प ही न हो तो WiFi driver नहीं है (मरम्मत, Drivers)।'))
        }
        Step 'Resetting the network settings (Winsock / TCP-IP)' 'Network settings reset करत आहे (Winsock / TCP-IP)' 'Network settings reset कर रहे हैं (Winsock / TCP-IP)'
        New-TSRestorePointOnce
        Reset-PDNetwork
        return (New-TSFix $null (TT 'I reset the network settings (Winsock, TCP-IP, DNS). If it still does not work after the restart, the router or the internet company is the cause.' 'Network settings reset केल्या (Winsock, TCP-IP, DNS). Restart नंतरही न चालल्यास router किंवा internet company कारण आहे.' 'Network settings reset कीं (Winsock, TCP-IP, DNS)। Restart के बाद भी न चले तो router या internet company कारण है।') -Restart)
    }
}
$script:D['lan'] = $script:D['no-internet']
$script:D['slow-internet'] = @{
    Check = {
        Step 'Measuring the internet speed' 'Internet चा वेग मोजत आहे' 'Internet की स्पीड माप रहे हैं'
        $pingHost = '8.8.8.8'
        $t = @(Test-Connection -ComputerName $pingHost -Count 6 -ErrorAction SilentlyContinue)
        if (-not $t.Count -and (Test-TSWeb)) { return (New-TSCheck $null (TT 'The internet works; this network blocks ping, so its speed cannot be measured here.' 'Internet चालते; हे network ping अडवते, त्यामुळे वेग इथे मोजता येत नाही.' 'Internet चल रहा है; यह network ping रोकता है, इसलिए स्पीड यहाँ नहीं माप सकते।')) }
        if (-not $t.Count) { return (New-TSCheck $true (TT 'The internet does not answer at all.' 'Internet अजिबात उत्तर देत नाही.' 'Internet बिल्कुल जवाब नहीं दे रहा।') @{ Down = $true }) }
        $ms = [math]::Round(($t | Measure-Object ResponseTime -Average).Average); $lost = 6 - $t.Count
        $proxy = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable -eq 1
        if ($ms -gt 150 -or $lost -ge 1 -or $proxy) {
            $px = if ($proxy) { TT ', and a proxy is set' ', आणि proxy लावलेला आहे' ', और proxy लगा है' } else { TT '' '' '' }
            return (New-TSCheck $true (TT "The internet is slow: $ms ms, $lost of 6 packets lost$($px.en)." "Internet हळू आहे: $ms ms, 6 पैकी $lost packets हरवले$($px.mr)." "Internet धीमा है: $ms ms, 6 में से $lost packets खोए$($px.hi)।"))
        }
        return (New-TSCheck $false (TT "The internet speed is fine ($ms ms, nothing lost)." "Internet चा वेग ठीक आहे ($ms ms, काहीही हरवले नाही)." "Internet की स्पीड ठीक है ($ms ms, कुछ नहीं खोया)।"))
    }
    Fix = {
        param($chk)
        if ($chk.Data -and $chk.Data.Down) { return (& $script:D['no-internet'].Fix (New-TSCheck $true $null)) }
        $null = & ipconfig.exe /flushdns 2>&1
        $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if ((Get-ItemProperty $is -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable -eq 1 -and -not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
            New-TSRestorePointOnce; $bak = Save-PDRegTree -Key $is -Name 'proxy'; Add-PDUndo @{ Type = 'RegTree'; File = $bak; Label = 'Proxy' }
            Set-ItemProperty $is -Name ProxyEnable -Value 0
        }
        return (New-TSFix $null (TT 'I cleared the DNS cache and turned off any proxy.' 'DNS cache साफ केला आणि proxy बंद केला.' 'DNS cache साफ़ किया और proxy बंद किया।') -Manual (TT 'If it is still slow, move closer to the router or use a cable and pause big downloads. Otherwise the internet company is the cause.' 'तरीही हळू असेल तर router जवळ जा किंवा cable वापरा आणि मोठे downloads थांबवा. नाहीतर internet company चे कारण आहे.' 'फिर भी धीमा हो तो router के पास जाएँ या cable लगाएँ और बड़े downloads रोकें। वरना internet company कारण है।'))
    }
}
$script:D['wifi'] = @{
    Check = {
        Step 'Checking the WiFi adapter' 'WiFi adapter तपासत आहे' 'WiFi adapter जाँच रहे हैं'
        $w = Get-TSWirelessAdapters
        $svc = Get-Service WlanSvc -ErrorAction SilentlyContinue
        $bad = Get-TSProblemDevices @('Net') | Where-Object { $_.Name -match '(?i)wi-?fi|wireless|wlan|802\.11' -or $_.ConfigManagerErrorCode -eq 28 }
        if (-not $w.Count -and -not @($bad).Count) { return (New-TSCheck $true (TT 'No WiFi adapter was found: the WiFi driver is missing or WiFi is switched off.' 'WiFi adapter सापडला नाही: WiFi driver नाही किंवा WiFi बंद केले आहे.' 'WiFi adapter नहीं मिला: WiFi driver नहीं है या WiFi बंद है।') @{ None = $true }) }
        if (@($bad).Count -or ($w | Where-Object Status -eq 'Disabled') -or -not $svc -or $svc.Status -ne 'Running') { return (New-TSCheck $true (TT 'The WiFi adapter or the WiFi service is not working.' 'WiFi adapter किंवा WiFi service काम करत नाही.' 'WiFi adapter या WiFi service काम नहीं कर रही।') @{ Bad = $bad }) }
        if ($w | Where-Object Status -eq 'Up') { return (New-TSCheck $false (TT 'WiFi works and is connected.' 'WiFi चालू आहे आणि जोडलेले आहे.' 'WiFi चालू है और जुड़ा है।')) }
        return (New-TSCheck $true (TT 'The WiFi adapter works but is not connected to any network.' 'WiFi adapter चालतो, पण कोणत्याही network ला जोडलेला नाही.' 'WiFi adapter चलता है, पर किसी network से जुड़ा नहीं है।') @{ NotConnected = $true })
    }
    Fix = {
        param($chk)
        Step 'Starting the WiFi service and adapter' 'WiFi service आणि adapter सुरू करत आहे' 'WiFi service और adapter शुरू कर रहे हैं'
        Set-Service WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service WlanSvc -ErrorAction SilentlyContinue
        foreach ($a in (Get-TSWirelessAdapters | Where-Object Status -eq 'Disabled')) { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
        [void](Repair-TSDevices @(Get-TSProblemDevices @('Net')))
        $after = & $script:D['wifi'].Check
        if (-not $after.Found) { return (New-TSFix $true (TT 'I started the WiFi service and the WiFi adapter.' 'WiFi service आणि WiFi adapter सुरू केले.' 'WiFi service और WiFi adapter शुरू किए।')) }
        if ($after.Data -and $after.Data.NotConnected) { return (New-TSFix $true (TT 'WiFi works now. Choose your network from the WiFi icon on the taskbar.' 'WiFi आता चालू आहे. Taskbar वरच्या WiFi icon मधून तुमचे network निवडा.' 'WiFi अब चालू है। Taskbar के WiFi icon से अपना network चुनें।')) }
        return (New-TSFix $false (TT 'The WiFi adapter is still missing.' 'WiFi adapter अजूनही दिसत नाही.' 'WiFi adapter अभी भी नहीं दिख रहा।') -Manual (TT 'Check the WiFi key (Fn + F2 / F12) and Airplane mode, then install the WiFi driver: Repair, Drivers (works offline from the USB).' 'WiFi key (Fn + F2 / F12) आणि Airplane mode तपासा, मग WiFi driver install करा: दुरुस्ती, Drivers (USB वरून internet शिवाय).' 'WiFi key (Fn + F2 / F12) और Airplane mode देखें, फिर WiFi driver install करें: मरम्मत, Drivers (USB से बिना internet)।'))
    }
}

$script:D['slow-pc'] = @{
    Check = {
        Step 'Measuring what slows this PC down' 'PC कशामुळे हळू आहे ते मोजत आहे' 'PC किस वजह से धीमा है, माप रहे हैं'
        $s = Invoke-PDScan -DataDir (Get-TSDataDir)
        $safe = @(Get-PDSafeStartupToDisable -Items $s.Startup -DataDir (Get-TSDataDir) -RamGB $s.Info.RAMGB)
        $junk = [double]$s.TempBytes
        $why = @()
        if ($safe.Count) { $why += TT "$($safe.Count) unneeded startup programs" "$($safe.Count) अनावश्यक startup programs" "$($safe.Count) बेकार startup programs" }
        if ($junk -ge 1GB) { $why += TT "$(Format-PDSize $junk) of junk files" "$(Format-PDSize $junk) junk files" "$(Format-PDSize $junk) junk files" }
        if ($s.Info.SysFreePct -lt 15) { $why += TT 'C: drive almost full' 'C: drive जवळपास भरलेला' 'C: drive लगभग भरा' }
        if (@($s.Bloat | Where-Object Default).Count) { $why += TT 'pre-installed bloatware' 'pre-installed bloatware' 'pre-installed bloatware' }
        if ($s.Score -lt 80 -or $why.Count) {
            $w = Join-TT $why ', '
            return (New-TSCheck $true (Add-TT (TT "Health score $($s.Score)/100." "Health score $($s.Score)/100." "Health score $($s.Score)/100.") $w) @{ Scan = $s; Safe = $safe })
        }
        return (New-TSCheck $false (TT "Health score $($s.Score)/100; nothing slowing the PC down was found." "Health score $($s.Score)/100; PC हळू करणारे काहीही सापडले नाही." "Health score $($s.Score)/100; PC को धीमा करने वाला कुछ नहीं मिला।") @{ Scan = $s })
    }
    Fix = {
        param($chk)
        $s = $chk.Data.Scan
        New-TSRestorePointOnce
        Step 'Cleaning junk files and turning off unneeded startup programs' 'Junk files साफ करत आहे आणि अनावश्यक startup बंद करत आहे' 'Junk files साफ़ कर रहे हैं और बेकार startup बंद कर रहे हैं'
        $did = @()
        $junk = Clear-PDJunk
        $did += TT "cleaned $(Format-PDSize $junk.Freed) of junk" "$(Format-PDSize $junk.Freed) junk साफ केले" "$(Format-PDSize $junk.Freed) junk साफ़ किया"
        foreach ($it in $chk.Data.Safe) { Set-PDStartupState -Item $it -Enabled $false }
        if (@($chk.Data.Safe).Count) { $n = @($chk.Data.Safe).Count; $did += TT "turned off $n startup programs" "$n startup programs बंद केले" "$n startup programs बंद किए" }
        $sd = @($s.Info.Disks | Where-Object { $_.IsSystem })[0]
        if ($s.Info.RAMGB -lt 7.5 -or ($sd -and $sd.MediaType -eq 'HDD') -or -not $s.Info.HasDedicatedGPU) { Set-PDVisualPerformance; $did += TT 'made the visual effects lighter' 'visual effects हलके केले' 'visual effects हल्के किए' }
        Set-PDPowerPlan -IsLaptop $s.Info.IsLaptop; Disable-PDSuggestions
        Optimize-PDServices -DataDir (Get-TSDataDir) -SystemOnHdd ([bool]($sd -and $sd.MediaType -eq 'HDD')) -RamGB $s.Info.RAMGB
        $bl = @($s.Bloat | Where-Object { $_.Default } | ForEach-Object { $_.Name })
        if ($bl.Count) { Remove-PDBloat -Packages $bl; $did += TT "removed $($bl.Count) bloatware apps" "$($bl.Count) bloatware apps काढले" "$($bl.Count) bloatware apps हटाए" }
        $hw = @()
        if ($s.Info.RAMGB -lt 7.5) { $hw += TT "only $($s.Info.RAMGB) GB RAM" "फक्त $($s.Info.RAMGB) GB RAM" "सिर्फ़ $($s.Info.RAMGB) GB RAM" }
        if ($sd -and $sd.MediaType -eq 'HDD') { $hw += TT 'Windows on an old hard disk (HDD)' 'Windows जुन्या hard disk (HDD) वर' 'Windows पुरानी hard disk (HDD) पर' }
        $man = if ($hw.Count) { Add-TT (TT 'For a big difference, upgrade the hardware:' 'मोठ्या फरकासाठी hardware upgrade करा:' 'बड़े फ़र्क के लिए hardware upgrade करें:') (Add-TT (Join-TT $hw ', ') (TT '-> 8 GB RAM / SSD.' '-> 8 GB RAM / SSD.' '-> 8 GB RAM / SSD.')) } else { $null }
        return (New-TSFix $true (Add-TT (Join-TT $did ', ') (TT '. Restart the PC for the full effect.' '. पूर्ण फरकासाठी PC restart करा.' '. पूरे असर के लिए PC restart करें।') '') -Restart -Manual $man)
    }
    NoVerify = $true
}
$script:D['slow-boot'] = $script:D['slow-pc']
$script:D['disk-100'] = $script:D['slow-pc']

$script:D['disk-full'] = @{
    Check = {
        Step 'Checking the free space on C:' 'C: वरची मोकळी जागा तपासत आहे' 'C: पर खाली जगह जाँच रहे हैं'
        $v = Get-Volume -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction SilentlyContinue
        $pct = if ($v.Size) { 100 * $v.SizeRemaining / $v.Size } else { 100 }
        $free = Format-PDSize $v.SizeRemaining; $size = Format-PDSize $v.Size; $p = [math]::Round($pct)
        if ($pct -lt 15 -or $v.SizeRemaining -lt 15GB) { return (New-TSCheck $true (TT "The C: drive is almost full: only $free free of $size ($p%)." "C: drive जवळपास भरला आहे: $size पैकी फक्त $free मोकळे ($p%)." "C: drive लगभग भरा है: $size में से सिर्फ़ $free खाली ($p%)।")) }
        return (New-TSCheck $false (TT "The C: drive has enough space: $free free of $size ($p%)." "C: drive वर पुरेशी जागा आहे: $size पैकी $free मोकळे ($p%)." "C: drive पर पर्याप्त जगह है: $size में से $free खाली ($p%)।"))
    }
    Fix = {
        New-TSRestorePointOnce
        Step 'Cleaning junk files' 'Junk files साफ करत आहे' 'Junk files साफ़ कर रहे हैं'
        $j = Clear-PDJunk -ComponentStore
        $f = Format-PDSize $j.Freed; $a = Format-PDSize $j.FreeAfter
        $txt = TT "I cleaned $f of junk (temp files, old updates, browser cache). C: now has $a free." "$f junk साफ केले (temp files, जुने updates, browser cache). आता C: वर $a मोकळे आहे." "$f junk साफ़ किया (temp files, पुराने updates, browser cache)। अब C: पर $a खाली है।"
        $after = & $script:D['disk-full'].Check
        if (-not $after.Found) { return (New-TSFix $true $txt) }
        return (New-TSFix $false $txt -Manual (TT 'Space is still low: move Downloads, Videos and Pictures to another drive from the "Disk Space" page (safe, with Undo).' 'जागा अजून कमी आहे: "C: drive जागा" page वरून Downloads, Videos, Pictures दुसऱ्या drive वर हलवा (सुरक्षित, Undo सह).' 'जगह अभी भी कम है: "C: drive जगह" page से Downloads, Videos, Pictures दूसरे drive पर ले जाएँ (सुरक्षित, Undo के साथ)।'))
    }
}

$script:D['bsod'] = @{
    Check = {
        Step 'Looking for blue screens and sudden restarts' 'Blue screen आणि अचानक restart शोधत आहे' 'Blue screen और अचानक restart खोज रहे हैं'
        $n = Get-TSEventCount 'System' @(1001) $null 30
        $n2 = Get-TSEventCount 'System' @(41) 'Microsoft-Windows-Kernel-Power' 30
        if ($n -or $n2 -ge 2) { return (New-TSCheck $true (TT "In the last 30 days: $n blue screens and $n2 sudden restarts." "मागच्या 30 दिवसांत: $n blue screen आणि $n2 वेळा अचानक restart." "पिछले 30 दिनों में: $n blue screen और $n2 बार अचानक restart।")) }
        return (New-TSCheck $false (TT 'No blue screens or sudden restarts in the last 30 days.' 'मागच्या 30 दिवसांत blue screen किंवा अचानक restart झालेले नाहीत.' 'पिछले 30 दिनों में कोई blue screen या अचानक restart नहीं हुआ।'))
    }
    Fix = {
        Step 'Finding the cause of the crashes' 'Crash चे कारण शोधत आहे' 'Crash का कारण खोज रहे हैं'
        $r = Invoke-TGAuto -Handler 'crashes' -UsbRoot $global:PDCtx.UsbRoot -P @{ ReportDir = $global:PDCtx.ReportDir }
        $cause = ($r.LinesEn | Where-Object { $_ -match '^• ' } | Select-Object -First 2) -join '; '
        $generic = -not $cause -or $cause -match 'ntoskrnl|ntkrnlmp|hal\.'
        if ($generic) {
            Step 'Repairing the Windows system files (DISM + SFC)' 'Windows system files दुरुस्त करत आहे (DISM + SFC)' 'Windows system files ठीक कर रहे हैं (DISM + SFC)'
            New-TSRestorePointOnce
            $os = Invoke-PDRepairOS
            return (New-TSFix $null (TT "The crashes point to Windows itself or the RAM. I repaired the system files (DISM: $($os.Dism); SFC: $($os.Sfc))." "Crash चे कारण Windows किंवा RAM आहे. System files दुरुस्त केल्या (DISM: $($os.Dism); SFC: $($os.Sfc))." "Crash का कारण Windows या RAM है। System files ठीक कीं (DISM: $($os.Dism); SFC: $($os.Sfc))।") -Restart -Manual (TT 'If blue screens continue, test the RAM (MemTest86+ from the USB) and the disk.' 'Blue screen येत राहिल्यास RAM (USB वरून MemTest86+) आणि disk तपासा.' 'Blue screen आती रहे तो RAM (USB से MemTest86+) और disk जाँचें।'))
        }
        return (New-TSFix $false (TT "The cause is a driver: $cause" "कारण एक driver आहे: $cause" "कारण एक driver है: $cause") -Manual (TT 'Install a fresh driver for that device from the maker''s website (or Repair, Drivers).' 'त्या device चा नवीन driver कंपनीच्या website वरून install करा (किंवा दुरुस्ती, Drivers).' 'उस device का नया driver कंपनी की website से install करें (या मरम्मत, Drivers)।'))
    }
}
$script:D['shutdown'] = @{
    Check = {
        Step 'Looking for sudden shutdowns and heat' 'अचानक बंद पडणे आणि तापमान तपासत आहे' 'अचानक बंद होना और तापमान जाँच रहे हैं'
        $kp = Get-TSEventCount 'System' @(41) 'Microsoft-Windows-Kernel-Power' 30
        $c = Get-TGThermalC
        if ($kp -ge 2 -or ($null -ne $c -and $c -ge 85)) {
            $tt = if ($null -ne $c) { TT "; the temperature now is $c°C" "; आत्ता तापमान $c°C आहे" "; अभी तापमान $c°C है" } else { TT '' '' '' }
            return (New-TSCheck $true (TT "$kp sudden power-offs in 30 days$($tt.en)." "30 दिवसांत $kp वेळा अचानक बंद पडला$($tt.mr)." "30 दिनों में $kp बार अचानक बंद हुआ$($tt.hi)।") @{ Temp = $c })
        }
        return (New-TSCheck $false (TT 'No sudden shutdowns were recorded recently.' 'अलीकडे अचानक बंद पडल्याची नोंद नाही.' 'हाल में अचानक बंद होने का कोई रिकॉर्ड नहीं।'))
    }
    Fix = {
        param($chk)
        Set-PDPowerPlan -IsLaptop (Test-TSIsLaptop)
        return (New-TSFix $false (TT 'I set the right power plan. Sudden power-offs are usually hardware: heat, the charger / battery or the power supply.' 'योग्य power plan लावला. अचानक बंद पडणे बहुतेक hardware मुळे होते: गरम होणे, charger / battery किंवा power supply.' 'सही power plan लगाया। अचानक बंद होना ज़्यादातर hardware से होता है: गर्मी, charger / battery या power supply.') -Manual (TT 'Clean the fan and heatsink, check the charger and battery (Tools guide, Battery) and run the 10-minute stress test.' 'Fan आणि heatsink साफ करा, charger आणि battery तपासा (Tools मार्गदर्शक, Battery) आणि 10 मिनिटांचा stress test करा.' 'Fan और heatsink साफ़ करें, charger और battery जाँचें (Tools गाइड, Battery) और 10 मिनट का stress test करें।'))
    }
}
$script:D['overheat'] = @{
    Check = {
        Step 'Checking the temperature' 'तापमान तपासत आहे' 'तापमान जाँच रहे हैं'
        $c = Get-TGThermalC
        $thr = Get-TSEventCount 'System' @(37) 'Microsoft-Windows-Kernel-Processor-Power' 7
        $top = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.CPU -and $_.Name -notmatch '^(System|Idle|svchost|csrss|dwm|MsMpEng)$' } | Sort-Object CPU -Descending | Select-Object -First 1
        if (($null -ne $c -and $c -ge 80) -or $thr -ge 1) {
            $now = if ($null -ne $c) { TT "$c°C now, " "आत्ता $c°C, " "अभी $c°C, " } else { TT '' '' '' }
            return (New-TSCheck $true (TT "Overheating: $($now.en)$thr slow-downs from heat this week." "PC गरम होत आहे: $($now.mr)या आठवड्यात गरमीमुळे $thr वेळा वेग कमी झाला." "PC गर्म हो रहा है: $($now.hi)इस हफ़्ते गर्मी से $thr बार स्पीड कम हुई।") @{ Top = $top })
        }
        if ($null -eq $c) { return (New-TSCheck $null (TT 'This PC does not report its temperature to Windows, and no slow-downs from heat were recorded.' 'हा PC Windows ला तापमान सांगत नाही, आणि गरमीमुळे वेग कमी झाल्याची नोंद नाही.' 'यह PC Windows को तापमान नहीं बताता, और गर्मी से स्पीड कम होने का रिकॉर्ड नहीं है।')) }
        return (New-TSCheck $false (TT "The temperature is normal ($c°C)." "तापमान सामान्य आहे ($c°C)." "तापमान सामान्य है ($c°C)।"))
    }
    Fix = {
        param($chk)
        Set-PDPowerPlan -IsLaptop (Test-TSIsLaptop)
        $hog = if ($chk.Data -and $chk.Data.Top) { TT " The heaviest program is $($chk.Data.Top.Name)." " सर्वात जड program: $($chk.Data.Top.Name)." " सबसे भारी program: $($chk.Data.Top.Name)।" } else { TT '' '' '' }
        return (New-TSFix $false (TT "I set the balanced power plan.$($hog.en)" "योग्य power plan लावला.$($hog.mr)" "सही power plan लगाया।$($hog.hi)") -Manual (TT 'Heat is a hardware problem: clean the fan and heatsink, renew the thermal paste and keep the laptop on a hard surface.' 'गरम होणे ही hardware ची समस्या आहे: fan आणि heatsink साफ करा, thermal paste बदला आणि laptop कठीण पृष्ठभागावर ठेवा.' 'गर्मी hardware की समस्या है: fan और heatsink साफ़ करें, thermal paste बदलें और laptop सख्त सतह पर रखें।'))
    }
}
$script:D['battery'] = @{
    Check = {
        Step 'Checking the battery' 'Battery तपासत आहे' 'Battery जाँच रहे हैं'
        $r = Invoke-TGAuto -Handler 'battery' -UsbRoot $global:PDCtx.UsbRoot -P @{}
        if ($r.Status -eq 'info') { return (New-TSCheck $null (TT 'No battery was found (desktop PC).' 'Battery सापडली नाही (desktop PC).' 'Battery नहीं मिली (desktop PC)।')) }
        if ($r.Status -in 'bad', 'warn') { return (New-TSCheck $true (TT $r.HeadEn $r.HeadMr $r.HeadHi) @{ R = $r }) }
        return (New-TSCheck $false (TT $r.HeadEn $r.HeadMr $r.HeadHi))
    }
    Fix = { param($chk) return (New-TSFix $false (TT 'A worn battery cannot be repaired by software.' 'झिजलेली battery software ने दुरुस्त होत नाही.' 'घिसी हुई battery software से ठीक नहीं होती।') -Manual (TT 'Replace it with an original battery; until then use battery saver and lower brightness.' 'Original battery बदला; तोपर्यंत battery saver आणि कमी brightness वापरा.' 'Original battery लगाएँ; तब तक battery saver और कम brightness रखें।')) }
}

$script:D['windows-update'] = @{
    Check = {
        Step 'Checking Windows Update' 'Windows Update तपासत आहे' 'Windows Update जाँच रहे हैं'
        $fails = Get-TSEventCount 'System' @(20) 'Microsoft-Windows-WindowsUpdateClient' 30
        $off = @('wuauserv', 'BITS', 'CryptSvc') | Where-Object { (Get-Service $_ -ErrorAction SilentlyContinue).StartType -eq 'Disabled' }
        if ($fails -or $off) {
            $o = if ($off) { TT "; disabled services: $($off -join ', ')" "; बंद services: $($off -join ', ')" "; बंद services: $($off -join ', ')" } else { TT '' '' '' }
            return (New-TSCheck $true (TT "$fails failed update installs in 30 days$($o.en)." "30 दिवसांत $fails updates fail झाले$($o.mr)." "30 दिनों में $fails updates fail हुए$($o.hi)।"))
        }
        return (New-TSCheck $false (TT 'No failed updates were recorded.' 'Update fail झाल्याची नोंद नाही.' 'Update fail होने का कोई रिकॉर्ड नहीं।'))
    }
    Fix = {
        New-TSRestorePointOnce
        foreach ($s in 'wuauserv', 'BITS', 'CryptSvc') { if ((Get-Service $s -ErrorAction SilentlyContinue).StartType -eq 'Disabled') { Set-Service $s -StartupType Manual -ErrorAction SilentlyContinue } }
        Step 'Resetting the Windows Update components' 'Windows Update components reset करत आहे' 'Windows Update components reset कर रहे हैं'
        Reset-PDWindowsUpdate
        return (New-TSFix $true (TT 'I reset the Windows Update components (cache cleared, services restored). Now open Settings, Windows Update, Check for updates.' 'Windows Update components reset केले (cache साफ, services परत). आता Settings, Windows Update, Check for updates करा.' 'Windows Update components reset किए (cache साफ़, services वापस)। अब Settings, Windows Update, Check for updates करें।'))
    }
    NoVerify = $true
}
$script:D['corrupt-windows'] = @{
    Check = {
        Step 'Checking the Windows system files (about 10 minutes)' 'Windows system files तपासत आहे (सुमारे 10 मिनिटे)' 'Windows system files जाँच रहे हैं (लगभग 10 मिनट)'
        $img = 'Unknown'; try { $img = [string](Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop).ImageHealthState } catch { }
        if ($img -in 'Repairable', 'NonRepairable') { return (New-TSCheck $true (TT 'The Windows system image is damaged.' 'Windows system image खराब झाली आहे.' 'Windows system image खराब हो गई है।')) }
        $out = (& "$env:WINDIR\System32\sfc.exe" /verifyonly 2>&1 | Out-String) -replace "`0", ''
        if ($out -match 'found integrity violations') { return (New-TSCheck $true (TT 'SFC found damaged system files.' 'SFC ला खराब system files सापडल्या.' 'SFC को खराब system files मिलीं।')) }
        return (New-TSCheck $false (TT 'The Windows system files are healthy.' 'Windows system files ठीक आहेत.' 'Windows system files ठीक हैं।'))
    }
    Fix = {
        New-TSRestorePointOnce
        Step 'Repairing the Windows system files (DISM + SFC, 15-40 minutes)' 'Windows system files दुरुस्त करत आहे (DISM + SFC, 15-40 मिनिटे)' 'Windows system files ठीक कर रहे हैं (DISM + SFC, 15-40 मिनट)'
        $os = Invoke-PDRepairOS
        return (New-TSFix $true (TT "I repaired the system files (DISM: $($os.Dism); SFC: $($os.Sfc))." "System files दुरुस्त केल्या (DISM: $($os.Dism); SFC: $($os.Sfc))." "System files ठीक कीं (DISM: $($os.Dism); SFC: $($os.Sfc))।") -Restart)
    }
    NoVerify = $true
}
$script:D['apps-install'] = @{
    Check = $script:D['corrupt-windows'].Check
    Fix = {
        Start-Process -FilePath "$env:WINDIR\System32\wsreset.exe" -ErrorAction SilentlyContinue
        return (& $script:D['corrupt-windows'].Fix)
    }
    NoVerify = $true
}

$script:D['time'] = @{
    Check = {
        Step 'Comparing the clock with the internet time' 'घड्याळ internet च्या वेळेशी जुळवत आहे' 'घड़ी को internet के समय से मिला रहे हैं'
        $net = $null
        try { $w = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8; $net = [datetime]::Parse($w.Headers['Date']).ToUniversalTime() } catch { }
        if (-not $net) { return (New-TSCheck $null (TT 'The time cannot be compared without internet.' 'Internet शिवाय वेळ तपासता येत नाही.' 'Internet के बिना समय नहीं जाँच सकते।')) }
        $off = [math]::Round([math]::Abs(((Get-Date).ToUniversalTime() - $net).TotalMinutes), 1)
        if ($off -gt 2) { return (New-TSCheck $true (TT "The clock is $off minutes wrong." "घड्याळ $off मिनिटांनी चुकीचे आहे." "घड़ी $off मिनट गलत है।")) }
        return (New-TSCheck $false (TT 'The clock is correct.' 'वेळ बरोबर आहे.' 'समय सही है।'))
    }
    Fix = { $r = Invoke-PDQuickFix -Id 'time'; return (New-TSFix $r.Ok (From-QuickFix $r)) }
}
$script:D['taskbar'] = @{
    Check = {
        Step 'Checking the taskbar and File Explorer' 'Taskbar आणि File Explorer तपासत आहे' 'Taskbar और File Explorer जाँच रहे हैं'
        $e = @(Get-Process explorer -ErrorAction SilentlyContinue)
        if (-not $e.Count) { return (New-TSCheck $true (TT 'File Explorer (taskbar / desktop) is not running.' 'File Explorer (taskbar / desktop) चालू नाही.' 'File Explorer (taskbar / desktop) नहीं चल रहा।')) }
        if ($e | Where-Object { -not $_.Responding }) { return (New-TSCheck $true (TT 'File Explorer (taskbar / desktop) is not responding.' 'File Explorer (taskbar / desktop) अडकला आहे.' 'File Explorer (taskbar / desktop) अटका हुआ है।')) }
        return (New-TSCheck $null (TT 'File Explorer is running normally.' 'File Explorer नीट चालू आहे.' 'File Explorer ठीक चल रहा है।'))
    }
    Fix = { $r = Invoke-PDQuickFix -Id 'explorer'; return (New-TSFix $true (From-QuickFix $r)) }
    Refresh = $true
}
$script:D['search'] = @{
    Check = {
        Step 'Checking Windows Search' 'Windows Search तपासत आहे' 'Windows Search जाँच रहे हैं'
        $s = Get-Service WSearch -ErrorAction SilentlyContinue
        if (-not $s -or $s.Status -ne 'Running') { return (New-TSCheck $true (TT 'The Windows Search service is not running.' 'Windows Search service चालू नाही.' 'Windows Search service नहीं चल रही।')) }
        return (New-TSCheck $null (TT 'The Windows Search service is running.' 'Windows Search service चालू आहे.' 'Windows Search service चल रही है।'))
    }
    Fix = { Set-Service WSearch -StartupType Automatic -ErrorAction SilentlyContinue; $r = Invoke-PDQuickFix -Id 'search'; return (New-TSFix $r.Ok (From-QuickFix $r)) }
    Refresh = $true
}
$script:D['printer'] = @{
    Check = {
        Step 'Checking the printer and the print queue' 'Printer आणि print queue तपासत आहे' 'Printer और print queue जाँच रहे हैं'
        $sp = Get-Service Spooler -ErrorAction SilentlyContinue
        $why = @()
        if (-not $sp -or $sp.Status -ne 'Running') { $why += TT 'the print service is stopped' 'print service बंद आहे' 'print service बंद है' }
        $jobs = @(); try { $jobs = @(Get-Printer -ErrorAction Stop | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue }) } catch { }
        $stuck = @($jobs | Where-Object { $_.JobStatus -match 'Error|Paused|Blocked' -or $_.SubmittedTime -lt (Get-Date).AddMinutes(-5) })
        if ($stuck.Count) { $why += TT "$($stuck.Count) print jobs are stuck" "$($stuck.Count) print jobs अडकले आहेत" "$($stuck.Count) print jobs अटके हैं" }
        $off = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.WorkOffline })
        if ($off.Count) { $names = ($off | ForEach-Object Name) -join ', '; $why += TT "$names is offline" "$names offline आहे" "$names offline है" }
        if ($why.Count) { return (New-TSCheck $true (Add-TT (TT 'Printer problem:' 'Printer ची समस्या:' 'Printer की समस्या:') (Join-TT $why ', ')) @{ Off = $off }) }
        if (-not @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax' }).Count) { return (New-TSCheck $true (TT 'No real printer is installed on this PC.' 'या PC वर एकही printer install केलेला नाही.' 'इस PC पर कोई printer install नहीं है।') @{ None = $true }) }
        return (New-TSCheck $false (TT 'The print service and the print queue are fine.' 'Print service आणि print queue ठीक आहेत.' 'Print service और print queue ठीक हैं।'))
    }
    Fix = {
        param($chk)
        if ($chk.Data -and $chk.Data.None) { return (New-TSFix $false (TT 'No printer is installed.' 'Printer install केलेला नाही.' 'Printer install नहीं है।') -Manual (TT 'Connect the printer and install its driver from the maker''s website (Settings, Printers, Add device).' 'Printer जोडा आणि कंपनीच्या website वरून त्याचा driver install करा (Settings, Printers, Add device).' 'Printer जोड़ें और कंपनी की website से उसका driver install करें (Settings, Printers, Add device)।')) }
        $r = Invoke-PDQuickFix -Id 'printer'
        $txt = From-QuickFix $r
        if (@($chk.Data.Off).Count) {
            foreach ($p in @($chk.Data.Off)) { try { $p.WorkOffline = $false; Set-CimInstance -InputObject $p -ErrorAction Stop } catch { } }
            $txt = Add-TT $txt (TT 'I also set the offline printer back online.' 'Offline printer पण पुन्हा online केला.' 'Offline printer को भी फिर online किया।')
        }
        return (New-TSFix $r.Ok $txt)
    }
    Verify = {
        $sp = Get-Service Spooler -ErrorAction SilentlyContinue
        $jobs = @(); try { $jobs = @(Get-Printer -ErrorAction Stop | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue } | Where-Object { $_.JobStatus -match 'Error|Paused|Blocked' }) } catch { }
        if (-not $sp -or $sp.Status -ne 'Running' -or $jobs.Count) { return (New-TSCheck $true (TT 'The print service / queue still does not work.' 'Print service / queue अजूनही चालत नाही.' 'Print service / queue अभी भी नहीं चल रही।')) }
        return (New-TSCheck $false (TT 'The print service runs and the queue is clear.' 'Print service चालू आहे आणि queue रिकामी आहे.' 'Print service चल रही है और queue खाली है।'))
    }
}
$script:D['sound'] = @{
    Check = {
        Step 'Checking the sound services and devices' 'आवाजाच्या services आणि devices तपासत आहे' 'आवाज़ की services और devices जाँच रहे हैं'
        $why = @()
        foreach ($s in 'Audiosrv', 'AudioEndpointBuilder') { if ((Get-Service $s -ErrorAction SilentlyContinue).Status -ne 'Running') { $why += TT "the $s service is stopped" "$s service बंद आहे" "$s service बंद है" } }
        $bad = Get-TSProblemDevices @('MEDIA', 'AudioEndpoint')
        if (@($bad).Count) { $n = @($bad).Count; $why += TT "$n sound devices have errors" "$n आवाजाच्या devices मध्ये error आहे" "$n आवाज़ के devices में error है" }
        $ep = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -eq 'OK')
        if (-not $ep.Count) { $why += TT 'no working sound output' 'आवाजाचे चालू output नाही' 'आवाज़ का कोई चालू output नहीं' }
        if ($why.Count) { return (New-TSCheck $true (Add-TT (TT 'Sound problem:' 'आवाजाची समस्या:' 'आवाज़ की समस्या:') (Join-TT $why ', ')) @{ Bad = $bad; NoEp = (-not $ep.Count) }) }
        return (New-TSCheck $null (TT 'The sound services and devices work.' 'आवाजाच्या services आणि devices चालू आहेत.' 'आवाज़ की services और devices चालू हैं।'))
    }
    Fix = {
        param($chk)
        [void](Repair-TSDevices @(Get-TSProblemDevices @('MEDIA', 'AudioEndpoint')))
        $r = Invoke-PDQuickFix -Id 'audio'
        $after = & $script:D['sound'].Check
        if ($after.Found -eq $true -and $after.Data.NoEp) { return (New-TSFix $false (TT 'I restarted the sound services, but no sound device works.' 'आवाजाच्या services पुन्हा सुरू केल्या, पण आवाजाचे device काम करत नाही.' 'आवाज़ की services फिर शुरू कीं, पर आवाज़ का device काम नहीं कर रहा।') -Manual (TT 'Install the sound driver: Repair, Drivers (Realtek / Intel audio).' 'आवाजाचा driver install करा: दुरुस्ती, Drivers (Realtek / Intel audio).' 'आवाज़ का driver install करें: मरम्मत, Drivers (Realtek / Intel audio)।')) }
        return (New-TSFix $true (From-QuickFix $r))
    }
    Refresh = $true
}
$script:D['display'] = @{
    Check = {
        Step 'Checking the display driver' 'Display driver तपासत आहे' 'Display driver जाँच रहे हैं'
        $basic = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Basic Display|Basic Render' })
        $bad = Get-TSProblemDevices @('Display', 'Monitor')
        if ($basic.Count -or @($bad).Count) { return (New-TSCheck $true (TT 'There is no proper display driver (Microsoft Basic Display Adapter), so resolution and brightness do not work.' 'योग्य display driver नाही (Microsoft Basic Display Adapter), त्यामुळे resolution आणि brightness चालत नाही.' 'सही display driver नहीं है (Microsoft Basic Display Adapter), इसलिए resolution और brightness नहीं चलते।')) }
        return (New-TSCheck $false (TT 'The display driver is installed and working.' 'Display driver install आहे आणि चालू आहे.' 'Display driver install है और चल रहा है।'))
    }
    Fix = {
        [void](Repair-TSDevices @(Get-TSProblemDevices @('Display', 'Monitor')))
        $after = & $script:D['display'].Check
        if (-not $after.Found) { return (New-TSFix $true (TT 'I installed the display driver from Windows'' own driver store.' 'Windows कडच्या drivers मधून display driver install केला.' 'Windows के अपने drivers से display driver install किया।')) }
        return (New-TSFix $false (TT 'Windows has no display driver for this PC.' 'Windows कडे या PC चा display driver नाही.' 'Windows के पास इस PC का display driver नहीं है।') -Manual (TT 'Install it from the laptop / graphics maker''s website, or Repair, Drivers (offline packs on the USB).' 'Laptop / graphics कंपनीच्या website वरून install करा, किंवा दुरुस्ती, Drivers (USB वरचे offline packs).' 'Laptop / graphics कंपनी की website से install करें, या मरम्मत, Drivers (USB के offline packs)।'))
    }
}
foreach ($pair in @(@('keyboard', @('Keyboard', 'Mouse', 'HIDClass')), @('usb', @('USB', 'USBDevice', 'DiskDrive', 'WPD', 'SCSIAdapter')), @('bluetooth', @('Bluetooth')), @('camera', @('Camera', 'Image')), @('drivers', $null))) {
    $id = $pair[0]; $cls = $pair[1]
    $script:D[$id] = @{
        Classes = $cls
        Check = $ExecutionContext.SessionState.Module.NewBoundScriptBlock([scriptblock]::Create(@"
Step 'Checking the devices and their drivers' 'Devices आणि त्यांचे drivers तपासत आहे' 'Devices और उनके drivers जाँच रहे हैं'
`$bad = Get-TSProblemDevices $(if ($cls) { "@('" + ($cls -join "','") + "')" } else { '$null' })
`$why = @()
if ('$id' -eq 'bluetooth' -and (Get-Service bthserv -ErrorAction SilentlyContinue).Status -ne 'Running') { `$why += TT 'the Bluetooth service is stopped' 'Bluetooth service बंद आहे' 'Bluetooth service बंद है' }
if ('$id' -eq 'camera' -and (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' -Name Value -ErrorAction SilentlyContinue).Value -eq 'Deny') { `$why += TT 'the camera is blocked in the privacy settings' 'privacy settings मध्ये camera बंद आहे' 'privacy settings में camera बंद है' }
if ('$id' -eq 'keyboard' -and (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status' -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 0) { `$why += TT 'the touchpad is switched off' 'touchpad बंद केलेला आहे' 'touchpad बंद किया हुआ है' }
foreach (`$d in (@(`$bad) | Select-Object -First 3)) { `$nm = Get-TSDeviceName `$d; `$c = `$d.ConfigManagerErrorCode; `$why += TT "`$nm (error code `$c)" "`$nm (error code `$c)" "`$nm (error code `$c)" }
if (`$why.Count) { return (New-TSCheck `$true (Add-TT (TT 'Not working:' 'काम करत नाही:' 'काम नहीं कर रहा:') (Join-TT `$why '; ')) @{ Bad = `$bad }) }
return (New-TSCheck `$false (TT 'All these devices work and have drivers.' 'हे सगळे devices चालू आहेत आणि त्यांना drivers आहेत.' 'ये सभी devices चल रहे हैं और इनके drivers हैं।'))
"@))
        Fix = $ExecutionContext.SessionState.Module.NewBoundScriptBlock([scriptblock]::Create(@"
param(`$chk)
New-TSRestorePointOnce
if ('$id' -eq 'bluetooth') { Set-Service bthserv -StartupType Manual -ErrorAction SilentlyContinue; [void](Invoke-PDQuickFix -Id 'bluetooth') }
if ('$id' -eq 'camera') { `$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'; if ((Get-ItemProperty `$k -Name Value -ErrorAction SilentlyContinue).Value -eq 'Deny') { `$b = Save-PDRegTree -Key `$k -Name 'webcam'; Add-PDUndo @{ Type = 'RegTree'; File = `$b; Label = 'Camera privacy' }; Set-ItemProperty `$k -Name Value -Value 'Allow' } }
if ('$id' -eq 'keyboard') { `$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status'; if ((Get-ItemProperty `$k -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 0) { Set-ItemProperty `$k -Name Enabled -Value 1 } }
[void](Repair-TSDevices @(`$chk.Data.Bad))
`$after = & `$script:D['$id'].Check
if (-not `$after.Found) { return (New-TSFix `$true (TT 'I restarted / enabled the devices and let Windows install their drivers.' 'Devices पुन्हा सुरू / चालू केले आणि Windows कडचे drivers लावले.' 'Devices फिर शुरू / चालू किए और Windows के drivers लगाए।')) }
`$names = ((@(`$after.Data.Bad) | Select-Object -First 3 | ForEach-Object { Get-TSDeviceName `$_ }) -join ', ')
return (New-TSFix `$false (TT "Still not working: `$names" "अजूनही चालत नाही: `$names" "अभी भी नहीं चल रहा: `$names") -Manual (TT 'Install the missing driver: Repair, Drivers (offline packs on the USB) or the maker''s website.' 'हरवलेला driver install करा: दुरुस्ती, Drivers (USB वरचे offline packs) किंवा कंपनीची website.' 'कमी driver install करें: मरम्मत, Drivers (USB के offline packs) या कंपनी की website.'))
"@))
    }
}

$script:D['disk-failing'] = @{
    Check = {
        Step 'Checking the health of the disks' 'Disks ची health तपासत आहे' 'Disks की health जाँच रहे हैं'
        $r = Invoke-TGAuto -Handler 'disk-health' -UsbRoot $global:PDCtx.UsbRoot -P @{}
        if ($r.Status -in 'bad', 'warn') { return (New-TSCheck $true (TT ($r.HeadEn + ': ' + (($r.LinesEn | Select-Object -First 2) -join ' ')) ($r.HeadMr + ': ' + (($r.LinesMr | Select-Object -First 2) -join ' ')) ($r.HeadHi + ': ' + (($r.LinesHi | Select-Object -First 2) -join ' ')))) }
        return (New-TSCheck $false (TT 'All disks are healthy.' 'सगळ्या disks ठीक आहेत.' 'सभी disks ठीक हैं।'))
    }
    Fix = { return (New-TSFix $false (TT 'A failing disk cannot be repaired by software.' 'खराब होणारी disk software ने दुरुस्त होत नाही.' 'खराब होती disk software से ठीक नहीं होती।') -Manual (TT 'Copy important data to another disk now, then replace the disk.' 'महत्त्वाचा data लगेच दुसऱ्या disk वर copy करा, मग disk बदला.' 'ज़रूरी data तुरंत दूसरी disk पर copy करें, फिर disk बदलें।')) }
}
$script:D['ram'] = @{
    Check = {
        Step 'Checking the RAM' 'RAM तपासत आहे' 'RAM जाँच रहे हैं'
        $gb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $md = $null; try { $md = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction Stop } catch { }
        if ($md -and $md.Id -ne 1201) { return (New-TSCheck $true (TT 'The last RAM test found errors.' 'मागच्या RAM test मध्ये errors सापडल्या.' 'पिछले RAM test में errors मिले।') @{ Bad = $true }) }
        if ($gb -lt 7.5) { return (New-TSCheck $true (TT "The PC has only $gb GB RAM." "PC मध्ये फक्त $gb GB RAM आहे." "PC में सिर्फ़ $gb GB RAM है।") @{ Low = $gb }) }
        return (New-TSCheck $false (TT "$gb GB RAM and no RAM errors recorded." "$gb GB RAM आहे आणि RAM errors ची नोंद नाही." "$gb GB RAM है और RAM errors का कोई रिकॉर्ड नहीं।"))
    }
    Fix = {
        param($chk)
        if ($chk.Data.Bad) { return (New-TSFix $false (TT 'The RAM is faulty.' 'RAM खराब आहे.' 'RAM खराब है।') -Manual (TT 'Test the sticks one at a time (MemTest86+ from the USB) and replace the faulty one.' 'Sticks एक-एक करून तपासा (USB वरून MemTest86+) आणि खराब stick बदला.' 'Sticks एक-एक करके जाँचें (USB से MemTest86+) और खराब stick बदलें।')) }
        return (New-TSFix $false (TT 'Low RAM makes the PC slow; software cannot add RAM.' 'कमी RAM मुळे PC हळू चालतो; software ने RAM वाढत नाही.' 'कम RAM से PC धीमा चलता है; software से RAM नहीं बढ़ती।') -Manual (TT 'Add RAM (8 GB or more). Tools guide, CPU-Z, "Check automatically" tells which RAM to buy.' 'RAM वाढवा (8 GB किंवा जास्त). Tools मार्गदर्शक, CPU-Z, "आपोआप तपासा" कोणती RAM घ्यायची ते सांगते.' 'RAM बढ़ाएँ (8 GB या ज़्यादा)। Tools गाइड, CPU-Z, "अपने आप जाँचें" बताता है कौन सी RAM लें।'))
    }
}

# viruses: only real evidence counts. A third-party antivirus switches Defender off on purpose - that is not a problem.
$script:D['virus'] = @{
    Check = {
        Step 'Checking the antivirus, recent threats and malware autostarts' 'Antivirus, सापडलेले virus आणि virus सारखे autostarts तपासत आहे' 'Antivirus, मिले virus और virus जैसे autostarts जाँच रहे हैं'
        $why = @()
        $avs = @(Get-TSAntivirus)
        $other = @($avs | Where-Object { -not $_.Microsoft })
        $st = $null; try { $st = Get-MpComputerStatus -ErrorAction Stop } catch { }
        if ($other.Count) {
            if (-not @($other | Where-Object Enabled).Count) { $n = ($other | ForEach-Object Name) -join ', '; $why += TT "the antivirus ($n) is switched off" "antivirus ($n) बंद आहे" "antivirus ($n) बंद है" }
        } elseif ($st) {
            if (-not $st.RealTimeProtectionEnabled) { $why += TT 'Microsoft Defender protection is off and no other antivirus is installed' 'Microsoft Defender protection बंद आहे आणि दुसरा antivirus नाही' 'Microsoft Defender protection बंद है और दूसरा antivirus नहीं है' }
            elseif ($st.AntivirusSignatureAge -gt 7 -and $st.AntivirusSignatureAge -lt 3650) { $why += TT "the virus definitions are $($st.AntivirusSignatureAge) days old" "virus definitions $($st.AntivirusSignatureAge) दिवस जुनी आहेत" "virus definitions $($st.AntivirusSignatureAge) दिन पुरानी हैं" }
        }
        $thr = @(Get-TSActiveThreats)
        if ($thr.Count) { $why += TT "$($thr.Count) threats were detected and not removed" "$($thr.Count) virus सापडले आहेत आणि अजून काढलेले नाहीत" "$($thr.Count) virus मिले हैं और अभी हटाए नहीं गए" }
        $reg = @(Get-PDRegistryIssues | Where-Object { $_.Kind -eq 'malware' -and $_.Selected })
        if ($reg.Count) { $why += TT "$($reg.Count) Windows settings were changed the way viruses do" "$($reg.Count) Windows settings virus सारख्या बदललेल्या आहेत" "$($reg.Count) Windows settings virus की तरह बदली गई हैं" }
        $auto = @(Get-TSSuspiciousAutostarts)
        if ($auto.Count) { $n = ($auto | Select-Object -First 3 | ForEach-Object Name) -join ', '; $why += TT "$($auto.Count) suspicious programs start by themselves ($n)" "$($auto.Count) संशयास्पद programs आपोआप सुरू होतात ($n)" "$($auto.Count) संदिग्ध programs अपने आप शुरू होते हैं ($n)" }
        $data = @{ Reg = $reg; Auto = $auto; Threats = $thr.Count; DefenderActive = (-not $other.Count -and $st) }
        if ($why.Count) { return (New-TSCheck $true (Add-TT (TT 'Found:' 'सापडले:' 'मिला:') (Join-TT $why '; ')) $data) }
        return (New-TSCheck $null (TT 'The antivirus is on, no threats are recorded and no malware settings or autostarts were found.' 'Antivirus चालू आहे, कोणत्याही virus ची नोंद नाही आणि virus सारखे बदल किंवा autostarts सापडले नाहीत.' 'Antivirus चालू है, किसी virus का रिकॉर्ड नहीं, और virus जैसे बदलाव या autostarts नहीं मिले।') $data)
    }
    # nothing visible: a real quick scan decides (only when Defender is the active antivirus)
    Probe = {
        param($chk)
        if (-not $chk.Data.DefenderActive) { return (New-TSCheck $false (Add-TT $chk.Text (TT 'Your own antivirus protects this PC.' 'या PC ला तुमचा antivirus संरक्षण देतो.' 'इस PC को आपका antivirus सुरक्षा देता है।')) $chk.Data) }
        Step 'Running a Microsoft Defender quick scan (a few minutes)' 'Microsoft Defender quick scan चालू आहे (काही मिनिटे)' 'Microsoft Defender quick scan चल रहा है (कुछ मिनट)'
        try { Start-MpScan -ScanType QuickScan -ErrorAction Stop } catch { return (New-TSCheck $false (Add-TT $chk.Text (TT 'The quick scan could not run.' 'Quick scan चालू होऊ शकला नाही.' 'Quick scan नहीं चल सका।')) $chk.Data) }
        $thr = @(Get-TSActiveThreats)
        if ($thr.Count) { $d = $chk.Data; $d.Threats = $thr.Count; return (New-TSCheck $true (TT "The quick scan found $($thr.Count) threats." "Quick scan ला $($thr.Count) virus सापडले." "Quick scan में $($thr.Count) virus मिले।") $d) }
        return (New-TSCheck $false (TT 'Antivirus on, no malware settings or autostarts, and a full quick scan found no virus.' 'Antivirus चालू, virus सारखे बदल / autostarts नाहीत, आणि quick scan मध्ये एकही virus सापडला नाही.' 'Antivirus चालू, virus जैसे बदलाव / autostarts नहीं, और quick scan में कोई virus नहीं मिला।') $chk.Data)
    }
    Fix = {
        param($chk)
        New-TSRestorePointOnce
        $did = @(); $failed = @()
        if (@($chk.Data.Reg).Count) {
            $r = Repair-PDRegistryIssues -Issues $chk.Data.Reg -NoRestorePoint
            if ($r.Fixed) { $did += TT "reverted $($r.Fixed) settings changed by malware" "virus ने बदललेल्या $($r.Fixed) settings परत केल्या" "virus द्वारा बदली $($r.Fixed) settings वापस कीं" }
        }
        if (@($chk.Data.Auto).Count) {
            $n = Disable-TSAutostarts $chk.Data.Auto
            if ($n) { $did += TT "turned off $n suspicious autostarts" "$n संशयास्पद autostarts बंद केले" "$n संदिग्ध autostarts बंद किए" }
        }
        if ($chk.Data.DefenderActive) {
            Step 'Turning on Microsoft Defender and removing threats' 'Microsoft Defender चालू करून virus काढत आहे' 'Microsoft Defender चालू करके virus हटा रहे हैं'
            try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop } catch { $failed += TT 'Defender could not be turned on' 'Defender चालू होऊ शकला नाही' 'Defender चालू नहीं हो सका' }
            try { Update-MpSignature -ErrorAction Stop; $did += TT 'updated the virus definitions' 'virus definitions update केल्या' 'virus definitions update कीं' } catch { }
            if ($chk.Data.Threats) { try { Remove-MpThreat -ErrorAction Stop; $did += TT "removed $($chk.Data.Threats) threats" "$($chk.Data.Threats) virus काढले" "$($chk.Data.Threats) virus हटाए" } catch { $failed += TT 'the threats could not be removed' 'virus काढता आले नाहीत' 'virus हटाए नहीं जा सके' } }
        }
        $after = & $script:D['virus'].Check
        $txt = if ($did.Count) { Add-TT (TT 'I' 'मी' 'मैंने') (Join-TT $did ', ') } else { TT 'Nothing could be changed automatically.' 'आपोआप काहीही बदलता आले नाही.' 'अपने आप कुछ नहीं बदला जा सका।' }
        if ($failed.Count) { $txt = Add-TT $txt (Add-TT (TT 'Not done:' 'झाले नाही:' 'नहीं हुआ:') (Join-TT $failed ', ')) '. ' }
        if ($after.Found -eq $true) {
            return (New-TSFix $false (Add-TT $txt (Add-TT (TT 'Still present:' 'अजूनही आहे:' 'अभी भी है:') $after.Text) '. ') -Manual (TT 'Boot from the USB and run Kaspersky Rescue Disk to clean the PC from outside Windows; or update / turn on your own antivirus.' 'USB वरून boot करून Kaspersky Rescue Disk ने Windows बाहेरून PC साफ करा; किंवा तुमचा antivirus update / चालू करा.' 'USB से boot करके Kaspersky Rescue Disk से Windows के बाहर से PC साफ़ करें; या अपना antivirus update / चालू करें।'))
        }
        return (New-TSFix $true (Add-TT $txt (TT 'No virus signs are left.' 'आता virus ची कोणतीही खूण उरलेली नाही.' 'अब virus का कोई निशान नहीं बचा।') '. '))
    }
    NoVerify = $true      # Fix already re-checks
}
$script:D['browser'] = $script:D['virus']

# windows / files / websites opening by themselves
$script:D['auto-open'] = @{
    Check = {
        Step 'Looking for programs that open things by themselves' 'आपोआप गोष्टी उघडणारे programs शोधत आहे' 'अपने आप चीज़ें खोलने वाले programs खोज रहे हैं'
        $c = & $script:D['virus'].Check
        $why = @()
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' } | Where-Object {
                @($_.Triggers | Where-Object { $_.Repetition -and $_.Repetition.Interval }).Count -and @($_.Actions | Where-Object { "$($_.Execute) $($_.Arguments)" -match '(?i)https?://|\.(html?|url)\b|explorer(\.exe)?\s|start\s' }).Count })
        if ($tasks.Count) { $n = ($tasks | Select-Object -First 3 | ForEach-Object TaskName) -join ', '; $why += TT "$($tasks.Count) scheduled tasks repeatedly open websites / files ($n)" "$($tasks.Count) scheduled tasks वारंवार websites / files उघडतात ($n)" "$($tasks.Count) scheduled tasks बार-बार websites / files खोलते हैं ($n)" }
        if ($c.Found -eq $true -or $why.Count) {
            $t = if ($c.Found -eq $true) { $c.Text } else { $null }
            $data = $c.Data; $data.Tasks = $tasks
            return (New-TSCheck $true (Join-TT @($t, (Add-TT (TT 'Found:' 'सापडले:' 'मिला:') (Join-TT $why '; '))) ' ') $data)
        }
        $data = $c.Data; $data.Tasks = @()
        return (New-TSCheck $null (TT 'No program that opens windows, files or websites by itself was found.' 'Windows, files किंवा websites आपोआप उघडणारा कोणताही program सापडला नाही.' 'Windows, files या websites अपने आप खोलने वाला कोई program नहीं मिला।') $data)
    }
    Probe = { param($chk) return (& $script:D['virus'].Probe $chk) }
    Fix = {
        param($chk)
        $r = & $script:D['virus'].Fix $chk
        $n = 0
        foreach ($t in @($chk.Data.Tasks)) { try { Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; $n++ } catch { } }
        if ($n) { $r.Text = Add-TT $r.Text (TT "I also turned off $n scheduled tasks that kept opening things." "वारंवार गोष्टी उघडणारे $n scheduled tasks पण बंद केले." "बार-बार चीज़ें खोलने वाले $n scheduled tasks भी बंद किए।") }
        return $r
    }
    NoVerify = $true
}

$script:D['task-manager'] = @{
    Check = {
        Step 'Looking for tools blocked by malware' 'Virus ने बंद केलेली tools शोधत आहे' 'Virus द्वारा बंद tools खोज रहे हैं'
        $reg = @(Get-PDRegistryIssues | Where-Object { $_.Kind -eq 'malware' })
        if ($reg.Count) { $n = ($reg | Select-Object -First 3 | ForEach-Object Title) -join '; '; return (New-TSCheck $true (TT "Blocked or changed by malware: $n" "Virus ने बंद / बदललेले: $n" "Virus द्वारा बंद / बदला गया: $n") @{ Reg = $reg }) }
        return (New-TSCheck $false (TT 'No blocked tools or malware settings were found.' 'बंद केलेली tools किंवा virus चे बदल सापडले नाहीत.' 'कोई बंद tool या virus का बदलाव नहीं मिला।'))
    }
    Fix = { param($chk) New-TSRestorePointOnce; $r = Repair-PDRegistryIssues -Issues $chk.Data.Reg -NoRestorePoint; return (New-TSFix ($r.Fixed -gt 0) (TT "I reverted $($r.Fixed) settings changed by malware (backup and Undo kept). Run a virus scan too." "Virus ने बदललेल्या $($r.Fixed) settings परत केल्या (backup आणि Undo ठेवले). Virus scan पण करा." "Virus द्वारा बदली $($r.Fixed) settings वापस कीं (backup और Undo रखा)। Virus scan भी करें।")) }
}
$script:D['activation'] = @{
    Check = {
        Step 'Checking the Windows activation' 'Windows activation तपासत आहे' 'Windows activation जाँच रहे हैं'
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lic -and $lic.LicenseStatus -eq 1) { return (New-TSCheck $false (TT 'Windows is activated.' 'Windows activate आहे.' 'Windows activate है।')) }
        $key = (Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3xOriginalProductKey
        $k = if ($key) { TT '; a key is stored in the BIOS' '; BIOS मध्ये key आहे' '; BIOS में key है' } else { TT '' '' '' }
        return (New-TSCheck $true (TT "Windows is not activated$($k.en)." "Windows activate नाही$($k.mr)." "Windows activate नहीं है$($k.hi)।") @{ Key = $key })
    }
    Fix = {
        param($chk)
        if ($chk.Data.Key) {
            $slmgr = "$env:WINDIR\System32\slmgr.vbs"
            $null = & cscript.exe //nologo $slmgr /ipk $chk.Data.Key 2>&1
            $null = & cscript.exe //nologo $slmgr /ato 2>&1
            $after = & $script:D['activation'].Check
            if (-not $after.Found) { return (New-TSFix $true (TT 'I activated Windows with the key stored in the BIOS.' 'BIOS मधल्या key ने Windows activate केले.' 'BIOS की key से Windows activate किया।')) }
        }
        return (New-TSFix $false (TT 'Windows could not be activated automatically.' 'Windows आपोआप activate झाले नाही.' 'Windows अपने आप activate नहीं हुआ।') -Manual (TT 'Settings, Activation, Troubleshoot, or enter a genuine key. Never use cracks or activators.' 'Settings, Activation, Troubleshoot, किंवा original key टाका. Crack किंवा activator कधीही वापरू नका.' 'Settings, Activation, Troubleshoot, या original key डालें। Crack या activator कभी न इस्तेमाल करें।'))
    }
}

# ------------------------------------------------------------------ runner
function Get-PDTroubleshootable { return @($script:D.Keys) }

function Invoke-PDTroubleshoot {
    param([Parameter(Mandatory)][string[]]$Ids, [Parameter(Mandatory)][object[]]$Problems)
    $script:RpDone = $false
    # Outcome: fixed | restart | manual | failed | notfound
    $res = [pscustomobject]@{ Outcome = 'notfound'; Issue = $null; Check = $null; Fix = $null; Checked = @(); Refreshed = @(); Guide = @(); Restart = $false; Resolved = $false; IsLaptop = (Test-TSIsLaptop) }
    foreach ($id in ($Ids | Select-Object -Unique)) {
        if ($global:PDState -and $global:PDState.Cancel) { break }
        $p = $Problems | Where-Object { $_.id -eq $id } | Select-Object -First 1
        $d = $script:D[$id]
        if (-not $d) { if ($p) { $res.Guide += [pscustomobject]@{ Id = $id; Problem = $p; Text = (Get-TSManual $p) } }; continue }
        Write-PDLog "Checking: $($p.en.title)" 'STEP'
        Send-TSEvent 'check' $p
        $chk = $null
        try { $chk = & $d.Check } catch { Write-PDLog "check $id failed: $($_.Exception.Message)" 'WARN'; continue }
        if ($null -eq $chk.Found -and $d.Probe) {
            Send-TSEvent 'probe' $p
            try { $chk = & $d.Probe $chk } catch { Write-PDLog "probe $id failed: $($_.Exception.Message)" 'WARN' }
        }
        $res.Checked += [pscustomobject]@{ Id = $id; Problem = $p; Check = $chk }
        if ($chk.Found -eq $false) { Write-PDLog ('  not found: ' + $chk.Text.en) 'OK'; continue }
        if ($null -eq $chk.Found) {
            if ($d.Refresh) {
                # nothing wrong could be measured; a harmless restart of the service is done and reported as such
                Send-TSEvent 'refresh' $p
                try { $f = & $d.Fix $chk; $res.Refreshed += [pscustomobject]@{ Id = $id; Problem = $p; Fix = $f } } catch { }
            } elseif ($p) { $res.Guide += [pscustomobject]@{ Id = $id; Problem = $p; Text = $chk.Text } }
            Write-PDLog ('  nothing measurable: ' + $chk.Text.en) 'INFO'
            continue
        }
        Write-PDLog ('  found: ' + $chk.Text.en) 'WARN'
        Send-TSEvent 'fix' $p
        $fix = $null
        try { $fix = & $d.Fix $chk } catch { $fix = New-TSFix $false (TT "The repair failed: $($_.Exception.Message)" "दुरुस्ती अयशस्वी: $($_.Exception.Message)" "मरम्मत असफल: $($_.Exception.Message)") }
        if (-not $fix.Text) { $fix.Text = TT 'The repair did not report anything.' 'दुरुस्तीने काहीही कळवले नाही.' 'मरम्मत ने कुछ नहीं बताया।' }
        if ($fix.Fixed -eq $true -and -not $d.NoVerify -and -not $fix.Restart) {
            Send-TSEvent 'verify' $p
            try {
                $v = if ($d.Verify) { & $d.Verify } else { & $d.Check }
                if ($v.Found -eq $true) { $fix.Fixed = $false; $fix.Text = Add-TT $fix.Text (TT '(the problem is still there after the repair)' '(दुरुस्तीनंतरही समस्या आहे)' '(मरम्मत के बाद भी समस्या है)') }
            } catch { }
        }
        $res.Issue = $p; $res.Check = $chk; $res.Fix = $fix; $res.Restart = $fix.Restart
        $res.Outcome = if ($fix.Fixed -eq $true -and -not $fix.Restart) { 'fixed' } elseif ($fix.Restart -and $fix.Fixed -ne $false) { 'restart' } elseif ($fix.Manual) { 'manual' } else { 'failed' }
        $res.Resolved = $res.Outcome -in 'fixed', 'restart'
        Write-PDLog ('  ' + $fix.Text.en) $(if ($res.Resolved) { 'OK' } else { 'WARN' })
        if ($res.Resolved -or $fix.Manual) { break }
    }
    return $res
}

$script:Words = @{
    en = @{ issue = 'Issue'; found = 'What I found'; did = 'What I did'; result = 'Result'; ok = '✔ Solved.'; restart = '↻ Restart the PC so the changes take effect.'; manual = 'What you need to do'
            failed = '⚠ It could not be fixed automatically.'; partial = '⚠ Software alone cannot fully solve this.'; none = 'I checked everything: no such problem was found on this {0}.'; checked = 'What I checked'
            refreshed = 'As a precaution'; guide = 'If it still happens'; pc = 'PC'; laptop = 'laptop' }
    mr = @{ issue = 'समस्या'; found = 'काय सापडले'; did = 'काय केले'; result = 'निकाल'; ok = '✔ समस्या सुटली.'; restart = '↻ बदल लागू होण्यासाठी PC restart करा.'; manual = 'तुम्ही करायचे'
            failed = '⚠ आपोआप दुरुस्त होऊ शकले नाही.'; partial = '⚠ ही समस्या फक्त software ने पूर्ण सुटत नाही.'; none = 'मी सर्व तपासले: असा कोणताही issue आपल्या {0} मध्ये आढळला नाही.'; checked = 'काय तपासले'
            refreshed = 'खबरदारी म्हणून'; guide = 'तरीही असे होत असेल तर'; pc = 'PC'; laptop = 'laptop' }
    hi = @{ issue = 'समस्या'; found = 'क्या मिला'; did = 'क्या किया'; result = 'नतीजा'; ok = '✔ समस्या हल हो गई।'; restart = '↻ बदलाव लागू होने के लिए PC restart करें।'; manual = 'आपको क्या करना है'
            failed = '⚠ अपने आप ठीक नहीं हो सका।'; partial = '⚠ यह समस्या सिर्फ़ software से पूरी हल नहीं होती।'; none = 'मैंने सब कुछ जाँचा: ऐसा कोई issue आपके {0} में नहीं मिला।'; checked = 'क्या जाँचा'
            refreshed = 'सावधानी के तौर पर'; guide = 'फिर भी ऐसा हो तो'; pc = 'PC'; laptop = 'laptop' }
}
function Get-TSPick($T, [string]$Lang) { if ($null -eq $T) { return '' } elseif ($T -is [string]) { return $T } else { $v = $T.$Lang; if ($v) { return $v } else { return $T.en } } }
function Get-TSTitle($P, [string]$Lang) { if (-not $P) { return '' }; $t = $P.$Lang.title; if ($t) { return $t } else { return $P.en.title } }

# Short written summary in the chosen language
function Format-PDTroubleshoot($R, [string]$Lang = 'mr') {
    $W = $script:Words[$Lang]; if (-not $W) { $W = $script:Words.en; $Lang = 'en' }
    $out = @()
    if ($R.Issue) {
        $out += "$($W.issue): $(Get-TSTitle $R.Issue $Lang)"
        $out += "$($W.found): $(Get-TSPick $R.Check.Text $Lang)"
        $out += "$($W.did): $(Get-TSPick $R.Fix.Text $Lang)"
        $out += "$($W.result): " + $(switch ($R.Outcome) { 'fixed' { $W.ok } 'restart' { $W.restart } 'manual' { $W.partial } default { $W.failed } })
        if ($R.Fix.Manual) { $out += "$($W.manual): $(Get-TSPick $R.Fix.Manual $Lang)" }
    } else {
        $out += ($W.none -f $(if ($R.IsLaptop) { $W.laptop } else { $W.pc }))
        foreach ($c in @($R.Checked)) { $out += "• $(Get-TSTitle $c.Problem $Lang): $(Get-TSPick $c.Check.Text $Lang)" }
        foreach ($f in @($R.Refreshed)) { $out += "$($W.refreshed): $(Get-TSPick $f.Fix.Text $Lang)" }
        foreach ($g in ($R.Guide | Select-Object -First 1)) { if ($g.Problem) { $out += "$($W.guide): $(Get-TSPick (Get-TSManual $g.Problem) $Lang)" } }
    }
    return $out
}

# What the voice assistant says at the end (short, natural sentences)
function Get-PDTroubleshootSpeech($R, [string]$Lang = 'mr') {
    $dev = @{ en = $(if ($R.IsLaptop) { 'laptop' } else { 'PC' }); mr = $(if ($R.IsLaptop) { 'laptop' } else { 'PC' }); hi = $(if ($R.IsLaptop) { 'laptop' } else { 'PC' }) }[$Lang]
    if (-not $R.Issue) {
        $s = @{ en = "I checked everything. No such problem was found on your $dev."; mr = "मी सर्व तपासले. असा कोणताही issue आपल्या $dev मध्ये आढळला नाही."; hi = "मैंने सब कुछ जाँच लिया। ऐसा कोई issue आपके $dev में नहीं मिला।" }[$Lang]
        if (@($R.Refreshed).Count) { $s += ' ' + @{ en = 'As a precaution I restarted the related service.'; mr = 'खबरदारी म्हणून संबंधित service पुन्हा सुरू केली.'; hi = 'सावधानी के तौर पर संबंधित service फिर से शुरू की।' }[$Lang] }
        if (@($R.Guide).Count) { $s += ' ' + @{ en = 'If it still happens, see the steps on the screen.'; mr = 'तरीही असे होत असेल तर स्क्रीनवरचे उपाय पहा.'; hi = 'फिर भी ऐसा हो तो स्क्रीन पर दिए उपाय देखें।' }[$Lang] }
        return $s
    }
    $title = Get-TSTitle $R.Issue $Lang
    $found = Get-TSPick $R.Check.Text $Lang
    $did = Get-TSPick $R.Fix.Text $Lang
    $head = @{ en = "The problem was: $found"; mr = "समस्या अशी होती: $found"; hi = "समस्या यह थी: $found" }[$Lang]
    $tail = switch ($R.Outcome) {
        'fixed'   { @{ en = 'The problem is solved now.'; mr = 'आता समस्या सुटली आहे.'; hi = 'अब समस्या हल हो गई है।' }[$Lang] }
        'restart' { @{ en = 'Please restart the PC so the changes take effect.'; mr = 'बदल लागू होण्यासाठी कृपया PC restart करा.'; hi = 'बदलाव लागू होने के लिए कृपया PC restart करें।' }[$Lang] }
        default   { (@{ en = 'Now you need to do this: '; mr = 'आता आपल्याला हे करावे लागेल: '; hi = 'अब आपको यह करना होगा: ' }[$Lang]) + (Get-TSPick $R.Fix.Manual $Lang) }
    }
    if (-not $found) { $head = @{ en = "The problem was: $title."; mr = "समस्या अशी होती: $title."; hi = "समस्या यह थी: $title." }[$Lang] }
    return "$head $did $tail"
}

Export-ModuleMember -Function Invoke-PDTroubleshoot, Format-PDTroubleshoot, Get-PDTroubleshootSpeech, Get-PDTroubleshootable, Get-TSSuspiciousAutostarts, Get-TSAntivirus
