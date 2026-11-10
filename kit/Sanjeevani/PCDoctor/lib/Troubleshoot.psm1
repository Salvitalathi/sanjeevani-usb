# Sanjeevani PC Doctor - automatic troubleshooter.
# For each likely problem (in the order the AI / matcher ranked them):  CHECK whether it really exists on this PC ->
# if yes FIX it with PC Doctor's own safe actions -> CHECK again to confirm. If the problem is not there, the next
# candidate is checked. Ends with a short summary (English / मराठी / हिन्दी): what the issue was and what was done.
# One restore point is created before the first change. Nothing here deletes user files.
Set-StrictMode -Off

# ------------------------------------------------------------------ results
function TT([string]$En, [string]$Mr, [string]$Hi) { [pscustomobject]@{ en = $En; mr = $Mr; hi = $(if ($Hi) { $Hi } else { $En }) } }
function New-TSCheck($Found, $Text, $Data = $null) { [pscustomobject]@{ Found = $Found; Text = $Text; Data = $Data } }
function New-TSFix([object]$Fixed, $Text, [switch]$Restart, $Manual = $null) { [pscustomobject]@{ Fixed = $Fixed; Text = $Text; Restart = [bool]$Restart; Manual = $Manual } }

function Get-TSDataDir { return (Join-Path $global:PDCtx.KitRoot 'PCDoctor\data') }
function Step([string]$En, [string]$Mr) { Write-PDLog $En 'STEP'; Set-PDProgress -1 $(if ((Get-PDLang) -eq 'mr' -and $Mr) { $Mr } else { $En }) }
$script:RpDone = $false
function New-TSRestorePointOnce { if (-not $script:RpDone) { $script:RpDone = $true; [void](New-PDRestorePoint 'Sanjeevani: auto troubleshoot') } }

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
function Repair-TSDevices($Devices) {
    $did = @()
    foreach ($d in $Devices) {
        try {
            if ($d.ConfigManagerErrorCode -eq 22) { Enable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop; $did += "enabled $($d.Name)" }
            else { $null = & pnputil.exe /restart-device "$($d.PNPDeviceID)" 2>&1; $did += "restarted $($d.Name)" }
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
    TT (($Problem.en.steps | Select-Object -First 3) -join ' ') (($Problem.mr.steps | Select-Object -First 3) -join ' ') $null
}

# ------------------------------------------------------------------ doctors
$script:D = @{}

$script:D['no-internet'] = @{
    Check = {
        if (Test-TSWeb) { return (New-TSCheck $false (TT 'Internet works on this PC.' 'या PC वर internet चालते.' 'इस PC पर इंटरनेट चल रहा है।')) }
        $up = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
        if (-not $up.Count) { return (New-TSCheck $true (TT 'No network connection (WiFi / cable not connected).' 'कोणतेही network जोडलेले नाही (WiFi / cable नाही).' 'कोई नेटवर्क जुड़ा नहीं है (WiFi / केबल नहीं).') @{ NoLink = $true }) }
        return (New-TSCheck $true (TT 'Connected to a network but the internet does not open.' 'Network जोडलेले आहे पण internet उघडत नाही.' 'नेटवर्क जुड़ा है पर इंटरनेट नहीं खुल रहा।'))
    }
    Fix = {
        param($chk)
        $did = @()
        Step 'Clearing DNS / proxy'
        $null = & ipconfig.exe /flushdns 2>&1; $did += 'DNS cache cleared'
        $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if ((Get-ItemProperty $is -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable -eq 1 -and -not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
            New-TSRestorePointOnce
            $bak = Save-PDRegTree -Key $is -Name 'proxy'; Add-PDUndo @{ Type = 'RegTree'; File = $bak; Label = 'Proxy' }
            Set-ItemProperty $is -Name ProxyEnable -Value 0; $did += 'proxy switched off'
        }
        if (Test-TSWeb) { return (New-TSFix $true (TT ('Fixed: ' + ($did -join ', ') + '.') ('दुरुस्त: DNS / proxy साफ केले.') ('ठीक किया: DNS / proxy साफ किया।'))) }
        Step 'Restarting network adapters'
        Set-Service WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service WlanSvc -ErrorAction SilentlyContinue
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
            if ($a.Status -eq 'Disabled') { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue; $did += "enabled $($a.Name)" }
            elseif ($a.Status -eq 'Up') { Restart-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
        }
        $null = & ipconfig.exe /renew 2>&1
        Start-Sleep 8
        if (Test-TSWeb) { return (New-TSFix $true (TT 'Fixed: network adapters restarted and a new IP address taken.' 'दुरुस्त: network adapters पुन्हा सुरू करून नवीन IP घेतला.' 'ठीक किया: नेटवर्क एडेप्टर फिर से चालू कर नया IP लिया।')) }
        if ($chk.Data -and $chk.Data.NoLink) {
            return (New-TSFix $false (TT 'Still no connection.' 'अजून connection नाही.' 'अभी भी कनेक्शन नहीं।') -Manual (TT 'Connect to WiFi / plug in the cable; if the WiFi option is missing, the WiFi driver is missing (Repair -> Drivers).' 'WiFi ला connect करा / cable लावा; WiFi पर्यायच नसेल तर WiFi driver नाही (दुरुस्ती -> Drivers).' 'WiFi से जोड़ें / केबल लगाएँ; WiFi विकल्प ही न हो तो WiFi ड्राइवर नहीं है (Repair -> Drivers).'))
        }
        Step 'Resetting the network stack (Winsock / TCP-IP)'
        New-TSRestorePointOnce
        Reset-PDNetwork
        return (New-TSFix $null (TT 'Network settings reset (Winsock / TCP-IP / DNS). Restart the PC to finish. If it still fails after the restart, the router / internet provider is the cause.' 'Network settings reset केल्या (Winsock / TCP-IP / DNS). पूर्ण होण्यासाठी PC restart करा. Restart नंतरही न चालल्यास router / internet company कारण आहे.' 'नेटवर्क सेटिंग्स रीसेट कीं। पूरा करने के लिए PC रीस्टार्ट करें। फिर भी न चले तो राउटर / इंटरनेट कंपनी कारण है।') -Restart)
    }
}
$script:D['lan'] = $script:D['no-internet']
$script:D['slow-internet'] = @{
    Check = {
        $pingHost = '8.8.8.8'
        $t = @(Test-Connection -ComputerName $pingHost -Count 6 -ErrorAction SilentlyContinue)
        if (-not $t.Count -and (Test-TSWeb)) { return (New-TSCheck $null (TT 'The internet works; this network blocks ping, so the speed cannot be measured here.' 'Internet चालते; हे network ping अडवते, त्यामुळे वेग इथे मोजता येत नाही.' 'इंटरनेट चल रहा है; यह नेटवर्क ping रोकता है।')) }
        if (-not $t.Count) { return (New-TSCheck $true (TT 'The internet does not answer at all.' 'Internet अजिबात उत्तर देत नाही.' 'इंटरनेट बिल्कुल जवाब नहीं दे रहा।') @{ Down = $true }) }
        $ms = [math]::Round(($t | Measure-Object ResponseTime -Average).Average); $lost = 6 - $t.Count
        $proxy = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable -eq 1
        if ($ms -gt 150 -or $lost -ge 1 -or $proxy) { return (New-TSCheck $true (TT "Slow internet: $ms ms, $lost/6 packets lost$(if ($proxy) { ', a proxy is set' })." "Internet हळू: $ms ms, 6 पैकी $lost packets हरवले$(if ($proxy) { ', proxy लावलेला आहे' })." "इंटरनेट धीमा: $ms ms, 6 में से $lost पैकेट खोए$(if ($proxy) { ', proxy लगा है' })।")) }
        return (New-TSCheck $false (TT "Internet speed to the outside is fine ($ms ms, no loss)." "Internet चा प्रतिसाद ठीक आहे ($ms ms)." "इंटरनेट की गति ठीक है ($ms ms)।"))
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
        return (New-TSFix $null (TT 'DNS cache cleared and any proxy switched off.' 'DNS cache साफ केला आणि proxy बंद केला.' 'DNS cache साफ किया और proxy बंद किया।') -Manual (TT 'If it is still slow: move closer to the router or use a cable, pause big downloads; otherwise it is the internet provider.' 'तरीही हळू असेल: router जवळ जा किंवा cable वापरा, मोठे downloads थांबवा; नाहीतर internet company ची समस्या.' 'फिर भी धीमा हो: राउटर के पास जाएँ या केबल लगाएँ, बड़े डाउनलोड रोकें; वरना इंटरनेट कंपनी की समस्या।'))
    }
}
$script:D['wifi'] = @{
    Check = {
        $w = Get-TSWirelessAdapters
        $svc = Get-Service WlanSvc -ErrorAction SilentlyContinue
        $bad = Get-TSProblemDevices @('Net') | Where-Object { $_.Name -match '(?i)wi-?fi|wireless|wlan|802\.11' -or $_.ConfigManagerErrorCode -eq 28 }
        if (-not $w.Count -and -not @($bad).Count) { return (New-TSCheck $true (TT 'No WiFi adapter found - the WiFi driver is missing or WiFi is switched off in hardware.' 'WiFi adapter सापडला नाही - WiFi driver नाही किंवा WiFi hardware switch बंद.' 'WiFi एडेप्टर नहीं मिला - WiFi ड्राइवर नहीं है या हार्डवेयर स्विच बंद है।') @{ None = $true }) }
        if (@($bad).Count -or ($w | Where-Object Status -eq 'Disabled') -or -not $svc -or $svc.Status -ne 'Running') { return (New-TSCheck $true (TT 'The WiFi adapter or the WLAN service is not working.' 'WiFi adapter किंवा WLAN service काम करत नाही.' 'WiFi एडेप्टर या WLAN सर्विस काम नहीं कर रही।') @{ Bad = $bad }) }
        if ($w | Where-Object Status -eq 'Up') { return (New-TSCheck $false (TT 'WiFi is connected.' 'WiFi जोडलेले आहे.' 'WiFi जुड़ा है।')) }
        return (New-TSCheck $true (TT 'The WiFi adapter works but is not connected to any network.' 'WiFi adapter चालतो पण कोणत्याही network ला जोडलेला नाही.' 'WiFi एडेप्टर चालू है पर किसी नेटवर्क से नहीं जुड़ा।') @{ NotConnected = $true })
    }
    Fix = {
        param($chk)
        Step 'Starting the WiFi service and adapters'
        Set-Service WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service WlanSvc -ErrorAction SilentlyContinue
        foreach ($a in (Get-TSWirelessAdapters | Where-Object Status -eq 'Disabled')) { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
        [void](Repair-TSDevices @(Get-TSProblemDevices @('Net')))
        $after = & $script:D['wifi'].Check
        if (-not $after.Found) { return (New-TSFix $true (TT 'Fixed: WLAN service and WiFi adapter started.' 'दुरुस्त: WLAN service आणि WiFi adapter सुरू केले.' 'ठीक किया: WLAN सर्विस और WiFi एडेप्टर चालू किए।')) }
        if ($after.Data -and $after.Data.NotConnected) { return (New-TSFix $true (TT 'WiFi is working now - connect to your network from the taskbar WiFi icon.' 'WiFi चालू झाले - taskbar वरच्या WiFi icon मधून network निवडून connect करा.' 'WiFi चालू हो गया - टास्कबार के WiFi आइकन से नेटवर्क चुनकर जोड़ें।')) }
        return (New-TSFix $false (TT 'WiFi adapter still missing.' 'WiFi adapter अजून दिसत नाही.' 'WiFi एडेप्टर अभी भी नहीं दिख रहा।') -Manual (TT 'Check the WiFi key (Fn+F2/F12) and Airplane mode; then install the WiFi driver: Repair -> Drivers (works offline from the USB).' 'WiFi key (Fn+F2/F12) आणि Airplane mode तपासा; मग WiFi driver install करा: दुरुस्ती -> Drivers (USB वरून internet शिवाय).' 'WiFi की (Fn+F2/F12) और Airplane mode देखें; फिर WiFi ड्राइवर डालें: Repair -> Drivers (USB से बिना इंटरनेट)।'))
    }
}

$script:D['slow-pc'] = @{
    Check = {
        Step 'Measuring what slows this PC down' 'PC कशामुळे हळू आहे ते मोजत आहे...'
        $s = Invoke-PDScan -DataDir (Get-TSDataDir)
        $safe = @(Get-PDSafeStartupToDisable -Items $s.Startup -DataDir (Get-TSDataDir) -RamGB $s.Info.RAMGB)
        $junk = [double]$s.TempBytes
        $why = @()
        if ($safe.Count) { $why += "$($safe.Count) startup programs" }
        if ($junk -ge 1GB) { $why += "$(Format-PDSize $junk) junk" }
        if ($s.Info.SysFreePct -lt 15) { $why += 'C: almost full' }
        if (@($s.Bloat | Where-Object Default).Count) { $why += 'bloatware' }
        if ($s.Score -lt 80 -or $why.Count) { return (New-TSCheck $true (TT ("Health score $($s.Score)/100: " + ($why -join ', ')) ("Health score $($s.Score)/100: " + ($why -join ', ')) $null) @{ Scan = $s; Safe = $safe }) }
        return (New-TSCheck $false (TT "Health score $($s.Score)/100 - nothing slowing it down was found." "Health score $($s.Score)/100 - हळू करणारे काही सापडले नाही." "Health score $($s.Score)/100 - धीमा करने वाला कुछ नहीं मिला।") @{ Scan = $s })
    }
    Fix = {
        param($chk)
        $s = $chk.Data.Scan
        New-TSRestorePointOnce
        $did = @()
        $junk = Clear-PDJunk; $did += "$(Format-PDSize $junk.Freed) junk cleaned"
        foreach ($it in $chk.Data.Safe) { Set-PDStartupState -Item $it -Enabled $false }
        if (@($chk.Data.Safe).Count) { $did += "$(@($chk.Data.Safe).Count) startup programs off" }
        $sd = @($s.Info.Disks | Where-Object { $_.IsSystem })[0]
        if ($s.Info.RAMGB -lt 7.5 -or ($sd -and $sd.MediaType -eq 'HDD') -or -not $s.Info.HasDedicatedGPU) { Set-PDVisualPerformance; $did += 'lighter visual effects' }
        Set-PDPowerPlan -IsLaptop $s.Info.IsLaptop; Disable-PDSuggestions
        Optimize-PDServices -DataDir (Get-TSDataDir) -SystemOnHdd ([bool]($sd -and $sd.MediaType -eq 'HDD')) -RamGB $s.Info.RAMGB
        $bl = @($s.Bloat | Where-Object { $_.Default } | ForEach-Object { $_.Package })
        if ($bl.Count) { Remove-PDBloat -Packages $bl; $did += "$($bl.Count) bloatware apps removed" }
        $hw = @()
        if ($s.Info.RAMGB -lt 7.5) { $hw += TT "only $($s.Info.RAMGB) GB RAM" "फक्त $($s.Info.RAMGB) GB RAM" "सिर्फ $($s.Info.RAMGB) GB RAM" }
        if ($sd -and $sd.MediaType -eq 'HDD') { $hw += TT 'Windows on a hard disk (HDD)' 'Windows hard disk (HDD) वर' 'Windows हार्ड डिस्क (HDD) पर' }
        $man = if ($hw.Count) { TT ('For a big difference upgrade the hardware: ' + (($hw | ForEach-Object { $_.en }) -join ', ') + ' -> 8 GB RAM / SSD.') ('मोठ्या फरकासाठी hardware upgrade: ' + (($hw | ForEach-Object { $_.mr }) -join ', ') + ' -> 8 GB RAM / SSD.') ('बड़े फर्क के लिए हार्डवेयर अपग्रेड: ' + (($hw | ForEach-Object { $_.hi }) -join ', ') + ' -> 8 GB RAM / SSD.') } else { $null }
        return (New-TSFix $true (TT ('Optimized: ' + ($did -join ', ') + '. Restart the PC for the full effect.') ('वेग वाढवला: ' + ($did -join ', ') + '. पूर्ण फरकासाठी PC restart करा.') ('तेज किया: ' + ($did -join ', ') + '. पूरे असर के लिए PC रीस्टार्ट करें।')) -Restart -Manual $man)
    }
    NoVerify = $true
}
$script:D['slow-boot'] = $script:D['slow-pc']
$script:D['disk-100'] = $script:D['slow-pc']

$script:D['disk-full'] = @{
    Check = {
        $v = Get-Volume -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction SilentlyContinue
        $pct = if ($v.Size) { 100 * $v.SizeRemaining / $v.Size } else { 100 }
        $txt = "C: $(Format-PDSize $v.SizeRemaining) free of $(Format-PDSize $v.Size) ($([math]::Round($pct))%)"
        if ($pct -lt 15 -or $v.SizeRemaining -lt 15GB) { return (New-TSCheck $true (TT "C: drive is almost full: $txt." "C: drive जवळपास भरलेला: $txt." "C: ड्राइव लगभग भरी: $txt।")) }
        return (New-TSCheck $false (TT "C: has enough space: $txt." "C: वर पुरेशी जागा: $txt." "C: पर पर्याप्त जगह: $txt।"))
    }
    Fix = {
        New-TSRestorePointOnce
        $j = Clear-PDJunk -ComponentStore
        $txt = TT "Cleaned $(Format-PDSize $j.Freed) of junk (temp files, old updates, browser cache, Windows.old). Now $(Format-PDSize $j.FreeAfter) free." "$(Format-PDSize $j.Freed) junk साफ केले (temp, जुने updates, browser cache, Windows.old). आता $(Format-PDSize $j.FreeAfter) मोकळे." "$(Format-PDSize $j.Freed) जंक साफ किया। अब $(Format-PDSize $j.FreeAfter) खाली।"
        $after = & $script:D['disk-full'].Check
        if (-not $after.Found) { return (New-TSFix $true $txt) }
        return (New-TSFix $false $txt -Manual (TT 'Still low: move Downloads / Videos / Pictures to another drive from the "C: drive space" page (safe, with Undo).' 'अजून जागा कमी: "C: drive जागा" page वरून Downloads / Videos / Pictures दुसऱ्या drive वर हलवा (सुरक्षित, Undo सह).' 'अभी भी कम: "C: drive space" पेज से Downloads / Videos दूसरे ड्राइव पर ले जाएँ।'))
    }
}

$script:D['bsod'] = @{
    Check = {
        $n = Get-TSEventCount 'System' @(1001) $null 30
        $n2 = Get-TSEventCount 'System' @(41) 'Microsoft-Windows-Kernel-Power' 30
        if ($n -or $n2 -ge 2) { return (New-TSCheck $true (TT "Last 30 days: $n blue screens, $n2 sudden restarts." "मागच्या 30 दिवसांत: $n blue screen, $n2 वेळा अचानक restart." "पिछले 30 दिन: $n ब्लू स्क्रीन, $n2 बार अचानक रीस्टार्ट।")) }
        return (New-TSCheck $false (TT 'No blue screens or sudden restarts in the last 30 days.' 'मागच्या 30 दिवसांत blue screen / अचानक restart नाहीत.' 'पिछले 30 दिनों में कोई ब्लू स्क्रीन नहीं।'))
    }
    Fix = {
        Step 'Finding the cause of the crashes'
        $r = Invoke-TGAuto -Handler 'crashes' -UsbRoot $global:PDCtx.UsbRoot -P @{ ReportDir = $global:PDCtx.ReportDir }
        $cause = ($r.LinesEn | Where-Object { $_ -match '^• ' } | Select-Object -First 2) -join '; '
        $generic = -not $cause -or $cause -match 'ntoskrnl|ntkrnlmp|hal\.'
        if ($generic) {
            Step 'Repairing Windows system files (DISM + SFC)' 'Windows system files दुरुस्त करत आहे (DISM + SFC)...'
            New-TSRestorePointOnce
            $os = Invoke-PDRepairOS
            return (New-TSFix $null (TT "Crashes point to Windows itself / RAM. Repaired system files (DISM: $($os.Dism); SFC: $($os.Sfc))." "Crash चे कारण Windows / RAM कडे. System files दुरुस्त केल्या (DISM: $($os.Dism); SFC: $($os.Sfc))." "क्रैश का कारण Windows / RAM। सिस्टम फ़ाइलें ठीक कीं।") -Restart -Manual (TT 'If blue screens continue: test the RAM (Tools guide -> Windows Memory Diagnostic or MemTest86+ from the USB) and the disk.' 'Blue screen चालू राहिल्यास: RAM तपासा (Tools मार्गदर्शक -> Windows Memory Diagnostic किंवा USB वरून MemTest86+) आणि disk.' 'ब्लू स्क्रीन जारी रहे तो RAM और डिस्क जाँचें (MemTest86+)।'))
        }
        return (New-TSFix $false (TT "Cause found: $cause" "कारण सापडले: $cause" "कारण मिला: $cause") -Manual (TT 'Install a fresh driver for that device from the maker''s website (or Repair -> Drivers), then watch for new blue screens.' 'त्या device चा नवीन driver कंपनीच्या website वरून install करा (किंवा दुरुस्ती -> Drivers).' 'उस डिवाइस का नया ड्राइवर कंपनी की वेबसाइट से डालें।'))
    }
}
$script:D['shutdown'] = @{
    Check = {
        $kp = Get-TSEventCount 'System' @(41) 'Microsoft-Windows-Kernel-Power' 30
        $c = Get-TGThermalC
        if ($kp -ge 2 -or ($null -ne $c -and $c -ge 85)) { return (New-TSCheck $true (TT "$kp sudden power-offs in 30 days$(if ($null -ne $c) { "; temperature now $c°C" })." "30 दिवसांत $kp वेळा अचानक बंद$(if ($null -ne $c) { "; आत्ता तापमान $c°C" })." "30 दिनों में $kp बार अचानक बंद$(if ($null -ne $c) { "; तापमान $c°C" })।") @{ Temp = $c }) }
        return (New-TSCheck $false (TT 'No sudden shutdowns recorded recently.' 'अलीकडे अचानक बंद पडल्याची नोंद नाही.' 'हाल में अचानक बंद होने का रिकॉर्ड नहीं।'))
    }
    Fix = {
        param($chk)
        Set-PDPowerPlan -IsLaptop ([bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue))
        return (New-TSFix $false (TT 'Balanced power plan set. Sudden power-offs are usually hardware: overheating, the charger / battery or the power supply.' 'योग्य power plan लावला. अचानक बंद पडणे बहुतेक hardware मुळे: गरम होणे, charger / battery किंवा power supply.' 'पावर प्लान ठीक किया। अचानक बंद होना अक्सर हार्डवेयर से: गर्मी, चार्जर / बैटरी या पावर सप्लाई।') -Manual (TT 'Clean the fan / heatsink, check the charger and battery (Tools guide -> Battery), run the 10-minute stress test.' 'Fan / heatsink साफ करा, charger आणि battery तपासा (Tools मार्गदर्शक -> Battery), 10 मिनिटांचा stress test करा.' 'पंखा साफ करें, चार्जर और बैटरी जाँचें, 10 मिनट का stress test करें।'))
    }
}
$script:D['overheat'] = @{
    Check = {
        $c = Get-TGThermalC
        $thr = Get-TSEventCount 'System' @(37) 'Microsoft-Windows-Kernel-Processor-Power' 7
        $top = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.CPU -and $_.Name -notmatch '^(System|Idle|svchost|csrss|dwm|MsMpEng)$' } | Sort-Object CPU -Descending | Select-Object -First 1
        if (($null -ne $c -and $c -ge 80) -or $thr -ge 1) { return (New-TSCheck $true (TT "Overheating: $(if ($null -ne $c) { "$c°C now, " })$thr slow-downs from heat this week." "गरम होतो: $(if ($null -ne $c) { "आत्ता $c°C, " })या आठवड्यात गरमीमुळे $thr वेळा वेग कमी झाला." "गर्म हो रहा है: $(if ($null -ne $c) { "$c°C, " })इस हफ्ते $thr बार गर्मी से धीमा हुआ।") @{ Top = $top }) }
        if ($null -eq $c) { return (New-TSCheck $null (TT 'This PC does not report its temperature to Windows.' 'हा PC Windows ला तापमान सांगत नाही.' 'यह PC तापमान नहीं बताता।')) }
        return (New-TSCheck $false (TT "Temperature is normal ($c°C)." "तापमान सामान्य ($c°C)." "तापमान सामान्य ($c°C)।"))
    }
    Fix = {
        param($chk)
        Set-PDPowerPlan -IsLaptop ([bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue))
        $hog = if ($chk.Data -and $chk.Data.Top) { " Heaviest program: $($chk.Data.Top.Name)." } else { '' }
        return (New-TSFix $false (TT "Balanced power plan set.$hog" "योग्य power plan लावला.$hog" "पावर प्लान ठीक किया।$hog") -Manual (TT 'Heat is a hardware issue: clean the fan / heatsink, renew the thermal paste, keep the laptop on a hard surface. Tools guide -> HWiNFO shows the temperatures.' 'गरम होणे hardware ची समस्या: fan / heatsink साफ करा, thermal paste बदला, laptop कठीण पृष्ठभागावर ठेवा. Tools मार्गदर्शक -> HWiNFO मध्ये तापमान दिसते.' 'गर्मी हार्डवेयर समस्या है: पंखा / हीटसिंक साफ करें, thermal paste बदलें।'))
    }
}
$script:D['battery'] = @{
    Check = {
        $r = Invoke-TGAuto -Handler 'battery' -UsbRoot $global:PDCtx.UsbRoot -P @{}
        if ($r.Status -eq 'info') { return (New-TSCheck $null (TT 'No battery found (desktop PC).' 'Battery सापडली नाही (desktop PC).' 'बैटरी नहीं मिली।')) }
        if ($r.Status -in 'bad', 'warn') { return (New-TSCheck $true (TT $r.HeadEn $r.HeadMr $null) @{ R = $r }) }
        return (New-TSCheck $false (TT $r.HeadEn $r.HeadMr $null))
    }
    Fix = { param($chk) return (New-TSFix $false (TT 'A worn battery cannot be repaired by software.' 'झिजलेली battery software ने दुरुस्त होत नाही.' 'घिसी बैटरी सॉफ्टवेयर से ठीक नहीं होती।') -Manual (TT 'Replace it with an original battery; meanwhile use battery saver and lower brightness.' 'Original battery बदला; तोपर्यंत battery saver आणि कमी brightness वापरा.' 'असली बैटरी बदलें; तब तक battery saver रखें।')) }
}

$script:D['windows-update'] = @{
    Check = {
        $fails = Get-TSEventCount 'System' @(20) 'Microsoft-Windows-WindowsUpdateClient' 30
        $off = @('wuauserv', 'BITS', 'CryptSvc') | Where-Object { (Get-Service $_ -ErrorAction SilentlyContinue).StartType -eq 'Disabled' }
        if ($fails -or $off) { return (New-TSCheck $true (TT "$fails failed update installs in 30 days$(if ($off) { "; disabled services: $($off -join ', ')" })." "30 दिवसांत $fails updates fail$(if ($off) { "; बंद services: $($off -join ', ')" })." "30 दिनों में $fails अपडेट विफल।")) }
        return (New-TSCheck $false (TT 'No failed updates recorded.' 'Update fail झाल्याची नोंद नाही.' 'कोई विफल अपडेट नहीं।'))
    }
    Fix = {
        New-TSRestorePointOnce
        foreach ($s in 'wuauserv', 'BITS', 'CryptSvc') { if ((Get-Service $s -ErrorAction SilentlyContinue).StartType -eq 'Disabled') { Set-Service $s -StartupType Manual -ErrorAction SilentlyContinue } }
        Step 'Resetting Windows Update components'
        Reset-PDWindowsUpdate
        return (New-TSFix $true (TT 'Windows Update components reset (cache cleared, services restored). Open Settings -> Windows Update -> Check for updates.' 'Windows Update components reset केले (cache साफ, services परत). Settings -> Windows Update -> Check for updates करा.' 'Windows Update रीसेट किया। Settings -> Windows Update -> Check for updates करें।'))
    }
    NoVerify = $true
}
$script:D['corrupt-windows'] = @{
    Check = {
        Step 'Checking Windows system files (SFC verify, about 10 minutes)' 'Windows system files तपासत आहे (SFC, सुमारे 10 मिनिटे)...'
        $img = 'Unknown'; try { $img = [string](Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop).ImageHealthState } catch { }
        if ($img -in 'Repairable', 'NonRepairable') { return (New-TSCheck $true (TT "Windows image: $img." "Windows image: $img." "Windows image: $img।")) }
        $out = (& "$env:WINDIR\System32\sfc.exe" /verifyonly 2>&1 | Out-String) -replace "`0", ''
        if ($out -match 'found integrity violations') { return (New-TSCheck $true (TT 'SFC found damaged system files.' 'SFC ला खराब system files सापडल्या.' 'SFC को खराब सिस्टम फ़ाइलें मिलीं।')) }
        return (New-TSCheck $false (TT 'Windows system files are healthy.' 'Windows system files ठीक आहेत.' 'Windows सिस्टम फ़ाइलें ठीक हैं।'))
    }
    Fix = {
        New-TSRestorePointOnce
        Step 'Repairing Windows system files (DISM + SFC, 15-40 minutes)' 'Windows system files दुरुस्त करत आहे (DISM + SFC, 15-40 मिनिटे)...'
        $os = Invoke-PDRepairOS
        return (New-TSFix $true (TT "System files repaired (DISM: $($os.Dism); SFC: $($os.Sfc)). Restart the PC." "System files दुरुस्त केल्या (DISM: $($os.Dism); SFC: $($os.Sfc)). PC restart करा." "सिस्टम फ़ाइलें ठीक कीं। PC रीस्टार्ट करें।") -Restart)
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
        $net = $null
        try { $w = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8; $net = [datetime]::Parse($w.Headers['Date']).ToUniversalTime() } catch { }
        if (-not $net) { return (New-TSCheck $null (TT 'Cannot compare the time without internet.' 'Internet शिवाय वेळ तपासता येत नाही.' 'इंटरनेट के बिना समय नहीं जाँच सकते।')) }
        $off = [math]::Round([math]::Abs(((Get-Date).ToUniversalTime() - $net).TotalMinutes), 1)
        if ($off -gt 2) { return (New-TSCheck $true (TT "The clock is $off minutes wrong." "घड्याळ $off मिनिटांनी चुकीचे आहे." "घड़ी $off मिनट गलत है।")) }
        return (New-TSCheck $false (TT 'The clock is correct.' 'वेळ बरोबर आहे.' 'समय सही है।'))
    }
    Fix = { $r = Invoke-PDQuickFix -Id 'time'; return (New-TSFix $r.Ok (TT $r.En $r.Mr 'इंटरनेट से समय ठीक किया।')) }
}
$script:D['taskbar'] = @{
    Check = {
        $e = @(Get-Process explorer -ErrorAction SilentlyContinue)
        if (-not $e.Count) { return (New-TSCheck $true (TT 'Explorer (taskbar / desktop) is not running.' 'Explorer (taskbar / desktop) चालू नाही.' 'Explorer (टास्कबार) नहीं चल रहा।')) }
        if ($e | Where-Object { -not $_.Responding }) { return (New-TSCheck $true (TT 'Explorer (taskbar / desktop) is not responding.' 'Explorer (taskbar / desktop) अडकला आहे.' 'Explorer अटका हुआ है।')) }
        return (New-TSCheck $null (TT 'Explorer is running; restarting it often clears taskbar / Start menu glitches.' 'Explorer चालू आहे; restart केल्याने taskbar / Start menu च्या अडचणी जातात.' 'Explorer चालू है; रीस्टार्ट से अक्सर दिक्कत जाती है।') @{ Soft = $true })
    }
    Fix = { $r = Invoke-PDQuickFix -Id 'explorer'; return (New-TSFix $true (TT $r.En $r.Mr 'टास्कबार / Explorer फिर से चालू किया।')) }
    FixEvenIfUnknown = $true
}
$script:D['search'] = @{
    Check = {
        $s = Get-Service WSearch -ErrorAction SilentlyContinue
        if (-not $s -or $s.Status -ne 'Running') { return (New-TSCheck $true (TT 'The Windows Search service is not running.' 'Windows Search service चालू नाही.' 'Windows Search सर्विस बंद है।')) }
        return (New-TSCheck $null (TT 'Search service is running; restarting it rebuilds a stuck search.' 'Search service चालू आहे; restart केल्याने अडकलेले search सुरू होते.' 'Search चालू है; रीस्टार्ट से ठीक होता है।'))
    }
    Fix = { Set-Service WSearch -StartupType Automatic -ErrorAction SilentlyContinue; $r = Invoke-PDQuickFix -Id 'search'; return (New-TSFix $r.Ok (TT $r.En $r.Mr 'Search सर्विस फिर से चालू की।')) }
    FixEvenIfUnknown = $true
}
$script:D['printer'] = @{
    Check = {
        $sp = Get-Service Spooler -ErrorAction SilentlyContinue
        $why = @()
        if (-not $sp -or $sp.Status -ne 'Running') { $why += 'print service stopped' }
        $jobs = @(); try { $jobs = @(Get-Printer -ErrorAction Stop | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue }) } catch { }
        $stuck = @($jobs | Where-Object { $_.JobStatus -match 'Error|Paused|Blocked' -or $_.SubmittedTime -lt (Get-Date).AddMinutes(-5) })
        if ($stuck.Count) { $why += "$($stuck.Count) stuck print jobs" }
        $off = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.WorkOffline })
        if ($off.Count) { $why += "offline: $(($off | ForEach-Object Name) -join ', ')" }
        if ($why.Count) { return (New-TSCheck $true (TT ('Printer problem: ' + ($why -join '; ') + '.') ('Printer समस्या: ' + ($why -join '; ') + '.') ('प्रिंटर समस्या: ' + ($why -join '; ') + '।')) @{ Off = $off }) }
        if (-not @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax' }).Count) { return (New-TSCheck $true (TT 'No real printer is installed.' 'एकही printer install केलेला नाही.' 'कोई प्रिंटर इंस्टॉल नहीं है।') @{ None = $true }) }
        return (New-TSCheck $false (TT 'Print service and queue are fine.' 'Print service आणि queue ठीक आहेत.' 'प्रिंट सर्विस ठीक है।'))
    }
    Fix = {
        param($chk)
        if ($chk.Data -and $chk.Data.None) { return (New-TSFix $false (TT 'No printer installed.' 'Printer install केलेला नाही.' 'प्रिंटर इंस्टॉल नहीं।') -Manual (TT 'Connect the printer and install its driver from the maker''s website (Settings -> Printers -> Add device).' 'Printer जोडा आणि कंपनीच्या website वरून driver install करा (Settings -> Printers -> Add device).' 'प्रिंटर जोड़ें और कंपनी की वेबसाइट से ड्राइवर डालें।')) }
        $r = Invoke-PDQuickFix -Id 'printer'
        foreach ($p in @($chk.Data.Off)) { try { $p.WorkOffline = $false; Set-CimInstance -InputObject $p -ErrorAction Stop } catch { } }
        return (New-TSFix $r.Ok (TT ($r.En + $(if (@($chk.Data.Off).Count) { ' Offline printers set back online.' })) ($r.Mr + $(if (@($chk.Data.Off).Count) { ' Offline printer पुन्हा online केले.' })) 'प्रिंट कतार साफ कर सर्विस फिर चालू की।'))
    }
}
$script:D['printer'].Verify = {
    $sp = Get-Service Spooler -ErrorAction SilentlyContinue
    $jobs = @(); try { $jobs = @(Get-Printer -ErrorAction Stop | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue } | Where-Object { $_.JobStatus -match 'Error|Paused|Blocked' }) } catch { }
    if (-not $sp -or $sp.Status -ne 'Running' -or $jobs.Count) { return (New-TSCheck $true (TT 'Print service / queue still not working.' 'Print service / queue अजून चालत नाही.' 'प्रिंट सर्विस अभी भी नहीं चल रही।')) }
    return (New-TSCheck $false (TT 'Print service running, queue clear.' 'Print service चालू, queue रिकामी.' 'प्रिंट सर्विस चालू।'))
}
$script:D['sound'] = @{
    Check = {
        $why = @()
        foreach ($s in 'Audiosrv', 'AudioEndpointBuilder') { if ((Get-Service $s -ErrorAction SilentlyContinue).Status -ne 'Running') { $why += "$s stopped" } }
        $bad = Get-TSProblemDevices @('MEDIA', 'AudioEndpoint')
        if (@($bad).Count) { $why += "$(@($bad).Count) audio devices with errors" }
        $ep = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -eq 'OK')
        if (-not $ep.Count) { $why += 'no working audio output' }
        if ($why.Count) { return (New-TSCheck $true (TT ('Sound problem: ' + ($why -join '; ')) ('आवाजाची समस्या: ' + ($why -join '; ')) ('आवाज़ की समस्या: ' + ($why -join '; '))) @{ Bad = $bad; NoEp = (-not $ep.Count) }) }
        return (New-TSCheck $null (TT 'Audio services and devices work; restarting audio clears most "no sound" issues. Also check mute / the output device.' 'Audio services आणि devices चालू; audio restart केल्याने बहुतेक आवाजाच्या अडचणी जातात. Mute / output device पण तपासा.' 'ऑडियो ठीक है; रीस्टार्ट से अक्सर ठीक होता है। Mute भी देखें।'))
    }
    Fix = {
        param($chk)
        [void](Repair-TSDevices @(Get-TSProblemDevices @('MEDIA', 'AudioEndpoint')))
        $r = Invoke-PDQuickFix -Id 'audio'
        $after = & $script:D['sound'].Check
        if ($after.Found -eq $true -and $after.Data.NoEp) { return (New-TSFix $false (TT 'Audio services restarted, but no working sound device.' 'Audio services पुन्हा सुरू केल्या, पण आवाजाचे device काम करत नाही.' 'ऑडियो सर्विस चालू की, पर साउंड डिवाइस काम नहीं कर रहा।') -Manual (TT 'Install the audio driver: Repair -> Drivers (Realtek / Intel audio).' 'Audio driver install करा: दुरुस्ती -> Drivers (Realtek / Intel audio).' 'ऑडियो ड्राइवर डालें: Repair -> Drivers।')) }
        return (New-TSFix $true (TT $r.En $r.Mr 'ऑडियो सर्विस फिर से चालू कीं। सही डिवाइस चुनें।'))
    }
    FixEvenIfUnknown = $true
}
$script:D['display'] = @{
    Check = {
        $basic = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Basic Display|Basic Render' })
        $bad = Get-TSProblemDevices @('Display', 'Monitor')
        if ($basic.Count -or @($bad).Count) { return (New-TSCheck $true (TT 'No proper display driver (Microsoft Basic Display Adapter) - resolution and brightness will not work.' 'योग्य display driver नाही (Basic Display Adapter) - resolution आणि brightness चालणार नाही.' 'सही डिस्प्ले ड्राइवर नहीं - resolution और brightness नहीं चलेगी।')) }
        return (New-TSCheck $false (TT 'The display driver is installed.' 'Display driver आहे.' 'डिस्प्ले ड्राइवर है।'))
    }
    Fix = {
        [void](Repair-TSDevices @(Get-TSProblemDevices @('Display', 'Monitor')))
        $after = & $script:D['display'].Check
        if (-not $after.Found) { return (New-TSFix $true (TT 'Display driver installed from Windows'' own driver store.' 'Windows कडच्या drivers मधून display driver install केला.' 'Windows के ड्राइवर स्टोर से डिस्प्ले ड्राइवर डाला।')) }
        return (New-TSFix $false (TT 'Windows has no display driver for this PC.' 'Windows कडे या PC चा display driver नाही.' 'Windows के पास इस PC का डिस्प्ले ड्राइवर नहीं।') -Manual (TT 'Install it from the laptop / graphics maker''s website, or Repair -> Drivers (offline packs on the USB).' 'Laptop / graphics कंपनीच्या website वरून, किंवा दुरुस्ती -> Drivers (USB वरचे offline packs).' 'कंपनी की वेबसाइट से या Repair -> Drivers से डालें।'))
    }
}
foreach ($pair in @(@('keyboard', @('Keyboard', 'Mouse', 'HIDClass')), @('usb', @('USB', 'USBDevice', 'DiskDrive', 'WPD', 'SCSIAdapter')), @('bluetooth', @('Bluetooth')), @('camera', @('Camera', 'Image')), @('drivers', $null))) {
    $id = $pair[0]; $cls = $pair[1]
    $script:D[$id] = @{
        Classes = $cls
        Check = $ExecutionContext.SessionState.Module.NewBoundScriptBlock([scriptblock]::Create(@"
`$bad = Get-TSProblemDevices $(if ($cls) { "@('" + ($cls -join "','") + "')" } else { '$null' })
`$extra = @()
if ('$id' -eq 'bluetooth' -and (Get-Service bthserv -ErrorAction SilentlyContinue).Status -ne 'Running') { `$extra += 'Bluetooth service stopped' }
if ('$id' -eq 'camera' -and (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' -Name Value -ErrorAction SilentlyContinue).Value -eq 'Deny') { `$extra += 'camera blocked in privacy settings' }
if ('$id' -eq 'keyboard' -and (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status' -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 0) { `$extra += 'touchpad switched off' }
`$n = @(`$bad).Count
if (`$n -or `$extra.Count) {
    `$names = ((@(`$bad) | Select-Object -First 3 | ForEach-Object { `$_.Name + ' (code ' + `$_.ConfigManagerErrorCode + ')' }) + `$extra) -join '; '
    return (New-TSCheck `$true (TT ('Problem devices: ' + `$names) ('समस्या असलेले devices: ' + `$names) ('समस्या वाले डिवाइस: ' + `$names)) @{ Bad = `$bad })
}
return (New-TSCheck `$false (TT 'All these devices work.' 'हे सगळे devices चालू आहेत.' 'ये सभी डिवाइस चल रहे हैं।'))
"@))
        Fix = $ExecutionContext.SessionState.Module.NewBoundScriptBlock([scriptblock]::Create(@"
param(`$chk)
New-TSRestorePointOnce
if ('$id' -eq 'bluetooth') { Set-Service bthserv -StartupType Manual -ErrorAction SilentlyContinue; [void](Invoke-PDQuickFix -Id 'bluetooth') }
if ('$id' -eq 'camera') { `$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'; if ((Get-ItemProperty `$k -Name Value -ErrorAction SilentlyContinue).Value -eq 'Deny') { `$b = Save-PDRegTree -Key `$k -Name 'webcam'; Add-PDUndo @{ Type = 'RegTree'; File = `$b; Label = 'Camera privacy' }; Set-ItemProperty `$k -Name Value -Value 'Allow' } }
if ('$id' -eq 'keyboard') { `$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status'; if ((Get-ItemProperty `$k -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 0) { Set-ItemProperty `$k -Name Enabled -Value 1 } }
`$did = Repair-TSDevices @(`$chk.Data.Bad)
`$after = & `$script:D['$id'].Check
if (-not `$after.Found) { return (New-TSFix `$true (TT 'Fixed: devices restarted / enabled and drivers picked from Windows'' driver store.' 'दुरुस्त: devices पुन्हा सुरू / चालू केले आणि Windows कडचे drivers लावले.' 'ठीक किया: डिवाइस फिर चालू किए और ड्राइवर लगाए।')) }
`$left = @(`$after.Data.Bad)
`$nod = @(`$left | Where-Object { `$_.ConfigManagerErrorCode -eq 28 }).Count
return (New-TSFix `$false (TT ("Still not working: " + ((`$left | Select-Object -First 3 | ForEach-Object Name) -join ', ')) ("अजून चालत नाही: " + ((`$left | Select-Object -First 3 | ForEach-Object Name) -join ', ')) ("अभी भी नहीं चल रहा: " + ((`$left | Select-Object -First 3 | ForEach-Object Name) -join ', '))) -Manual (TT 'Install the missing driver: Repair -> Drivers (offline packs on the USB) or the maker''s website.' 'हरवलेला driver install करा: दुरुस्ती -> Drivers (USB वरचे offline packs) किंवा कंपनीची website.' 'ड्राइवर डालें: Repair -> Drivers या कंपनी की वेबसाइट।'))
"@))
    }
}

