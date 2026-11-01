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
        [pscustomobject]@{ Name = 'CPU'; Pass = $cpuOk; Detail = $(if ($null -eq $cpuOk) { "$($Info.CPU) - नक्की सांगता येत नाही (Microsoft PC Health Check वापरा)" } else { $Info.CPU }) }
        [pscustomobject]@{ Name = 'TPM 2.0'; Pass = ($Info.TPM.Present -and $Info.TPM.Version -like '2*'); Detail = $(if ($Info.TPM.Present) { "TPM $($Info.TPM.Version)" } else { 'TPM सापडला नाही (BIOS मध्ये fTPM/PTT चालू करून पहा)' }) }
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
    function rec($title, $fit, $why) { [void]$recs.Add([pscustomobject]@{ Title = $title; Fit = $fit; Why = $why }) }

    if ($w11.Ready -ne 'No') {
        if ($ram -ge 7.5 -and $ssd) { rec 'Windows 11' 'सर्वोत्तम' 'हा PC Windows 11 साठी योग्य आहे. Updates आणि security नियमित मिळतील.' }
        elseif ($ram -ge 3.8) { rec 'Windows 11' 'चालेल' ('Windows 11 चालेल, पण ' + $(if (-not $ssd) { 'SSD' } else { '' }) + $(if (-not $ssd -and $ram -lt 7.5) { ' आणि ' } else { '' }) + $(if ($ram -lt 7.5) { '8 GB RAM' } else { '' }) + ' लावल्यास खूप फरक पडेल. PC Doctor चे "Speed" tweaks नक्की लावा.') }
        if ($w11.Ready -eq 'Maybe') { rec 'PC Health Check app' 'तपासा' 'CPU support नक्की नाही. Microsoft चे PC Health Check app चालवून खात्री करा.' }
    } else {
        rec 'Windows 11' 'Officially supported नाही' 'हा hardware Windows 11 च्या अटी पूर्ण करत नाही. जबरदस्तीने install केल्यास updates ची हमी नाही.'
        rec ('Windows 10 (22H2) + ESU') 'तात्पुरता' ("Personal PC ला ESU मध्ये enroll केल्यास $($cfg.win10EsuConsumerEnd) पर्यंत security updates. त्यानंतर बदलावे लागेल.")
    }
    if ($ram -lt 3.8) {
        rec 'Linux Mint XFCE / Linux Lite' 'सर्वोत्तम' 'कमी RAM साठी हलके, free आणि सुरक्षित. Browser, Office (LibreOffice), WhatsApp Web, PDF सगळे चालते.'
        rec 'Windows 10 / 11' 'शिफारस नाही' "$ram GB RAM मध्ये Windows खूप slow चालेल."
    } elseif ($w11.Ready -eq 'No') {
        rec ($(if ($ram -ge 6) { 'Linux Mint Cinnamon' } else { 'Linux Mint XFCE' })) 'खूप चांगला' 'Free, नियमित security updates, जुन्या PC वर वेगाने चालतो. Windows सारखाच दिसतो.'
        rec 'ChromeOS Flex' 'चांगला (फक्त internet कामांसाठी)' 'Google चे free OS - browser आधारित कामांसाठी जलद. आधी USB वरून चालवून पहा.'
    }
    if (-not $Info.Is64Bit -and $Info.CPUArch64) { rec 'Windows 64-bit' 'आवश्यक' 'CPU 64-bit आहे पण Windows 32-bit आहे. 64-bit Windows install केल्यास जास्त RAM वापरता येते.' }

    $up = @()
    if (-not $ssd) { $up += 'HDD ऐवजी SSD लावा (240-500 GB SATA SSD). हा सर्वात स्वस्त आणि सर्वात मोठा speed upgrade आहे - Clonezilla/Rescuezilla ने जुनी disk नवीन SSD वर clone करता येते.' }
    if ($ram -lt 7.5) {
        $free = [int]$Info.RAMSlotsTotal - [int]$Info.RAMSlotsUsed
        $t = "RAM 8 GB किंवा जास्त करा ($($Info.RAMType)"
        if ($Info.RAMSpeed) { $t += ", $($Info.RAMSpeed) MHz" }
        $t += ')'
        if ($Info.RAMSlotsTotal -gt 0) { $t += ". Slots: $($Info.RAMSlotsUsed)/$($Info.RAMSlotsTotal) वापरात" + $(if ($free -gt 0) { " - $free slot रिकामा आहे" } else { ' - नवीन मोठी stick बदलावी लागेल' }) }
        if ($Info.RAMMaxGB -gt 0) { $t += ". Max support: $($Info.RAMMaxGB) GB" }
        $up += $t
    }
    if ($Info.IsLaptop) { $up += 'Laptop: Toolbox मधील BatteryInfoView ने battery wear तपासा; fan/heat sink साफ करा (heat मुळे CPU हळू चालतो).' }
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
                App = $a.Name; Kind = $r.kind; Reason = $r.reason
                Alternatives = ($r.alternatives -join ', '); Action = $r.action
                Uninstall = $a.Uninstall; SizeMB = $a.SizeMB
            }
            if ($r.kind -eq 'av') { $avHits += $o } else { $out += $o }
            break
        }
    }
    if ($avHits.Count -gt 0) {
        foreach ($o in $avHits) {
            if ($lowEnd -or $avHits.Count -gt 1) {
                $o.Reason = if ($avHits.Count -gt 1) { 'एकापेक्षा जास्त antivirus - एकमेकांशी भांडतात, PC खूप slow होतो. एकच ठेवा.' } else { $o.Reason }
                $out += $o
            }
        }
    }
    return $out
}

function Invoke-PDUninstall {
    param([Parameter(Mandatory)][string]$UninstallString, [string]$Name)
    Write-PDLog "Uninstaller उघडत आहे: $Name (त्याच्या window मध्ये पुढे जा)" 'STEP'
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
    Write-PDLog "$Name uninstaller बंद झाला." 'OK'
}

Export-ModuleMember -Function *
