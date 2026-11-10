# Sanjeevani PC Doctor - advisor: which OS suits this PC, which apps to remove / replace.
Set-StrictMode -Off

function Test-PDWin11Cpu {
    param([string]$Name)
    $n = $Name -replace '\(R\)|\(TM\)|CPU|@.*$', '' -replace '\s+', ' '
    if ($n -match 'Core\s*Ultra|Core [3579] \d{3}[A-Z]?\b|Intel\(?R?\)? (N\d{2,3})\b|i3-N3\d\d|Ryzen AI') { return $true }
    $m = [regex]::Match($n, '\bi[3579]-(\d{4,5})')
    if ($m.Success) {
        $d = $m.Groups[1].Value
        $gen = if ($d.Length -eq 5 -or $d.StartsWith('1')) { [int]$d.Substring(0, 2) } else { [int]$d.Substring(0, 1) }
        return ($gen -ge 8)
    }
    if ($n -match '\bi[3579] ?[A-Z]? ?\d{3}\b') { return $false }          # 1st gen e.g. "i5 CPU M 520"
    if ($n -match '(Pentium|Celeron)') {
        if ($n -match '\b(N4\d{3}|N5\d{3}|N6\d{3}|G5\d{3}|G6\d{3}|G7\d{3}|[4-7]\d{2}5U|6305|7305|8505)\b') { return $true }
        return $false
    }
    $r = [regex]::Match($n, 'Ryzen (?:Threadripper )?(?:\d )?(?:PRO )?(\d)(\d{3})')
    if ($r.Success) { return ([int]$r.Groups[1].Value -ge 2) }
    if ($n -match 'Athlon') {
        if ($n -match 'Athlon (Gold|Silver|PRO)? ?(3\d{3}|7\d{3}|2[0-4]0GE|3000G)') { return $true }
        return $false
    }
    if ($n -match '\b(A4|A6|A8|A9|A10|A12|FX|E1|E2|Phenom|Sempron|Turion)\b') { return $false }
    if ($n -match 'Core\(?\)? ?2|Core 2|Atom') { return $false }
    return $null
}

function Get-PDWin11Check {
    param($Info)
    $sysDisk = @($Info.Disks | Where-Object { $_.IsSystem })[0]
    $cpuOk = Test-PDWin11Cpu $Info.CPU
    $checks = @(
        [pscustomobject]@{ Name = 'CPU'; Pass = $cpuOk; Detail = $(if ($null -eq $cpuOk) { "$($Info.CPU) - " + (L 'cannot say for sure (use Microsoft PC Health Check)' 'नक्की सांगता येत नाही (Microsoft PC Health Check वापरा)' 'पक्का नहीं कह सकते (Microsoft PC Health Check इस्तेमाल करें)') } else { $Info.CPU }) }
        [pscustomobject]@{ Name = 'TPM 2.0'; Pass = ($Info.TPM.Present -and $Info.TPM.Version -like '2*'); Detail = $(if ($Info.TPM.Present) { "TPM $($Info.TPM.Version)" } else { (L 'No TPM found (try turning on fTPM / PTT in the BIOS)' 'TPM सापडला नाही (BIOS मध्ये fTPM/PTT चालू करून पहा)' 'TPM नहीं मिला (BIOS में fTPM/PTT चालू करके देखें)') }) }
        [pscustomobject]@{ Name = 'UEFI + Secure Boot'; Pass = ($Info.Firmware -eq 'UEFI' -and $Info.SecureBoot -ne 'Unsupported'); Detail = "$($Info.Firmware), Secure Boot: $($Info.SecureBoot)" }
        [pscustomobject]@{ Name = 'RAM ≥ 4 GB'; Pass = ($Info.RAMGB -ge 3.8); Detail = "$($Info.RAMGB) GB" }
        [pscustomobject]@{ Name = 'Disk ≥ 64 GB'; Pass = ($sysDisk -and $sysDisk.SizeGB -ge 64); Detail = $(if ($sysDisk) { "$($sysDisk.SizeGB) GB" } else { '?' }) }
        [pscustomobject]@{ Name = '64-bit CPU'; Pass = [bool]$Info.CPUArch64; Detail = '' }
    )
    $fail = @($checks | Where-Object { $_.Pass -eq $false }).Count
    $unknown = @($checks | Where-Object { $null -eq $_.Pass }).Count
    $ready = if ($fail -gt 0) { 'No' } elseif ($unknown -gt 0) { 'Maybe' } else { 'Yes' }
    return [pscustomobject]@{ Ready = $ready; Checks = $checks }
}