$script:D['disk-failing'] = @{
    Check = {
        $r = Invoke-TGAuto -Handler 'disk-health' -UsbRoot $global:PDCtx.UsbRoot -P @{}
        if ($r.Status -in 'bad', 'warn') { return (New-TSCheck $true (TT ($r.HeadEn + ': ' + (($r.LinesEn | Select-Object -First 2) -join ' ')) ($r.HeadMr + ': ' + (($r.LinesMr | Select-Object -First 2) -join ' ')) $null)) }
        return (New-TSCheck $false (TT 'All disks are healthy.' 'सगळे disks ठीक आहेत.' 'सभी डिस्क ठीक हैं।'))
    }
    Fix = { return (New-TSFix $false (TT 'A failing disk cannot be repaired by software.' 'खराब होणारी disk software ने दुरुस्त होत नाही.' 'खराब डिस्क सॉफ्टवेयर से ठीक नहीं होती।') -Manual (TT 'Copy important data to another disk now, then replace the disk.' 'महत्त्वाचा data लगेच दुसऱ्या disk वर copy करा, मग disk बदला.' 'ज़रूरी डेटा तुरंत दूसरी डिस्क पर कॉपी करें, फिर डिस्क बदलें।')) }
}
$script:D['ram'] = @{
    Check = {
        $gb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $md = $null; try { $md = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction Stop } catch { }
        if ($md -and $md.Id -ne 1201) { return (New-TSCheck $true (TT 'The last RAM test found errors.' 'मागच्या RAM test मध्ये errors सापडल्या.' 'पिछले RAM टेस्ट में गलतियाँ मिलीं।') @{ Bad = $true }) }
        if ($gb -lt 7.5) { return (New-TSCheck $true (TT "Only $gb GB RAM." "फक्त $gb GB RAM." "सिर्फ $gb GB RAM।") @{ Low = $gb }) }
        return (New-TSCheck $false (TT "$gb GB RAM, no RAM errors recorded." "$gb GB RAM, RAM errors ची नोंद नाही." "$gb GB RAM, कोई गलती नहीं।"))
    }
    Fix = { param($chk) if ($chk.Data.Bad) { return (New-TSFix $false (TT 'Faulty RAM.' 'RAM खराब.' 'RAM खराब।') -Manual (TT 'Test the sticks one at a time (MemTest86+ from the USB) and replace the faulty one.' 'Sticks एक-एक काढून test करा (USB वरून MemTest86+) आणि खराब बदला.' 'एक-एक स्टिक जाँचें और खराब बदलें।')) }
        return (New-TSFix $false (TT 'Low RAM makes the PC slow.' 'कमी RAM मुळे PC हळू.' 'कम RAM से PC धीमा।') -Manual (TT 'Add RAM (8 GB or more). Tools guide -> CPU-Z -> "Check automatically" tells which RAM to buy.' 'RAM वाढवा (8 GB किंवा जास्त). Tools मार्गदर्शक -> CPU-Z -> "आपोआप तपासा" कोणती RAM घ्यायची ते सांगते.' 'RAM बढ़ाएँ (8 GB+)।')) }
}

$script:D['virus'] = @{
    Check = {
        Step 'Checking antivirus status and malware settings'
        $why = @()
        $st = $null; try { $st = Get-MpComputerStatus -ErrorAction Stop } catch { }
        if ($st -and -not $st.RealTimeProtectionEnabled) { $why += 'Defender real-time protection is off' }
        if ($st -and $st.AntivirusSignatureAge -gt 7) { $why += "virus definitions $($st.AntivirusSignatureAge) days old" }
        $thr = @(); try { $thr = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.ThreatStatusID -notin 2, 3, 4, 6 }) } catch { }
        if ($thr.Count) { $why += "$($thr.Count) active threats" }
        $reg = @(Get-PDRegistryIssues | Where-Object { $_.Kind -eq 'malware' -and $_.Selected })
        if ($reg.Count) { $why += "$($reg.Count) settings changed by malware" }
        if ($why.Count) { return (New-TSCheck $true (TT ('Found: ' + ($why -join '; ')) ('सापडले: ' + ($why -join '; ')) ('मिला: ' + ($why -join '; '))) @{ Reg = $reg }) }
        return (New-TSCheck $null (TT 'Antivirus is on and no malware settings were found; a quick scan will confirm.' 'Antivirus चालू आहे आणि virus चे बदल सापडले नाहीत; quick scan करून खात्री करतो.' 'एंटीवायरस चालू है; quick scan से पक्का करेंगे।') @{ Reg = @() })
    }
    Fix = {
        param($chk)
        New-TSRestorePointOnce
        $did = @()
        if (@($chk.Data.Reg).Count) { $r = Repair-PDRegistryIssues -Issues $chk.Data.Reg -NoRestorePoint; $did += "$($r.Fixed) malware settings reverted" }
        Step 'Turning on Defender, updating definitions, quick scan (several minutes)'
        try { Repair-PDDefender } catch { }
        try { Update-MpSignature -ErrorAction Stop; $did += 'definitions updated' } catch { }
        try { Start-MpScan -ScanType QuickScan -ErrorAction Stop; $did += 'quick scan done' } catch { }
        $thr = @(); try { $thr = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.ThreatStatusID -notin 2, 3, 4, 6 }) } catch { }
        if ($thr.Count) { try { Remove-MpThreat -ErrorAction Stop; $did += "$($thr.Count) threats removed" } catch { } }
        $left = @(); try { $left = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.ThreatStatusID -notin 2, 3, 4, 6 }) } catch { }
        if ($left.Count) { return (New-TSFix $false (TT ('Done: ' + ($did -join ', ') + '; some threats remain.') ('केले: ' + ($did -join ', ') + '; काही threats अजून आहेत.') ('किया: ' + ($did -join ', '))) -Manual (TT 'Boot from the USB -> Kaspersky Rescue Disk for a full clean outside Windows.' 'USB वरून boot -> Kaspersky Rescue Disk ने Windows बाहेरून पूर्ण साफ करा.' 'USB से boot -> Kaspersky Rescue Disk से पूरा साफ करें।')) }
        return (New-TSFix $true (TT ('Done: ' + ($did -join ', ') + '; no active threats left.') ('केले: ' + ($did -join ', ') + '; आता कोणतेही virus नाहीत.') ('किया: ' + ($did -join ', ') + '; कोई सक्रिय वायरस नहीं।')))
    }
    FixEvenIfUnknown = $true
    NoVerify = $true
}
$script:D['browser'] = $script:D['virus']
$script:D['task-manager'] = @{
    Check = {
        $reg = @(Get-PDRegistryIssues | Where-Object { $_.Kind -eq 'malware' })
        if ($reg.Count) { return (New-TSCheck $true (TT ('Blocked / changed by malware: ' + (($reg | Select-Object -First 3 | ForEach-Object Title) -join '; ')) ('Virus ने बंद / बदललेले: ' + (($reg | Select-Object -First 3 | ForEach-Object Title) -join '; ')) $null) @{ Reg = $reg }) }
        return (New-TSCheck $false (TT 'No blocked tools or malware settings found.' 'बंद केलेली tools / virus चे बदल सापडले नाहीत.' 'कोई बंद टूल नहीं मिला।'))
    }
    Fix = { param($chk) New-TSRestorePointOnce; $r = Repair-PDRegistryIssues -Issues $chk.Data.Reg -NoRestorePoint; return (New-TSFix ($r.Fixed -gt 0) (TT "Reverted $($r.Fixed) settings changed by malware (backup + Undo kept). Run a virus scan too." "Virus ने बदललेल्या $($r.Fixed) settings परत केल्या (backup + Undo). Virus scan पण करा." "$($r.Fixed) सेटिंग्स वापस कीं।")) }
}
$script:D['activation'] = @{
    Check = {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lic -and $lic.LicenseStatus -eq 1) { return (New-TSCheck $false (TT 'Windows is activated.' 'Windows activate आहे.' 'Windows सक्रिय है।')) }
        $key = (Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3xOriginalProductKey
        return (New-TSCheck $true (TT "Windows is not activated$(if ($key) { '; a key is stored in the BIOS' })." "Windows activate नाही$(if ($key) { '; BIOS मध्ये key आहे' })." "Windows सक्रिय नहीं है।") @{ Key = $key })
    }
    Fix = {
        param($chk)
        if ($chk.Data.Key) {
            $slmgr = "$env:WINDIR\System32\slmgr.vbs"
            $null = & cscript.exe //nologo $slmgr /ipk $chk.Data.Key 2>&1
            $null = & cscript.exe //nologo $slmgr /ato 2>&1
            $after = & $script:D['activation'].Check
            if (-not $after.Found) { return (New-TSFix $true (TT 'Activated with the key stored in the BIOS.' 'BIOS मधल्या key ने activate केले.' 'BIOS की key से सक्रिय किया।')) }
        }
        return (New-TSFix $false (TT 'Could not activate automatically.' 'आपोआप activate झाले नाही.' 'अपने आप सक्रिय नहीं हुआ।') -Manual (TT 'Settings -> Activation -> Troubleshoot, or enter a genuine key. Never use cracks / activators.' 'Settings -> Activation -> Troubleshoot, किंवा original key टाका. Crack / activator कधीही वापरू नका.' 'Settings -> Activation -> Troubleshoot; crack कभी न वापरें।'))
    }
}