function Get-PDOSAdvice {
    param($Info, [string]$DataDir)
    $cfg = Get-Content (Join-Path $DataDir 'os-advice.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $w11 = Get-PDWin11Check $Info
    $sysDisk = @($Info.Disks | Where-Object { $_.IsSystem })[0]
    $ssd = ($sysDisk -and $sysDisk.MediaType -eq 'SSD')
    $ram = [double]$Info.RAMGB
    $recs = New-Object System.Collections.ArrayList
    $fitName = @{
        best = (L 'Best' 'सर्वोत्तम' 'सबसे अच्छा'); great = (L 'Very good' 'खूप चांगला' 'बहुत अच्छा'); ok = (L 'Works' 'चालेल' 'चलेगा'); check = (L 'Check' 'तपासा' 'जाँचें')
        temp = (L 'Temporary' 'तात्पुरता' 'अस्थायी'); no = (L 'Not recommended' 'शिफारस नाही' 'सुझाव नहीं'); unsupported = (L 'Not officially supported' 'Officially supported नाही' 'Officially supported नहीं')
        web = (L 'Good (internet work only)' 'चांगला (फक्त internet कामांसाठी)' 'अच्छा (सिर्फ़ internet कामों के लिए)'); need = (L 'Required' 'आवश्यक' 'ज़रूरी')
    }
    $fitColorId = @{ best = 'best'; great = 'great'; ok = 'ok'; check = 'check'; temp = 'temp'; no = 'no'; unsupported = 'no'; web = 'ok'; need = 'check' }
    function rec($title, $fitId, $why) { [void]$recs.Add([pscustomobject]@{ Title = $title; Fit = $fitName[$fitId]; FitId = $fitColorId[$fitId]; Why = $why }) }

    if ($w11.Ready -ne 'No') {
        if ($ram -ge 7.5 -and $ssd) { rec 'Windows 11' 'best' (L 'This PC suits Windows 11. It will get regular updates and security fixes.' 'हा PC Windows 11 साठी योग्य आहे. Updates आणि security नियमित मिळतील.' 'यह PC Windows 11 के लिए सही है। Updates और security नियमित मिलेंगे।') }
        elseif ($ram -ge 3.8) {
            $need = @($(if (-not $ssd) { 'SSD' }) + $(if ($ram -lt 7.5) { '8 GB RAM' }) | Where-Object { $_ }) -join ' + '
            rec 'Windows 11' 'ok' ((L 'Windows 11 runs, but adding {0} makes a big difference. Apply PC Doctor''s "Speed Up" tweaks.' 'Windows 11 चालेल, पण {0} लावल्यास खूप फरक पडेल. PC Doctor चे "वेग वाढवा" tweaks नक्की लावा.' 'Windows 11 चलेगा, पर {0} लगाने से बहुत फ़र्क पड़ेगा। PC Doctor के "स्पीड बढ़ाएँ" tweaks ज़रूर लगाएँ।') -f $need)
        }
        if ($w11.Ready -eq 'Maybe') { rec 'PC Health Check app' 'check' (L 'CPU support is not certain. Run Microsoft''s PC Health Check app to be sure.' 'CPU support नक्की नाही. Microsoft चे PC Health Check app चालवून खात्री करा.' 'CPU support पक्का नहीं। Microsoft का PC Health Check app चलाकर पक्का करें।') }
    } else {
        rec 'Windows 11' 'unsupported' (L 'This hardware does not meet the Windows 11 requirements. If it is forced on, updates are not guaranteed.' 'हा hardware Windows 11 च्या अटी पूर्ण करत नाही. जबरदस्तीने install केल्यास updates ची हमी नाही.' 'यह hardware Windows 11 की शर्तें पूरी नहीं करता। ज़बरदस्ती install करने पर updates की गारंटी नहीं।')
        rec ('Windows 10 (22H2) + ESU') 'temp' ((L 'A personal PC enrolled in ESU gets security updates until {0}. After that it must be replaced.' 'Personal PC ला ESU मध्ये enroll केल्यास {0} पर्यंत security updates. त्यानंतर बदलावे लागेल.' 'Personal PC को ESU में enroll करने पर {0} तक security updates. उसके बाद बदलना होगा।') -f $cfg.win10EsuConsumerEnd)
    }
    if ($ram -lt 3.8) {
        rec 'Linux Mint XFCE / Linux Lite' 'best' (L 'Light for little RAM, free and safe. Browser, Office (LibreOffice), WhatsApp Web, PDF - everything works.' 'कमी RAM साठी हलके, free आणि सुरक्षित. Browser, Office (LibreOffice), WhatsApp Web, PDF सगळे चालते.' 'कम RAM के लिए हल्का, free और सुरक्षित। Browser, Office (LibreOffice), WhatsApp Web, PDF सब चलता है।')
        rec 'Windows 10 / 11' 'no' ((L 'Windows will be very slow with {0} GB RAM.' '{0} GB RAM मध्ये Windows खूप slow चालेल.' '{0} GB RAM में Windows बहुत slow चलेगा।') -f $ram)
    } elseif ($w11.Ready -eq 'No') {
        rec ($(if ($ram -ge 6) { 'Linux Mint Cinnamon' } else { 'Linux Mint XFCE' })) 'great' (L 'Free, regular security updates, runs fast on old PCs. Looks much like Windows.' 'Free, नियमित security updates, जुन्या PC वर वेगाने चालतो. Windows सारखाच दिसतो.' 'Free, नियमित security updates, पुराने PC पर तेज़ चलता है। Windows जैसा ही दिखता है।')
        rec 'ChromeOS Flex' 'web' (L 'Google''s free OS - fast for browser-based work. Try it from a USB first.' 'Google चे free OS - browser आधारित कामांसाठी जलद. आधी USB वरून चालवून पहा.' 'Google का free OS - browser वाले कामों के लिए तेज़। पहले USB से चलाकर देखें।')
    }
    if (-not $Info.Is64Bit -and $Info.CPUArch64) { rec 'Windows 64-bit' 'need' (L 'The CPU is 64-bit but Windows is 32-bit. 64-bit Windows can use more RAM.' 'CPU 64-bit आहे पण Windows 32-bit आहे. 64-bit Windows install केल्यास जास्त RAM वापरता येते.' 'CPU 64-bit है पर Windows 32-bit है। 64-bit Windows install करने पर ज़्यादा RAM इस्तेमाल हो सकती है।') }

    $up = @()
    if (-not $ssd) { $up += (L 'Fit an SSD instead of the HDD (240-500 GB SATA SSD). It is the cheapest and biggest speed upgrade - Clonezilla / Rescuezilla can clone the old disk to the new SSD.' 'HDD ऐवजी SSD लावा (240-500 GB SATA SSD). हा सर्वात स्वस्त आणि सर्वात मोठा speed upgrade आहे - Clonezilla/Rescuezilla ने जुनी disk नवीन SSD वर clone करता येते.' 'HDD की जगह SSD लगाएँ (240-500 GB SATA SSD)। यह सबसे सस्ता और सबसे बड़ा speed upgrade है - Clonezilla/Rescuezilla से पुरानी disk नए SSD पर clone हो सकती है।') }
    if ($ram -lt 7.5) {
        $free = [int]$Info.RAMSlotsTotal - [int]$Info.RAMSlotsUsed
        $t = (L 'Increase RAM to 8 GB or more' 'RAM 8 GB किंवा जास्त करा' 'RAM 8 GB या ज़्यादा करें') + " ($($Info.RAMType)"
        if ($Info.RAMSpeed) { $t += ", $($Info.RAMSpeed) MHz" }
        $t += ')'
        if ($Info.RAMSlotsTotal -gt 0) { $t += ". Slots: $($Info.RAMSlotsUsed)/$($Info.RAMSlotsTotal) " + (L 'in use' 'वापरात' 'उपयोग में') + $(if ($free -gt 0) { " - " + ((L '{0} slot free' '{0} slot रिकामा आहे' '{0} slot खाली है') -f $free) } else { ' - ' + (L 'a bigger stick must replace one' 'नवीन मोठी stick बदलावी लागेल' 'नई बड़ी stick बदलनी होगी') }) }
        if ($Info.RAMMaxGB -gt 0) { $t += ". Max support: $($Info.RAMMaxGB) GB" }
        $up += $t
    }
    if ($Info.IsLaptop) { $up += (L 'Laptop: check battery wear with BatteryInfoView (Tools guide); clean the fan / heat sink (heat makes the CPU slow down).' 'Laptop: Tools मार्गदर्शक मधील BatteryInfoView ने battery wear तपासा; fan/heat sink साफ करा (heat मुळे CPU हळू चालतो).' 'Laptop: Tools गाइड के BatteryInfoView से battery wear जाँचें; fan/heat sink साफ़ करें (गर्मी से CPU धीमा चलता है)।') }
    return [pscustomobject]@{ Win11 = $w11; Recommendations = @($recs); Upgrades = $up; LowEnd = ($ram -lt 7.5 -or -not $ssd) }
}

function Get-PDAppAdvice {
    param([object[]]$Apps, $Info, [string]$DataDir)
    $file = Join-Path $DataDir 'apps.json'
    if (-not (Test-Path $file)) { return @() }
    $rules = (Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json).rules
    $sysDisk = @($Info.Disks | Where-Object { $_.IsSystem })[0]
    $lowEnd = ($Info.RAMGB -lt 7.5 -or ($sysDisk -and $sysDisk.MediaType -eq 'HDD'))
    $out = @()
    $avHits = @()
    foreach ($a in $Apps) {
        foreach ($r in $rules) {
            if ($a.Name -notmatch $r.match) { continue }
            if ($r.lowEndOnly -and -not $lowEnd) { break }
            $o = [pscustomobject]@{
                App = $a.Name; Kind = $r.kind; Reason = (L $r.reason_en $r.reason $r.reason_hi)
                Alternatives = ((@(L ($r.alternatives_en -join '|') ($r.alternatives -join '|') ($r.alternatives_hi -join '|')) -split '\|') -join ', '); Action = $r.action
                Uninstall = $a.Uninstall; SizeMB = $a.SizeMB
            }
            if ($r.kind -eq 'av') { $avHits += $o } else { $out += $o }
            break
        }
    }
    if ($avHits.Count -gt 0) {
        foreach ($o in $avHits) {
            if ($lowEnd -or $avHits.Count -gt 1) {
                $o.Reason = if ($avHits.Count -gt 1) { (L 'More than one antivirus - they fight each other and make the PC very slow. Keep only one.' 'एकापेक्षा जास्त antivirus - एकमेकांशी भांडतात, PC खूप slow होतो. एकच ठेवा.' 'एक से ज़्यादा antivirus - आपस में टकराते हैं, PC बहुत slow होता है। एक ही रखें।') } else { $o.Reason }
                $out += $o
            }
        }
    }
    return $out
}

function Invoke-PDUninstall {
    param([Parameter(Mandatory)][string]$UninstallString, [string]$Name)
    Write-PDLog "Opening the uninstaller: $Name (continue in its window)" 'STEP'
    $s = $UninstallString.Trim()
    if ($s -match '^(?i)"?msiexec(\.exe)?"?\s+/[IX]\s*(\{[0-9A-F\-]+\})') {
        $p = Start-Process msiexec.exe -ArgumentList "/x $($Matches[2])" -PassThru
    } elseif ($s -match '^"([^"]+)"\s*(.*)$') {
        if ($Matches[2]) { $p = Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -PassThru } else { $p = Start-Process -FilePath $Matches[1] -PassThru }
    } elseif ($s -match '^(?i)(.+?\.exe)\s*(.*)$') {
        if ($Matches[2]) { $p = Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -PassThru }
        else { $p = Start-Process -FilePath $Matches[1] -PassThru }
    } else {
        $p = Start-Process cmd.exe -ArgumentList "/c `"$s`"" -PassThru -WindowStyle Hidden
    }
    if ($p) { $p.WaitForExit() }
    Write-PDLog "$Name uninstaller closed." 'OK'
}

Export-ModuleMember -Function *