# ------------------------------------------------------------------ runner
function Get-PDTroubleshootable { return @($script:D.Keys) }

function Invoke-PDTroubleshoot {
    param([Parameter(Mandatory)][string[]]$Ids, [Parameter(Mandatory)][object[]]$Problems)
    $script:RpDone = $false
    $log = New-Object System.Collections.ArrayList
    $res = [pscustomobject]@{ Issue = $null; Check = $null; Fix = $null; Checked = @(); Guide = @(); Restart = $false; Resolved = $false }
    foreach ($id in ($Ids | Select-Object -Unique)) {
        if ($global:PDState -and $global:PDState.Cancel) { break }
        $p = $Problems | Where-Object { $_.id -eq $id } | Select-Object -First 1
        $d = $script:D[$id]
        if (-not $d) { $res.Guide += [pscustomobject]@{ Id = $id; Problem = $p; Text = (Get-TSManual $p) }; continue }
        Write-PDLog "Checking: $($p.en.title)" 'STEP'
        $chk = $null
        try { $chk = & $d.Check } catch { Write-PDLog "check $id failed: $($_.Exception.Message)" 'WARN'; continue }
        $res.Checked += [pscustomobject]@{ Id = $id; Problem = $p; Check = $chk }
        if ($chk.Found -eq $false) { Write-PDLog ("  OK: " + $chk.Text.en) 'OK'; continue }
        if ($null -eq $chk.Found -and -not $d.FixEvenIfUnknown) { $res.Guide += [pscustomobject]@{ Id = $id; Problem = $p; Text = $chk.Text }; continue }
        Write-PDLog ("  Found: " + $chk.Text.en) 'WARN'
        $fix = $null
        try { $fix = & $d.Fix $chk } catch { $fix = New-TSFix $false (TT "Repair failed: $($_.Exception.Message)" "दुरुस्ती अयशस्वी: $($_.Exception.Message)" $null) }
        if ($fix.Fixed -eq $true -and -not $d.NoVerify -and -not $fix.Restart) {
            try { $v = if ($d.Verify) { & $d.Verify } else { & $d.Check }; if ($v.Found -eq $true) { $fix.Fixed = $false; $fix.Text = TT ($fix.Text.en + ' (still present after the repair)') ($fix.Text.mr + ' (दुरुस्तीनंतरही समस्या आहे)') $fix.Text.hi } } catch { }
        }
        $res.Issue = $p; $res.Check = $chk; $res.Fix = $fix; $res.Restart = $fix.Restart
        $res.Resolved = ($fix.Fixed -eq $true) -or ($null -eq $fix.Fixed -and $fix.Restart)
        Write-PDLog ("  " + $fix.Text.mr) $(if ($res.Resolved) { 'OK' } else { 'WARN' })
        if ($res.Resolved -or $fix.Manual) { break }
    }
    return $res
}

# Short summary in the chosen language
function Format-PDTroubleshoot($R, [string]$Lang = 'mr') {
    $pick = { param($t) if ($null -eq $t) { '' } elseif ($t -is [string]) { $t } else { $t.$Lang } }
    $L = @{
        en = @{ issue = 'Issue'; did = 'What was done'; result = 'Result'; ok = 'Solved.'; restart = 'Restart the PC to finish.'; manual = 'What you need to do'; none = 'No problem matching your description was found on this PC.'; checked = 'Checked'; guide = 'Suggestion' }
        mr = @{ issue = 'समस्या'; did = 'काय केले'; result = 'निकाल'; ok = 'समस्या सुटली.'; restart = 'पूर्ण होण्यासाठी PC restart करा.'; manual = 'तुम्ही करायचे'; none = 'तुम्ही सांगितलेली समस्या या PC वर सापडली नाही.'; checked = 'तपासले'; guide = 'सल्ला' }
        hi = @{ issue = 'समस्या'; did = 'क्या किया'; result = 'नतीजा'; ok = 'समस्या हल हो गई।'; restart = 'पूरा करने के लिए PC रीस्टार्ट करें।'; manual = 'आपको क्या करना है'; none = 'आपकी बताई समस्या इस PC पर नहीं मिली।'; checked = 'जाँचा'; guide = 'सुझाव' }
    }[$Lang]
    $out = @()
    if ($R.Issue) {
        $out += "$($L.issue): $($R.Issue.$($(if ($Lang -eq 'hi') { 'en' } else { $Lang })).title) - $(& $pick $R.Check.Text)"
        $out += "$($L.did): $(& $pick $R.Fix.Text)"
        $out += "$($L.result): " + $(if ($R.Fix.Fixed -eq $true -and -not $R.Restart) { $L.ok } elseif ($R.Restart) { $L.restart } else { '⚠' })
        if ($R.Fix.Manual) { $out += "$($L.manual): $(& $pick $R.Fix.Manual)" }
    } else {
        $out += $L.none
        if (@($R.Checked).Count) { $out += "$($L.checked): " + (($R.Checked | ForEach-Object { & $pick $_.Check.Text }) -join ' | ') }
        foreach ($g in ($R.Guide | Select-Object -First 1)) { if ($g.Text) { $out += "$($L.guide): $(& $pick $g.Text)" } }
    }
    return $out
}

Export-ModuleMember -Function Invoke-PDTroubleshoot, Format-PDTroubleshoot, Get-PDTroubleshootable
