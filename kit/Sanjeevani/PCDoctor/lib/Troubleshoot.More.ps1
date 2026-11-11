# Sanjeevani PC Doctor - more automatic checks for the Assistant (dot-sourced by Troubleshoot.psm1, shares its $script:D).
# Collected from the problems technicians see most often (Windows, apps, hardware / storage, India-specific: Aadhaar
# devices, DSC tokens, pendrive shortcut virus, activators). Same rules as Troubleshoot.psm1: CHECK first, change only
# what is really wrong, never erase data, never weaken security, never activate / crack anything.
Set-StrictMode -Off

# ------------------------------------------------------------------ shared helpers
function Get-TXEvents([string]$Log, [int[]]$Ids, [string]$Provider, [int]$Days, [int]$Max = 200) {
    $f = @{ LogName = $Log; StartTime = (Get-Date).AddDays(-$Days) }
    if ($Ids) { $f.Id = $Ids }
    if ($Provider) { $f.ProviderName = $Provider }
    try { return @(Get-WinEvent -FilterHashtable $f -MaxEvents $Max -ErrorAction Stop) } catch { return @() }
}
function Get-TXInstalled([string]$Pattern) {
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.DisplayName -match $Pattern })
}
# Application Error (event 1000): app name, faulting module
function Get-TXCrashes([int]$Days = 7) {
    @(Get-TXEvents 'Application' @(1000) 'Application Error' $Days 300 | ForEach-Object {
            $app = $null; $mod = $null
            try { $app = [string]$_.Properties[0].Value; $mod = [string]$_.Properties[3].Value } catch { }
            if ($app) { [pscustomobject]@{ App = $app; Module = $mod; Time = $_.TimeCreated } }
        })
}
# current AC / DC index of a power setting in the active plan (the "0x0000000n" values; text around them is localised)
function Get-TXPowerIndex([string]$Sub, [string]$Setting) {
    $out = (& powercfg.exe /query SCHEME_CURRENT $Sub $Setting 2>$null) -join "`n"
    $m = [regex]::Matches($out, '0x([0-9a-fA-F]{8})')
    if ($m.Count -lt 1) { return $null }
    $ac = [Convert]::ToInt32($m[$m.Count - $(if ($m.Count -ge 2) { 2 } else { 1 })].Groups[1].Value, 16)
    $dc = [Convert]::ToInt32($m[$m.Count - 1].Groups[1].Value, 16)
    return [pscustomobject]@{ AC = $ac; DC = $dc }
}
function Set-TXPowerIndex([string]$Sub, [string]$Setting, [int]$Value) {
    $null = & powercfg.exe /setacvalueindex SCHEME_CURRENT $Sub $Setting $Value 2>&1
    $null = & powercfg.exe /setdcvalueindex SCHEME_CURRENT $Sub $Setting $Value 2>&1
    $null = & powercfg.exe /setactive SCHEME_CURRENT 2>&1
}
function Test-TXWinget { return [bool](Get-Command winget.exe -ErrorAction SilentlyContinue) }
function Invoke-TXWinget([string]$Id) {
    if (-not (Test-TXWinget)) { return $false }
    $code = Invoke-PDProcess -FilePath 'winget.exe' -Arguments "install --id $Id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" -ProgressLabel $Id
    return ($code -eq 0 -or $code -eq -1978335189)        # 0x8A15002B = already installed / no newer version
}
# removable drives (pendrives, cards) with a drive letter
function Get-TXRemovableRoots {
    $r = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue | ForEach-Object { $_.DeviceID })
    try {
        foreach ($d in @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -in 'USB', 'SD', 'MMC' -and $_.Number -ne $null })) {
            foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) { $r += "$($p.DriveLetter):" }
        }
    } catch { }
    @($r | Where-Object { $_ -and $_ -ne $env:SystemDrive } | Select-Object -Unique)
}
function Start-TXAsUser([string]$Exe) {
    # programs like OneDrive refuse to run with administrator rights: File Explorer starts them with normal rights
    try { Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList "`"$Exe`"" -ErrorAction Stop; return $true } catch { return $false }
}
function Format-TXList($Items, [int]$Max = 4) { (@($Items) | Select-Object -First $Max) -join ', ' }

# ================================================================== WINDOWS

# black screen with only the mouse pointer after sign-in
$script:D['black-screen-login'] = @{
    Check = {
        Step 'Checking what starts the desktop after sign-in' 'Sign-in नंतर desktop सुरू करणारे भाग तपासत आहे' 'Sign-in के बाद desktop शुरू करने वाले हिस्से जाँच रहे हैं'
        $why = @(); $data = @{}
        $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
        $shell = [string]$wl.Shell; $ui = [string]$wl.Userinit
        if ($shell -and $shell.Trim() -notmatch '^(?i)explorer(\.exe)?$') { $why += TT "the Windows shell is set to '$shell' instead of explorer.exe" "Windows shell explorer.exe ऐवजी '$shell' आहे" "Windows shell explorer.exe की जगह '$shell' है"; $data.Winlogon = $true }
        if ($ui -and $ui.Trim() -notmatch '^(?i)[a-z]:\\windows\\system32\\userinit\.exe,?$') { $why += TT "Userinit is changed ('$ui')" "Userinit बदललेले आहे ('$ui')" "Userinit बदला हुआ है ('$ui')"; $data.Winlogon = $true }
        if ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -ErrorAction SilentlyContinue).Shell) { $why += TT 'this user has its own shell set' 'या user साठी वेगळा shell लावलेला आहे' 'इस user के लिए अलग shell लगा है'; $data.Winlogon = $true }
        $ex = @(Get-TXCrashes 7 | Where-Object { $_.App -match '^(?i)explorer\.exe$' })
        if ($ex.Count -ge 2) { $mods = Format-TXList (@($ex | ForEach-Object Module | Select-Object -Unique)) 3; $why += TT "File Explorer crashed $($ex.Count) times this week (module: $mods)" "या आठवड्यात File Explorer $($ex.Count) वेळा crash झाला (module: $mods)" "इस हफ़्ते File Explorer $($ex.Count) बार crash हुआ (module: $mods)" }
        $dead = @()
        try { $dead = @(Get-SmbMapping -ErrorAction Stop | Where-Object { $_.Status -ne 'OK' }) } catch { }
        if ($dead.Count) { $n = Format-TXList ($dead | ForEach-Object { "$($_.LocalPath) $($_.RemotePath)" }); $why += TT "mapped network drives that cannot be reached: $n" "न सापडणारे mapped network drives: $n" "न मिलने वाले mapped network drives: $n"; $data.Dead = $dead }
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { $why += TT 'File Explorer is not running' 'File Explorer चालू नाही' 'File Explorer चालू नहीं है'; $data.NoExplorer = $true }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $null (TT 'The shell settings are normal and File Explorer has not crashed. If the screen stays black after sign-in, try Win + Ctrl + Shift + B (resets the display driver) and Win + P.' 'Shell settings बरोबर आहेत आणि File Explorer crash झालेला नाही. Sign-in नंतर screen काळी राहत असेल तर Win + Ctrl + Shift + B (display driver reset) आणि Win + P वापरून पाहा.' 'Shell settings सही हैं और File Explorer crash नहीं हुआ। Sign-in के बाद screen काली रहे तो Win + Ctrl + Shift + B (display driver reset) और Win + P आज़माएँ।'))
    }
    Fix = {
        param($chk)
        $did = @(); $man = @()
        if ($chk.Data.NoExplorer) { [void](Invoke-PDQuickFix -Id 'explorer'); $did += TT 'started File Explorer again' 'File Explorer पुन्हा सुरू केला' 'File Explorer फिर शुरू किया' }
        if ($chk.Data.Winlogon) { $man += TT 'The shell was changed - usually by a virus or a "tweak" tool: run the virus check, then the Registry check (it restores explorer.exe / userinit with a backup).' 'Shell बदललेला आहे - बहुतेक virus किंवा "tweak" tool मुळे: आधी virus तपासणी, मग Registry तपासणी करा (ती backup घेऊन explorer.exe / userinit परत लावते).' 'Shell बदला गया है - अक्सर virus या "tweak" tool से: पहले virus जाँच, फिर Registry जाँच करें (वह backup लेकर explorer.exe / userinit वापस लगाती है)।' }
        if (@($chk.Data.Dead).Count) { $man += TT 'Remove the dead network drives (File Explorer → This PC → right-click → Disconnect, or "net use X: /delete").' 'न सापडणारे network drives काढा (File Explorer → This PC → right-click → Disconnect, किंवा "net use X: /delete").' 'न मिलने वाले network drives हटाएँ (File Explorer → This PC → right-click → Disconnect, या "net use X: /delete")।' }
        $man += TT 'If it continues: sign in to another account to test the profile, and repair the system files (DISM + SFC).' 'तरीही होत असेल तर: profile तपासण्यासाठी दुसऱ्या account ने sign in करा, आणि system files दुरुस्त करा (DISM + SFC).' 'फिर भी हो तो: profile जाँचने के लिए दूसरे account से sign in करें, और system files ठीक करें (DISM + SFC)।'
        $txt = if ($did.Count) { Add-TT (TT 'I' 'मी' 'मैंने') (Join-TT $did ', ') } else { TT 'These need your decision, nothing was changed automatically.' 'यासाठी तुमचा निर्णय लागतो, आपोआप काहीही बदलले नाही.' 'इसके लिए आपका फ़ैसला चाहिए, अपने आप कुछ नहीं बदला।' }
        return (New-TSFix $null $txt -Manual (Join-TT $man ' '))
    }
    NoVerify = $true
}

# "You've been signed in with a temporary profile"
$script:D['temp-profile'] = @{
    Check = {
        Step 'Checking the user profile' 'User profile तपासत आहे' 'User profile जाँच रहे हैं'
        $why = @()
        if ($env:USERPROFILE -match '\\TEMP(\.|$)') { $why += TT "Windows is using a temporary profile ($env:USERPROFILE) - work saved there is lost at sign-out" "Windows तात्पुरते profile वापरत आहे ($env:USERPROFILE) - त्यात save केलेले sign-out नंतर हरवते" "Windows अस्थायी profile इस्तेमाल कर रहा है ($env:USERPROFILE) - उसमें save किया sign-out के बाद खो जाता है" }
        $pl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $bak = @(Get-ChildItem -LiteralPath $pl -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like '*.bak' })
        if ($bak.Count) { $why += TT "$($bak.Count) damaged profile entries (.bak) in the registry" "Registry मध्ये $($bak.Count) बिघडलेल्या profile entries (.bak)" "Registry में $($bak.Count) खराब profile entries (.bak)" }
        $tmp = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.Loaded -and ($_.Status -band 1) -and -not $_.Special })
        if ($tmp.Count -and -not ($env:USERPROFILE -match '\\TEMP')) { $why += TT 'a signed-in user has a temporary profile' 'sign-in असलेल्या user चे profile तात्पुरते आहे' 'sign-in user का profile अस्थायी है' }
        $ev = @(Get-TXEvents 'Application' @(1511, 1515) 'Microsoft-Windows-User Profiles Service' 14)
        if ($ev.Count) { $why += TT "$($ev.Count) temporary-profile sign-ins in 14 days" "14 दिवसांत $($ev.Count) वेळा तात्पुरत्या profile ने sign-in" "14 दिनों में $($ev.Count) बार अस्थायी profile से sign-in" }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') @{ Bak = $bak }) }
        return (New-TSCheck $false (TT 'The user profile is normal (no temporary or damaged profile).' 'User profile नेहमीसारखे आहे (तात्पुरते किंवा बिघडलेले profile नाही).' 'User profile सामान्य है (कोई अस्थायी या खराब profile नहीं)।'))
    }
    Fix = {
        param($chk)
        $b = Save-PDRegBackup -RegPath 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name 'profilelist'
        $txt = if ($b) { TT "I saved a backup of the profile list ($b). The files are NOT lost - they are still in C:\Users\<name>." "Profile list चा backup घेतला ($b). Files हरवलेल्या नाहीत - त्या C:\Users\<नाव> मध्येच आहेत." "Profile list का backup लिया ($b)। Files खोई नहीं हैं - वे C:\Users\<नाम> में ही हैं।" } else { TT 'The files are NOT lost - they are still in C:\Users\<name>.' 'Files हरवलेल्या नाहीत - त्या C:\Users\<नाव> मध्येच आहेत.' 'Files खोई नहीं हैं - वे C:\Users\<नाम> में ही हैं।' }
        return (New-TSFix $null $txt -Manual (TT '1) Copy C:\Users\<name> to a USB disk. 2) regedit → ProfileList: the key whose ProfileImagePath is the user''s folder must not end in .bak (rename the pair), set State = 0 and RefCount = 0. 3) Restart. Or make a new account and copy the files over.' '1) C:\Users\<नाव> USB disk वर copy करा. 2) regedit → ProfileList: ज्या key चा ProfileImagePath त्या user चा folder आहे तिच्या नावाच्या शेवटी .bak नसावे (दोन्हीचे नाव बदला), State = 0 आणि RefCount = 0 करा. 3) Restart. किंवा नवीन account बनवून files copy करा.' '1) C:\Users\<नाम> को USB disk पर copy करें। 2) regedit → ProfileList: जिस key का ProfileImagePath उस user का folder है उसके नाम के अंत में .bak न हो (दोनों के नाम बदलें), State = 0 और RefCount = 0 करें। 3) Restart. या नया account बनाकर files copy करें।'))
    }
    NoVerify = $true
}

# BitLocker recovery key screen at start-up
$script:D['bitlocker-recovery'] = @{
    Check = {
        Step 'Checking BitLocker encryption' 'BitLocker encryption तपासत आहे' 'BitLocker encryption जाँच रहे हैं'
        $v = $null
        try { $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop } catch { }
        if (-not $v) {
            $o = (& manage-bde.exe -status $env:SystemDrive 2>$null) -join ' '
            if (-not $o) { return (New-TSCheck $null (TT 'BitLocker status could not be read on this PC.' 'या PC वर BitLocker ची स्थिती वाचता आली नाही.' 'इस PC पर BitLocker की स्थिति पढ़ी नहीं जा सकी।')) }
            $on = $o -match '(?i)protection on|संरक्षण चालू'
        } else { $on = ($v.ProtectionStatus -eq 'On' -or $v.VolumeStatus -match 'Encrypt') }
        if (-not $on) { return (New-TSCheck $false (TT "The $env:SystemDrive drive is not BitLocker-protected, so no recovery key is needed." "$env:SystemDrive drive वर BitLocker संरक्षण नाही, त्यामुळे recovery key लागत नाही." "$env:SystemDrive drive पर BitLocker सुरक्षा नहीं है, इसलिए recovery key नहीं चाहिए।")) }
        $ids = @()
        if ($v) { $ids = @($v.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | ForEach-Object { $_.KeyProtectorId }) }
        $kid = if ($ids.Count) { ($ids[0] -replace '[{}]', '').Split('-')[0] } else { '?' }
        return (New-TSCheck $true (TT "The $env:SystemDrive drive is encrypted with BitLocker (recovery key ID starts with $kid). After a BIOS / Windows update it can ask for the 48-digit key at start-up." "$env:SystemDrive drive BitLocker ने encrypted आहे (recovery key ID ची सुरुवात $kid). BIOS / Windows update नंतर सुरू होताना 48 अंकी key मागू शकतो." "$env:SystemDrive drive BitLocker से encrypted है (recovery key ID की शुरुआत $kid)। BIOS / Windows update के बाद शुरू होते समय 48 अंकों की key माँग सकता है।") @{ Kid = $kid })
    }
    Fix = {
        param($chk)
        return (New-TSFix $null (TT 'Nothing was changed: encryption protects the owner''s data.' 'काहीही बदलले नाही: encryption मालकाच्या data चे संरक्षण करते.' 'कुछ नहीं बदला: encryption मालिक के data की सुरक्षा करता है।') -Manual (TT "The key is in the owner's Microsoft account: open aka.ms/myrecoverykey on a phone and pick the key whose ID starts with $($chk.Data.Kid) (office PC: ask the IT admin). Make sure the owner keeps a copy; before a BIOS update, suspend BitLocker for one restart. Never decrypt or clear the TPM to 'fix' it." "Key मालकाच्या Microsoft account मध्ये असते: phone वर aka.ms/myrecoverykey उघडा आणि ज्याचा ID $($chk.Data.Kid) ने सुरू होतो ती key घ्या (office PC: IT admin कडे). मालकाकडे key ची copy असल्याची खात्री करा; BIOS update आधी BitLocker एका restart साठी suspend करा. 'Fix' म्हणून decrypt किंवा TPM clear कधीही करू नका." "Key मालिक के Microsoft account में होती है: phone पर aka.ms/myrecoverykey खोलें और जिसका ID $($chk.Data.Kid) से शुरू होता है वह key लें (office PC: IT admin से)। मालिक के पास key की copy हो यह पक्का करें; BIOS update से पहले BitLocker एक restart के लिए suspend करें। 'Fix' के लिए decrypt या TPM clear कभी न करें।"))
    }
    NoVerify = $true
}

# Windows 11 requirements / Windows 10 end of support
$script:D['win11-upgrade'] = @{
    Check = {
        Step 'Checking the Windows 11 requirements' 'Windows 11 च्या अटी तपासत आहे' 'Windows 11 की शर्तें जाँच रहे हैं'
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os.Caption -match 'Windows 11') { return (New-TSCheck $false (TT "This PC already runs $($os.Caption)." "या PC वर आधीच $($os.Caption) आहे." "इस PC पर पहले से $($os.Caption) है।")) }
        $fail = @(); $ok = @()
        $tpmOk = $false
        try {
            $t = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop
            if ($t -and ([string]$t.SpecVersion).Split(',')[0].Trim() -ge '2.0') { $tpmOk = $true }
        } catch { }
        if ($tpmOk) { $ok += 'TPM 2.0' } else { $fail += TT 'TPM 2.0 is off or missing (turn on Intel PTT / AMD fTPM in the BIOS)' 'TPM 2.0 बंद आहे किंवा नाही (BIOS मध्ये Intel PTT / AMD fTPM चालू करा)' 'TPM 2.0 बंद है या नहीं है (BIOS में Intel PTT / AMD fTPM चालू करें)' }
        $sb = $null; try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { }
        if ($sb -eq $true) { $ok += 'Secure Boot' } elseif ($sb -eq $false) { $fail += TT 'Secure Boot is off (UEFI mode, can be turned on in the BIOS)' 'Secure Boot बंद आहे (UEFI mode, BIOS मध्ये चालू करता येते)' 'Secure Boot बंद है (UEFI mode, BIOS में चालू हो सकता है)' } else { $fail += TT 'the PC starts in old Legacy / CSM mode (needs UEFI + Secure Boot)' 'PC जुन्या Legacy / CSM mode मध्ये सुरू होतो (UEFI + Secure Boot लागते)' 'PC पुराने Legacy / CSM mode में शुरू होता है (UEFI + Secure Boot चाहिए)' }
        try {
            $sysDisk = Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction Stop | Get-Disk
            if ($sysDisk.PartitionStyle -eq 'MBR') { $fail += TT 'the system disk is MBR (needs GPT - check with "mbr2gpt /validate /allowFullOS")' 'System disk MBR आहे (GPT लागते - "mbr2gpt /validate /allowFullOS" ने तपासा)' 'System disk MBR है (GPT चाहिए - "mbr2gpt /validate /allowFullOS" से जाँचें)' } else { $ok += 'GPT' }
        } catch { }
        $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        if ($ram -lt 3.8) { $fail += TT "only $ram GB RAM (4 GB needed)" "फक्त $ram GB RAM (4 GB लागते)" "सिर्फ़ $ram GB RAM (4 GB चाहिए)" } else { $ok += "RAM $ram GB" }
        $c = Get-Volume -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction SilentlyContinue
        if ($c -and $c.Size -lt 60GB) { $fail += TT 'the C: drive is smaller than 64 GB' 'C: drive 64 GB पेक्षा लहान आहे' 'C: drive 64 GB से छोटा है' }
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
        $old = $cpu -match '(?i)i[3579]-[2-7]\d{3}|core\(tm\)2|pentium|celeron [nj]?[1-3]\d{3}|athlon|\bA[4-9]-|\bFX-|Ryzen [3579] 1\d{3}'
        if ($old) { $fail += TT "the processor ($cpu) is too old for Windows 11 - this cannot be fixed by settings" "Processor ($cpu) Windows 11 साठी खूप जुना आहे - settings ने सुटत नाही" "Processor ($cpu) Windows 11 के लिए बहुत पुराना है - settings से हल नहीं होता" }
        if ($fail.Count) { return (New-TSCheck $true (Add-TT (TT 'Windows 11 is blocked:' 'Windows 11 अडते:' 'Windows 11 रुकता है:') (Join-TT $fail '; ')) @{ Old = $old; Cpu = $cpu }) }
        return (New-TSCheck $null (TT "TPM 2.0, Secure Boot, GPT disk and RAM are fine; the processor ($cpu) must be on Microsoft's supported list (Intel 8th gen / AMD Ryzen 2000 or newer). Use Windows Update or the PC Health Check app." "TPM 2.0, Secure Boot, GPT disk आणि RAM ठीक आहेत; processor ($cpu) Microsoft च्या यादीत असावा (Intel 8th gen / AMD Ryzen 2000 किंवा नवीन). Windows Update किंवा PC Health Check app वापरा." "TPM 2.0, Secure Boot, GPT disk और RAM ठीक हैं; processor ($cpu) Microsoft की सूची में होना चाहिए (Intel 8th gen / AMD Ryzen 2000 या नया)। Windows Update या PC Health Check app इस्तेमाल करें।"))
    }
    Fix = {
        param($chk)
        $m = TT 'TPM / Secure Boot are switched on in the BIOS (Security / Boot tabs). An MBR disk is converted with mbr2gpt only after a backup, and BitLocker must be suspended first.' 'TPM / Secure Boot BIOS मध्ये (Security / Boot tabs) चालू करतात. MBR disk mbr2gpt ने फक्त backup घेऊनच बदला, आणि आधी BitLocker suspend करा.' 'TPM / Secure Boot BIOS में (Security / Boot tabs) चालू होते हैं। MBR disk को mbr2gpt से सिर्फ़ backup लेकर बदलें, और पहले BitLocker suspend करें।'
        if ($chk.Data.Old) { $m = Add-TT $m (TT 'With an old processor the honest options are: stay on Windows 10 with extended security updates (ESU) while available, a light Linux (OS / Apps advice page), or a newer PC - no unsupported "bypass" as a shop fix.' 'जुन्या processor साठी प्रामाणिक पर्याय: उपलब्ध असेपर्यंत extended security updates (ESU) सह Windows 10, हलका Linux ("OS / Apps सल्ला" page), किंवा नवीन PC - दुकानातला उपाय म्हणून unsupported "bypass" नको.' 'पुराने processor के लिए सही विकल्प: उपलब्ध होने तक extended security updates (ESU) के साथ Windows 10, हल्का Linux ("OS / Apps सलाह" page), या नया PC - दुकान के उपाय के तौर पर unsupported "bypass" नहीं।') }
        return (New-TSFix $null (TT 'These are BIOS / hardware settings; nothing was changed from Windows.' 'ह्या BIOS / hardware settings आहेत; Windows मधून काहीही बदलले नाही.' 'ये BIOS / hardware settings हैं; Windows से कुछ नहीं बदला।') -Manual $m)
    }
    NoVerify = $true
}

# shared folders / NAS / other PCs on the network
$script:D['network-share'] = @{
    Check = {
        Step 'Checking network sharing' 'Network sharing तपासत आहे' 'Network sharing जाँच रहे हैं'
        $why = @(); $data = @{ Svc = @() }
        $pub = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'Public' })
        if ($pub.Count) { $why += TT "the network '$($pub[0].Name)' is set to Public, which hides this PC and blocks sharing" "network '$($pub[0].Name)' Public आहे, त्यामुळे हा PC दिसत नाही आणि sharing बंद राहते" "network '$($pub[0].Name)' Public है, इससे यह PC नहीं दिखता और sharing बंद रहती है"; $data.Public = $true }
        foreach ($s in 'FDResPub', 'fdPHost', 'LanmanWorkstation') {
            $sv = Get-Service $s -ErrorAction SilentlyContinue
            if ($sv -and $sv.Status -ne 'Running') { $data.Svc += $s }
        }
        if ($data.Svc.Count) { $why += TT "network discovery services are stopped ($($data.Svc -join ', '))" "network शोधणाऱ्या services बंद आहेत ($($data.Svc -join ', '))" "network खोजने वाली services बंद हैं ($($data.Svc -join ', '))" }
        $info = $null
        try {
            $c = Get-SmbClientConfiguration -ErrorAction Stop
            if ($c.RequireSecuritySignature -and -not $c.EnableInsecureGuestLogons) { $info = TT 'Windows now requires signed connections and blocks guest (no-password) access: old NAS boxes / router USB disks need a real user name and password or a firmware update.' 'Windows आता signed connection मागते आणि guest (password नसलेला) access बंद करते: जुने NAS / router USB disk साठी खरे user name-password किंवा firmware update लागतो.' 'Windows अब signed connection माँगता है और guest (बिना password) access बंद करता है: पुराने NAS / router USB disk के लिए असली user name-password या firmware update चाहिए।' }
        } catch { }
        $data.Info = $info
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        $t = TT 'Network discovery is on and the network is Private.' 'Network discovery चालू आहे आणि network Private आहे.' 'Network discovery चालू है और network Private है।'
        if ($info) { $t = Add-TT $t $info } else { $t = Add-TT $t (TT 'Try the other PC by its IP: \\192.168.x.x' 'दुसरा PC त्याच्या IP ने उघडून पाहा: \\192.168.x.x' 'दूसरा PC उसके IP से खोलकर देखें: \\192.168.x.x') }
        return (New-TSCheck $null $t)
    }
    Fix = {
        param($chk)
        $did = @()
        foreach ($s in @($chk.Data.Svc)) {
            try { if ($s -eq 'FDResPub') { Set-Service $s -StartupType Automatic -ErrorAction Stop }; Start-Service $s -ErrorAction Stop; $did += $s } catch { }
        }
        $txt = if ($did.Count) { TT "I started the network discovery services ($($did -join ', '))." "Network शोधणाऱ्या services सुरू केल्या ($($did -join ', '))." "Network खोजने वाली services शुरू कीं ($($did -join ', '))।" } else { TT 'No service needed starting.' 'कोणतीही service सुरू करावी लागली नाही.' 'कोई service शुरू नहीं करनी पड़ी।' }
        $man = @()
        if ($chk.Data.Public) { $man += TT 'Only on a trusted home / office network: Settings → Network → this network → Private (you decide - on public WiFi keep it Public).' 'फक्त विश्वासाच्या घर / office network वर: Settings → Network → हा network → Private (निर्णय तुमचा - public WiFi वर Public च ठेवा).' 'सिर्फ़ भरोसेमंद घर / office network पर: Settings → Network → यह network → Private (फ़ैसला आपका - public WiFi पर Public ही रखें)।' }
        if ($chk.Data.Info) { $man += $chk.Data.Info }
        $man += TT 'Open the share by IP (\\192.168.x.x\folder) and save the right user name / password in Credential Manager.' 'Share IP ने उघडा (\\192.168.x.x\folder) आणि योग्य user name / password Credential Manager मध्ये save करा.' 'Share IP से खोलें (\\192.168.x.x\folder) और सही user name / password Credential Manager में save करें।'
        return (New-TSFix $(if ($did.Count -and -not $chk.Data.Public) { $true } else { $null }) $txt -Manual (Join-TT $man ' '))
    }
}


# PC will not sleep / wakes up by itself
$script:SubSleep = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; $script:RtcWake = 'bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d'
$script:D['sleep-wake'] = @{
    Check = {
        Step 'Checking what wakes the PC up' 'PC ला कोण जागे करते ते तपासत आहे' 'PC को कौन जगाता है, जाँच रहे हैं'
        $why = @(); $data = @{ Nics = @() }
        $armed = @((& powercfg.exe /devicequery wake_armed 2>$null) | Where-Object { $_ -and $_.Trim() -and $_ -notmatch '^\s*NONE\s*$' } | ForEach-Object { $_.Trim() })
        $nicNames = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { $_.InterfaceDescription })
        $data.Nics = @($armed | Where-Object { $nicNames -contains $_ -or $_ -match '(?i)ethernet|network|wi-?fi|wireless|lan|realtek pcie|intel\(r\) (ethernet|wi)' })
        if ($data.Nics.Count) { $why += TT "the network adapter may wake the PC ($(Format-TXList $data.Nics 2))" "network adapter PC ला जागे करू शकतो ($(Format-TXList $data.Nics 2))" "network adapter PC को जगा सकता है ($(Format-TXList $data.Nics 2))" }
        $rtc = Get-TXPowerIndex $script:SubSleep $script:RtcWake
        if ($rtc -and ($rtc.AC -eq 1 -or $rtc.DC -eq 1)) { $why += TT 'wake timers are allowed (scheduled tasks / updates can switch the PC on at night)' 'wake timers चालू आहेत (scheduled tasks / updates रात्री PC चालू करू शकतात)' 'wake timers चालू हैं (scheduled tasks / updates रात में PC चालू कर सकते हैं)'; $data.Rtc = $true }
        $mice = @($armed | Where-Object { $_ -match '(?i)mouse|माउस' })
        if ($why.Count) {
            $t = Join-TT $why '; '
            if ($mice.Count) { $t = Add-TT $t (TT "(the mouse can also wake it: $(Format-TXList $mice 1))" "(mouse सुद्धा जागे करू शकतो: $(Format-TXList $mice 1))" "(mouse भी जगा सकता है: $(Format-TXList $mice 1))") }
            return (New-TSCheck $true $t $data)
        }
        $lw = ((& powercfg.exe /lastwake 2>$null) -join ' ') -replace '\s+', ' '
        return (New-TSCheck $null (TT "No network wake or wake timers are set. Last wake: $lw" "Network wake किंवा wake timers लावलेले नाहीत. शेवटचे जागे होणे: $lw" "Network wake या wake timers नहीं लगे। आख़िरी बार जगना: $lw"))
    }
    Fix = {
        param($chk)
        $did = @()
        foreach ($n in @($chk.Data.Nics)) { $null = & powercfg.exe /devicedisablewake $n 2>&1; if ($LASTEXITCODE -eq 0) { $did += $n } }
        if ($chk.Data.Rtc) { Set-TXPowerIndex $script:SubSleep $script:RtcWake 0; $did += 'wake timers' }
        if (-not $did.Count) { return (New-TSFix $false (TT 'Nothing could be changed.' 'काहीही बदलता आले नाही.' 'कुछ नहीं बदला जा सका।') -Manual (TT 'Run "powercfg /requests" as administrator to see what keeps the PC awake.' 'PC ला जागे ठेवणारे पाहण्यासाठी administrator म्हणून "powercfg /requests" चालवा.' 'PC को जगाए रखने वाला देखने के लिए administrator के रूप में "powercfg /requests" चलाएँ।')) }
        $n = Format-TXList $did 4
        return (New-TSFix $true (TT "I stopped these from waking the PC: $n." "यांना PC जागे करण्यापासून थांबवले: $n." "इन्हें PC जगाने से रोका: $n।") -Manual (TT 'To allow it again: "powercfg /deviceenableawake <name>". Missing chipset / graphics drivers also break sleep - install them from the maker.' 'पुन्हा चालू करण्यासाठी: "powercfg /deviceenableawake <नाव>". Chipset / graphics drivers नसल्यास sleep बिघडते - कंपनीकडून install करा.' 'फिर चालू करने के लिए: "powercfg /deviceenableawake <नाम>"। Chipset / graphics drivers न हों तो sleep बिगड़ती है - कंपनी से install करें।'))
    }
}

# Windows Hello PIN / fingerprint / face not working
$script:D['hello-pin'] = @{
    Check = {
        Step 'Checking the sign-in hardware (TPM, fingerprint, face camera)' 'Sign-in hardware (TPM, fingerprint, face camera) तपासत आहे' 'Sign-in hardware (TPM, fingerprint, face camera) जाँच रहे हैं'
        $why = @(); $data = @{}
        $bio = @(Get-PnpDevice -Class Biometric -PresentOnly -ErrorAction SilentlyContinue)
        $badBio = @(Get-TSProblemDevices @('Biometric'))
        if ($badBio.Count) { $why += TT "the fingerprint / face device has a driver problem ($(Get-TSDeviceName $badBio[0]))" "fingerprint / face device च्या driver मध्ये दोष आहे ($(Get-TSDeviceName $badBio[0]))" "fingerprint / face device के driver में खराबी है ($(Get-TSDeviceName $badBio[0]))"; $data.Bad = $badBio }
        $wb = Get-Service WbioSrvc -ErrorAction SilentlyContinue
        if ($bio.Count -and $wb -and $wb.Status -ne 'Running') { $why += TT 'the Windows Biometric service is stopped' 'Windows Biometric service बंद आहे' 'Windows Biometric service बंद है'; $data.Svc = $true }
        try { $t = Get-Tpm -ErrorAction Stop; if ($t.TpmPresent -and -not $t.TpmReady) { $why += TT 'the TPM security chip is not ready (often after a BIOS update or reset) - the PIN depends on it' 'TPM security chip तयार नाही (बहुतेक BIOS update / reset नंतर) - PIN त्यावर अवलंबून असतो' 'TPM security chip तैयार नहीं है (अक्सर BIOS update / reset के बाद) - PIN उसी पर निर्भर है'; $data.Tpm = $true } } catch { }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $null (TT 'TPM and sign-in devices look fine; a broken PIN store cannot be seen from outside.' 'TPM आणि sign-in devices ठीक दिसतात; बिघडलेला PIN store बाहेरून दिसत नाही.' 'TPM और sign-in devices ठीक दिखते हैं; खराब PIN store बाहर से नहीं दिखता।'))
    }
    Fix = {
        param($chk)
        $did = @()
        if ($chk.Data.Svc) { try { Start-Service WbioSrvc -ErrorAction Stop; $did += TT 'started the Biometric service' 'Biometric service सुरू केली' 'Biometric service शुरू की' } catch { } }
        if (@($chk.Data.Bad).Count) { $r = @(Repair-TSDevices $chk.Data.Bad); if ($r.Count) { $did += TT 'restarted the fingerprint / face device' 'fingerprint / face device पुन्हा सुरू केला' 'fingerprint / face device फिर शुरू किया' } }
        Start-Process 'ms-settings:signinoptions' -ErrorAction SilentlyContinue
        $txt = if ($did.Count) { Add-TT (TT 'I' 'मी' 'मैंने') (Join-TT $did ', ') } else { TT 'I opened Sign-in options.' 'Sign-in options उघडले.' 'Sign-in options खोले।' }
        return (New-TSFix $null $txt -Manual (TT 'Sign in with the account PASSWORD first (make sure the owner knows it), then Sign-in options → PIN → Remove → Add again. If that fails, a technician resets the NGC folder. A TPM "not ready" is fixed in the BIOS (Security → TPM / PTT on).' 'आधी account च्या PASSWORD ने sign in करा (मालकाला तो माहीत असल्याची खात्री करा), मग Sign-in options → PIN → Remove → पुन्हा Add. तरी चालत नसेल तर technician NGC folder reset करतो. TPM "not ready" BIOS मध्ये (Security → TPM / PTT चालू) सुटते.' 'पहले account के PASSWORD से sign in करें (मालिक को वह पता हो यह पक्का करें), फिर Sign-in options → PIN → Remove → फिर Add. फिर भी न चले तो technician NGC folder reset करता है। TPM "not ready" BIOS में (Security → TPM / PTT चालू) ठीक होता है।'))
    }
    NoVerify = $true
}

# Antimalware Service Executable (Defender) using the processor
$script:D['defender-cpu'] = @{
    Check = {
        Step 'Measuring how much the antivirus uses the processor' 'Antivirus processor किती वापरतो ते मोजत आहे' 'Antivirus processor कितना इस्तेमाल करता है, माप रहे हैं'
        $s = @()
        for ($i = 0; $i -lt 3; $i++) {
            $p = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name='MsMpEng'" -ErrorAction SilentlyContinue
            if ($p) { $s += [double]$p.PercentProcessorTime }
            Start-Sleep -Milliseconds 900
        }
        $cores = [Environment]::ProcessorCount
        $pct = if ($s.Count) { [math]::Round((($s | Measure-Object -Average).Average) / [math]::Max(1, $cores)) } else { $null }
        $others = @()
        try { $others = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch '(?i)defender' } | ForEach-Object displayName) } catch { }
        $why = @()
        if ($null -ne $pct -and $pct -ge 20) { $why += TT "the antivirus (MsMpEng) uses about $pct% of the processor right now" "antivirus (MsMpEng) आत्ता सुमारे $pct% processor वापरतो" "antivirus (MsMpEng) अभी लगभग $pct% processor इस्तेमाल करता है" }
        if ($others.Count -ge 2) { $why += TT "more than one other antivirus is registered ($(Format-TXList $others 3)) - they slow each other down" "एकापेक्षा जास्त antivirus नोंदलेले आहेत ($(Format-TXList $others 3)) - ते एकमेकांना धीमे करतात" "एक से ज़्यादा antivirus दर्ज हैं ($(Format-TXList $others 3)) - वे एक-दूसरे को धीमा करते हैं" }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') @{ Pct = $pct; Others = $others }) }
        $now = if ($null -ne $pct) { "$pct%" } else { '-' }
        return (New-TSCheck $false (TT "The antivirus is not loading the PC now (processor use $now)." "Antivirus आत्ता PC वर भार टाकत नाही (processor वापर $now)." "Antivirus अभी PC पर भार नहीं डाल रहा (processor इस्तेमाल $now)।"))
    }
    Fix = {
        param($chk)
        $did = $false
        try {
            $cur = (Get-MpPreference -ErrorAction Stop).ScanAvgCPULoadFactor
            if ($cur -gt 30) { Set-MpPreference -ScanAvgCPULoadFactor 30 -ErrorAction Stop; $did = $true }
        } catch { }
        $txt = if ($did) { TT 'I limited Defender''s scans to about 30% of the processor (protection stays fully on).' 'Defender च्या scans ना सुमारे 30% processor पर्यंत मर्यादित केले (संरक्षण पूर्ण चालू आहे).' 'Defender के scans को लगभग 30% processor तक सीमित किया (सुरक्षा पूरी चालू है)।' } else { TT 'Protection was left fully on.' 'संरक्षण पूर्ण चालू ठेवले.' 'सुरक्षा पूरी चालू रखी।' }
        return (New-TSFix $(if ($did) { $true } else { $null }) $txt -Manual (TT 'A scan after updates is normal and ends by itself. Keep only ONE antivirus (remove expired trials). On an old HDD / 4 GB RAM PC an SSD or more RAM is the real cure. Never switch Defender off.' 'Updates नंतर scan होणे नेहमीचे आहे आणि आपोआप संपते. फक्त एकच antivirus ठेवा (संपलेले trials काढा). जुन्या HDD / 4 GB RAM PC वर SSD किंवा जास्त RAM हाच खरा उपाय. Defender कधीही बंद करू नका.' 'Updates के बाद scan होना सामान्य है और अपने आप खत्म होता है। सिर्फ़ एक antivirus रखें (खत्म trials हटाएँ)। पुराने HDD / 4 GB RAM PC पर SSD या ज़्यादा RAM ही असली इलाज है। Defender कभी बंद न करें।'))
    }
    NoVerify = $true
}

# Windows Security app will not open
$script:D['security-app'] = @{
    Check = {
        Step 'Checking the Windows Security app and its services' 'Windows Security app आणि त्याच्या services तपासत आहे' 'Windows Security app और उसकी services जाँच रहे हैं'
        $why = @(); $data = @{ Svc = @() }
        $pkg = $null
        try { $pkg = Get-AppxPackage -AllUsers -Name Microsoft.SecHealthUI -ErrorAction Stop | Select-Object -First 1 } catch { try { $pkg = Get-AppxPackage -Name Microsoft.SecHealthUI -ErrorAction Stop | Select-Object -First 1 } catch { } }
        $isServer = (Get-CimInstance Win32_OperatingSystem).ProductType -ne 1
        if (-not $pkg -and -not $isServer) { $why += TT 'the Windows Security app is missing' 'Windows Security app नाही' 'Windows Security app नहीं है'; $data.Pkg = $true }
        elseif ($pkg -and $pkg.Status -and $pkg.Status -ne 'Ok') { $why += TT "the Windows Security app is damaged ($($pkg.Status))" "Windows Security app बिघडलेले आहे ($($pkg.Status))" "Windows Security app खराब है ($($pkg.Status))"; $data.Pkg = $true }
        foreach ($s in 'SecurityHealthService', 'wscsvc') { $sv = Get-Service $s -ErrorAction SilentlyContinue; if ($sv -and $sv.Status -ne 'Running') { $data.Svc += $s } }
        if ($data.Svc.Count) { $why += TT "security services are stopped ($($data.Svc -join ', '))" "security services बंद आहेत ($($data.Svc -join ', '))" "security services बंद हैं ($($data.Svc -join ', '))" }
        $pol = Get-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -ErrorAction SilentlyContinue
        if ($pol -and ($pol.ValueCount -or $pol.SubKeyCount)) { $why += TT 'Defender is controlled by policy settings ("managed by your organization") - on a home PC this is usually a virus or a tweak tool' 'Defender policy settings ने नियंत्रित आहे ("managed by your organization") - घरच्या PC वर हे बहुतेक virus किंवा tweak tool मुळे' 'Defender policy settings से नियंत्रित है ("managed by your organization") - घर के PC पर यह अक्सर virus या tweak tool से होता है'; $data.Policy = $true }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT 'The Windows Security app and its services are fine.' 'Windows Security app आणि त्याच्या services ठीक आहेत.' 'Windows Security app और उसकी services ठीक हैं।'))
    }
    Fix = {
        param($chk)
        $did = @()
        foreach ($s in @($chk.Data.Svc)) { try { Start-Service $s -ErrorAction Stop; $did += $s } catch { } }
        if ($chk.Data.Pkg) {
            try {
                $p = Get-AppxPackage -AllUsers -Name Microsoft.SecHealthUI -ErrorAction Stop | Select-Object -First 1
                if ($p -and (Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue)) { $p | Reset-AppxPackage -ErrorAction Stop; $did += 'Windows Security app (reset)' }
                elseif ($p) { Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $p.InstallLocation 'AppXManifest.xml') -ErrorAction Stop; $did += 'Windows Security app (re-registered)' }
            } catch { }
        }
        $txt = if ($did.Count) { TT "I repaired: $($did -join ', ')." "दुरुस्त केले: $($did -join ', ')." "ठीक किया: $($did -join ', ')।" } else { TT 'Nothing could be repaired automatically.' 'आपोआप काहीही दुरुस्त झाले नाही.' 'अपने आप कुछ ठीक नहीं हुआ।' }
        $man = TT 'If it still does not open: remove leftovers of old antivirus programs (vendor''s removal tool) and repair the system files (DISM + SFC).' 'तरीही उघडत नसेल तर: जुन्या antivirus चे उरलेले भाग काढा (कंपनीचे removal tool) आणि system files दुरुस्त करा (DISM + SFC).' 'फिर भी न खुले तो: पुराने antivirus के बचे हिस्से हटाएँ (कंपनी का removal tool) और system files ठीक करें (DISM + SFC)।'
        if ($chk.Data.Policy) { $man = Add-TT (TT 'Run the virus check and then the Registry check - it removes the Defender policies a virus set (with a backup). On an office PC ask the IT admin first.' 'Virus तपासणी आणि मग Registry तपासणी करा - virus ने लावलेल्या Defender policies ती (backup सह) काढते. Office PC वर आधी IT admin ला विचारा.' 'Virus जाँच और फिर Registry जाँच करें - virus की लगाई Defender policies वह (backup के साथ) हटाती है। Office PC पर पहले IT admin से पूछें।') $man }
        return (New-TSFix $null $txt -Manual $man)
    }
}

# Desktop / Documents files "missing" (OneDrive folder backup)
$script:D['desktop-files-missing'] = @{
    Check = {
        Step 'Checking where the Desktop and Documents folders are' 'Desktop आणि Documents folders कुठे आहेत ते तपासत आहे' 'Desktop और Documents folders कहाँ हैं, जाँच रहे हैं'
        $usf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
        $paths = @([Environment]::ExpandEnvironmentVariables([string]$usf.Desktop), [Environment]::ExpandEnvironmentVariables([string]$usf.Personal))
        $od = @($paths | Where-Object { $_ -match '(?i)onedrive' })
        $run = [bool](Get-Process OneDrive -ErrorAction SilentlyContinue)
        $exe = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($env:USERPROFILE -match '\\TEMP') { return (New-TSCheck $true (TT 'Windows signed in with a temporary profile - the real Desktop is in the user''s own folder (see "temporary profile").' 'Windows तात्पुरत्या profile ने sign in झाले - खरा Desktop user च्या स्वतःच्या folder मध्ये आहे ("तात्पुरते profile" पाहा).' 'Windows अस्थायी profile से sign in हुआ - असली Desktop user के अपने folder में है ("अस्थायी profile" देखें)।') @{ Temp = $true }) }
        if ($od.Count -and -not $run) { return (New-TSCheck $true (TT "Desktop / Documents are kept in OneDrive ($($od[0])) but OneDrive is not running, so online-only files do not open." "Desktop / Documents OneDrive मध्ये ठेवलेले आहेत ($($od[0])) पण OneDrive चालू नाही, त्यामुळे online-only files उघडत नाहीत." "Desktop / Documents OneDrive में रखे हैं ($($od[0])) पर OneDrive चालू नहीं है, इसलिए online-only files नहीं खुलतीं।") @{ Exe = $exe; Od = $od[0] }) }
        if ($od.Count) { return (New-TSCheck $null (TT "Desktop / Documents are kept in OneDrive ($($od[0])) and OneDrive is running. Files with a cloud icon are online-only; deleted ones may be in the OneDrive web Recycle Bin." "Desktop / Documents OneDrive मध्ये आहेत ($($od[0])) आणि OneDrive चालू आहे. Cloud icon असलेल्या files फक्त online आहेत; delete झालेल्या OneDrive web च्या Recycle Bin मध्ये असू शकतात." "Desktop / Documents OneDrive में हैं ($($od[0])) और OneDrive चालू है। Cloud icon वाली files सिर्फ़ online हैं; delete हुई OneDrive web के Recycle Bin में हो सकती हैं।")) }
        $others = Format-TXList (@(Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'All Users', 'Default User' } | ForEach-Object Name)) 6
        return (New-TSCheck $null (TT "The Desktop is in its normal place. User folders on this PC: $others - the files may be in another account or in Windows.old." "Desktop नेहमीच्या जागी आहे. या PC वरचे user folders: $others - files दुसऱ्या account मध्ये किंवा Windows.old मध्ये असू शकतात." "Desktop सामान्य जगह पर है। इस PC के user folders: $others - files दूसरे account में या Windows.old में हो सकती हैं।"))
    }
    Fix = {
        param($chk)
        if ($chk.Data.Temp) { return (& $script:D['temp-profile'].Fix (& $script:D['temp-profile'].Check)) }
        $ok = $false
        if ($chk.Data.Exe) { $ok = Start-TXAsUser $chk.Data.Exe }
        $man = TT 'Sign in to OneDrive (tray cloud icon). Keep important folders with right-click → "Always keep on this device". If the free 5 GB is full or the owner does not want OneDrive: OneDrive settings → Sync and backup → Manage backup → Stop (only after all files are downloaded).' 'OneDrive मध्ये sign in करा (tray मधील cloud icon). महत्त्वाचे folders right-click → "Always keep on this device" ने ठेवा. मोफत 5 GB भरले असल्यास किंवा मालकाला OneDrive नको असल्यास: OneDrive settings → Sync and backup → Manage backup → Stop (सगळ्या files download झाल्यावरच).' 'OneDrive में sign in करें (tray का cloud icon)। ज़रूरी folders को right-click → "Always keep on this device" से रखें। मुफ़्त 5 GB भरा हो या मालिक को OneDrive नहीं चाहिए: OneDrive settings → Sync and backup → Manage backup → Stop (सभी files download होने के बाद ही)।'
        if ($ok) { return (New-TSFix $true (TT 'I started OneDrive - the files appear again as it syncs.' 'OneDrive सुरू केले - sync होताच files पुन्हा दिसतील.' 'OneDrive शुरू किया - sync होते ही files फिर दिखेंगी।') -Manual $man) }
        return (New-TSFix $false (TT 'OneDrive is not installed / could not be started.' 'OneDrive install नाही / सुरू करता आले नाही.' 'OneDrive install नहीं है / शुरू नहीं हो सका।') -Manual $man)
    }
    NoVerify = $true
}

# programs / shortcuts open with the wrong app
$script:D['file-assoc'] = @{
    Check = {
        Step 'Checking how programs and files open' 'Programs आणि files कशा उघडतात ते तपासत आहे' 'Programs और files कैसे खुलती हैं, जाँच रहे हैं'
        $bad = @()
        foreach ($a in @(@('.exe', 'exefile'), @('.lnk', 'lnkfile'))) {
            $v = (Get-ItemProperty "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($a[0])" -ErrorAction SilentlyContinue).'(default)'
            if ($v -and $v -ne $a[1]) { $bad += "$($a[0]) = $v" }
            if (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($a[0])\UserChoice") { $bad += "$($a[0]) (user choice)" }
        }
        if ($bad.Count) { return (New-TSCheck $true (TT "Programs / shortcuts are set to open in the wrong way ($($bad -join ', ')) - usually done by a virus." "Programs / shortcuts चुकीच्या पद्धतीने उघडण्यासाठी लावलेले आहेत ($($bad -join ', ')) - बहुतेक virus मुळे." "Programs / shortcuts गलत तरीके से खुलने के लिए लगे हैं ($($bad -join ', ')) - अक्सर virus से।") @{ Bad = $bad }) }
        $pdf = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
        $p = if ($pdf) { $pdf } else { '-' }
        return (New-TSCheck $null (TT "Programs and shortcuts open normally. PDF files open with: $p. Change any file type in Settings → Apps → Default apps." "Programs आणि shortcuts नेहमीसारखे उघडतात. PDF files उघडतात: $p. कोणताही file type Settings → Apps → Default apps मध्ये बदला." "Programs और shortcuts सामान्य खुलते हैं। PDF files खुलती हैं: $p। कोई भी file type Settings → Apps → Default apps में बदलें।"))
    }
    Fix = {
        param($chk)
        return (New-TSFix $null (TT 'This is a virus sign; it is repaired with a backup by the Registry check.' 'हे virus चे लक्षण आहे; Registry तपासणी backup घेऊन ते दुरुस्त करते.' 'यह virus का लक्षण है; Registry जाँच backup लेकर इसे ठीक करती है।') -Manual (TT 'Run the virus check first, then the Registry check (it restores .exe / .lnk). Default apps for other files: Settings → Apps → Default apps.' 'आधी virus तपासणी, मग Registry तपासणी करा (ती .exe / .lnk परत लावते). इतर files चे default app: Settings → Apps → Default apps.' 'पहले virus जाँच, फिर Registry जाँच करें (वह .exe / .lnk वापस लगाती है)। बाकी files के default app: Settings → Apps → Default apps.'))
    }
    NoVerify = $true
}

# copy-paste not working
$script:D['clipboard'] = @{
    Check = {
        Step 'Testing copy and paste' 'Copy आणि paste तपासत आहे' 'Copy और paste जाँच रहे हैं'
        $tok = 'Sanjeevani-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $old = $null; $ok = $null
        try {
            $old = Get-Clipboard -Raw -ErrorAction Stop
            Set-Clipboard -Value $tok -ErrorAction Stop
            Start-Sleep -Milliseconds 300
            $ok = ((Get-Clipboard -Raw -ErrorAction Stop) -match [regex]::Escape($tok))
        } catch { $ok = $null }
        try { if ($old) { Set-Clipboard -Value $old -ErrorAction Stop } } catch { }
        if ($null -eq $ok) { return (New-TSCheck $null (TT 'The clipboard could not be tested here.' 'Clipboard इथे तपासता आला नाही.' 'Clipboard यहाँ जाँचा नहीं जा सका।')) }
        if (-not $ok) { return (New-TSCheck $true (TT 'Copy-paste does not work: copied text does not reach the clipboard.' 'Copy-paste चालत नाही: copy केलेला text clipboard पर्यंत पोहोचत नाही.' 'Copy-paste नहीं चल रहा: copy किया text clipboard तक नहीं पहुँचता।')) }
        $rdp = Get-Process rdpclip, TeamViewer, AnyDesk -ErrorAction SilentlyContinue | Select-Object -First 1
        $t = TT 'Copy-paste works in Windows.' 'Windows मध्ये copy-paste चालते.' 'Windows में copy-paste चलता है।'
        if ($rdp) { $t = Add-TT $t (TT "A remote-access tool ($($rdp.Name)) is running - it can block copy-paste in some apps; close it and try." "Remote-access tool ($($rdp.Name)) चालू आहे - काही apps मध्ये तो copy-paste अडवू शकतो; बंद करून पाहा." "Remote-access tool ($($rdp.Name)) चालू है - कुछ apps में वह copy-paste रोक सकता है; बंद करके देखें।") }
        return (New-TSCheck $false $t)
    }
    Fix = {
        Get-Service 'cbdhsvc_*' -ErrorAction SilentlyContinue | ForEach-Object { try { Restart-Service $_.Name -Force -ErrorAction Stop } catch { } }
        Get-Process rdpclip -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        [void](Invoke-PDQuickFix -Id 'explorer')
        return (New-TSFix $true (TT 'I restarted the clipboard service and File Explorer.' 'Clipboard service आणि File Explorer पुन्हा सुरू केले.' 'Clipboard service और File Explorer फिर शुरू किए।') -Manual (TT 'If pasted text is different from what you copied (bank / UPI numbers!), it is a virus - run the virus check now.' 'Paste केलेला text copy केलेल्यापेक्षा वेगळा येत असेल (bank / UPI नंबर!), तर तो virus आहे - लगेच virus तपासणी करा.' 'Paste किया text copy किए से अलग आए (bank / UPI नंबर!), तो वह virus है - तुरंत virus जाँच करें।'))
    }
}

# "Your computer is low on memory"
$script:D['low-memory'] = @{
    Check = {
        Step 'Checking the memory and the page file' 'Memory आणि page file तपासत आहे' 'Memory और page file जाँच रहे हैं'
        $why = @(); $data = @{}
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
        $pfMB = [double](($pf | Measure-Object AllocatedBaseSize -Sum).Sum)
        if ($cs -and -not $cs.AutomaticManagedPagefile -and $pfMB -lt 1024) { $why += TT "the page file (virtual memory) is switched off or tiny ($pfMB MB) - often done by 'optimizer' tools" "page file (virtual memory) बंद किंवा खूप लहान आहे ($pfMB MB) - बहुतेक 'optimizer' tools मुळे" "page file (virtual memory) बंद या बहुत छोटी है ($pfMB MB) - अक्सर 'optimizer' tools से"; $data.Pf = $true }
        $ev = @(Get-TXEvents 'System' @(2004) 'Microsoft-Windows-Resource-Exhaustion-Detector' 14)
        if ($ev.Count) { $why += TT "Windows ran out of memory $($ev.Count) times in 14 days" "14 दिवसांत Windows ची memory $($ev.Count) वेळा संपली" "14 दिनों में Windows की memory $($ev.Count) बार खत्म हुई" }
        $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $data.Ram = $ram
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT "The page file is managed by Windows and no low-memory events were recorded (RAM $ram GB)." "Page file Windows सांभाळते आणि memory कमी पडल्याची नोंद नाही (RAM $ram GB)." "Page file Windows संभालता है और memory कम पड़ने का रिकॉर्ड नहीं (RAM $ram GB)।"))
    }
    Fix = {
        param($chk)
        $man = TT "With $($chk.Data.Ram) GB RAM: close unused browser tabs; 8 GB RAM is the comfortable minimum for Windows 10/11 today." "$($chk.Data.Ram) GB RAM सह: न लागणारे browser tabs बंद करा; आजच्या Windows 10/11 साठी 8 GB RAM आरामदायक किमान आहे." "$($chk.Data.Ram) GB RAM के साथ: बेकार browser tabs बंद करें; आज के Windows 10/11 के लिए 8 GB RAM आरामदायक न्यूनतम है।"
        if (-not $chk.Data.Pf) { return (New-TSFix $null (TT 'The page file is fine; the PC simply needs more memory for what it runs.' 'Page file ठीक आहे; PC वर चालणाऱ्या कामासाठी जास्त memory लागते.' 'Page file ठीक है; PC पर चलने वाले काम के लिए ज़्यादा memory चाहिए।') -Manual $man) }
        New-TSRestorePointOnce
        try {
            $cs = Get-CimInstance Win32_ComputerSystem
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
            return (New-TSFix $true (TT 'I let Windows manage the page file again (virtual memory on).' 'Page file पुन्हा Windows ला सांभाळू दिली (virtual memory चालू).' 'Page file फिर से Windows को संभालने दी (virtual memory चालू)।') -Restart -Manual $man)
        } catch { return (New-TSFix $false (TT "The page file could not be changed: $($_.Exception.Message)" "Page file बदलता आली नाही: $($_.Exception.Message)" "Page file बदली नहीं जा सकी: $($_.Exception.Message)") -Manual (TT 'System → Advanced system settings → Performance → Advanced → Virtual memory → "Automatically manage".' 'System → Advanced system settings → Performance → Advanced → Virtual memory → "Automatically manage".' 'System → Advanced system settings → Performance → Advanced → Virtual memory → "Automatically manage".')) }
    }
}


# ================================================================== APPS

# Word / Excel / PowerPoint / Outlook crash or will not open
$script:D['office-repair'] = @{
    Check = {
        Step 'Checking Microsoft Office' 'Microsoft Office तपासत आहे' 'Microsoft Office जाँच रहे हैं'
        $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
        $msi = @(Get-TXInstalled '^Microsoft (Office|365)')
        if (-not $c2r -and -not $msi.Count) { return (New-TSCheck $false (TT 'Microsoft Office is not installed on this PC.' 'या PC वर Microsoft Office install नाही.' 'इस PC पर Microsoft Office install नहीं है।')) }
        $cr = @(Get-TXCrashes 14 | Where-Object { $_.App -match '^(?i)(winword|excel|powerpnt|outlook|onenote|msaccess|mspub)\.exe$' })
        if ($cr.Count) {
            $apps = Format-TXList (@($cr | ForEach-Object App | Select-Object -Unique)) 4
            return (New-TSCheck $true (TT "Office programs crashed $($cr.Count) times in 14 days ($apps)." "14 दिवसांत Office programs $($cr.Count) वेळा crash झाले ($apps)." "14 दिनों में Office programs $($cr.Count) बार crash हुए ($apps)।") @{ C2R = $c2r })
        }
        return (New-TSCheck $null (TT 'Office is installed and no Office crash was recorded. If a file does not open, try another file; start the app in safe mode with "winword /safe" or "excel /safe" (Win + R).' 'Office install आहे आणि Office crash ची नोंद नाही. एखादी file उघडत नसेल तर दुसरी file उघडून पाहा; app safe mode मध्ये "winword /safe" किंवा "excel /safe" (Win + R) ने सुरू करा.' 'Office install है और Office crash का रिकॉर्ड नहीं। कोई file न खुले तो दूसरी file खोलकर देखें; app को safe mode में "winword /safe" या "excel /safe" (Win + R) से शुरू करें।') @{ C2R = $c2r })
    }
    Fix = {
        param($chk)
        $man = TT 'Choose "Quick Repair" (offline, keeps files and settings). If it still crashes, run "Online Repair" (downloads Office again). Also start the app with /safe - if it works then, a faulty add-in is the cause (File → Options → Add-ins).' '"Quick Repair" निवडा (offline, files आणि settings राहतात). तरीही crash होत असेल तर "Online Repair" (Office पुन्हा download होते). App /safe ने सुरू करून पाहा - तेव्हा चालले तर खराब add-in कारण आहे (File → Options → Add-ins).' '"Quick Repair" चुनें (offline, files और settings रहती हैं)। फिर भी crash हो तो "Online Repair" (Office फिर download होता है)। App को /safe से शुरू करके देखें - तब चले तो खराब add-in कारण है (File → Options → Add-ins)।'
        $c = $chk.Data.C2R
        $exe = Join-Path $env:CommonProgramFiles 'Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
        if ($c -and (Test-Path -LiteralPath $exe)) {
            $plat = if ($c.Platform) { $c.Platform } else { 'x64' }
            $cul = if ($c.ClientCulture) { $c.ClientCulture } else { 'en-us' }
            try {
                Start-Process -FilePath $exe -ArgumentList "scenario=Repair platform=$plat culture=$cul RepairType=QuickRepair DisplayLevel=True" -ErrorAction Stop
                return (New-TSFix $null (TT 'I started the Office Quick Repair - follow its window.' 'Office Quick Repair सुरू केले - त्याच्या window प्रमाणे करा.' 'Office Quick Repair शुरू किया - उसकी window के अनुसार करें।') -Manual $man)
            } catch { }
        }
        Start-Process 'appwiz.cpl' -ErrorAction SilentlyContinue
        return (New-TSFix $null (TT 'I opened Programs and Features: select Microsoft Office → Change → Repair.' 'Programs and Features उघडले: Microsoft Office निवडा → Change → Repair.' 'Programs and Features खोला: Microsoft Office चुनें → Change → Repair.') -Manual $man)
    }
    NoVerify = $true
}

# "VCRUNTIME140.dll / MSVCP140.dll was not found"
function Get-TXVcMissing {
    $miss = @()
    $x64 = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue).Installed
    $x86 = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86' -ErrorAction SilentlyContinue).Installed
    if (-not $x86) { $x86 = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86' -ErrorAction SilentlyContinue).Installed }
    if ([Environment]::Is64BitOperatingSystem -and $x64 -ne 1) { $miss += 'x64' }
    if ($x86 -ne 1) { $miss += 'x86' }
    return $miss
}
$script:D['vcredist-dll'] = @{
    Check = {
        Step 'Checking the Visual C++ runtime (VCRUNTIME140 / MSVCP140)' 'Visual C++ runtime (VCRUNTIME140 / MSVCP140) तपासत आहे' 'Visual C++ runtime (VCRUNTIME140 / MSVCP140) जाँच रहे हैं'
        $miss = @(Get-TXVcMissing)
        $cr = @(Get-TXCrashes 14 | Where-Object { $_.Module -match '(?i)^(vcruntime|msvcp|ucrtbase|concrt|vcomp)' })
        $why = @()
        if ($miss.Count) { $why += TT "the Visual C++ 2015-2022 runtime is missing ($($miss -join ', ')) - many programs and games need it" "Visual C++ 2015-2022 runtime नाही ($($miss -join ', ')) - अनेक programs आणि games ना तो लागतो" "Visual C++ 2015-2022 runtime नहीं है ($($miss -join ', ')) - कई programs और games को यह चाहिए" }
        if ($cr.Count) { $why += TT "$($cr.Count) program crashes inside the C++ runtime ($(Format-TXList (@($cr | ForEach-Object App | Select-Object -Unique)) 3))" "C++ runtime मध्ये $($cr.Count) program crashes ($(Format-TXList (@($cr | ForEach-Object App | Select-Object -Unique)) 3))" "C++ runtime में $($cr.Count) program crashes ($(Format-TXList (@($cr | ForEach-Object App | Select-Object -Unique)) 3))" }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') @{ Miss = $miss }) }
        return (New-TSCheck $false (TT 'The Visual C++ 2015-2022 runtime is installed (32 and 64-bit) and no program crashed in it.' 'Visual C++ 2015-2022 runtime install आहे (32 आणि 64-bit) आणि त्यात कोणताही program crash झाला नाही.' 'Visual C++ 2015-2022 runtime install है (32 और 64-bit) और उसमें कोई program crash नहीं हुआ।'))
    }
    Fix = {
        param($chk)
        $arch = @('x86'); if ([Environment]::Is64BitOperatingSystem) { $arch = @('x64', 'x86') }
        $man = TT 'Download only from Microsoft: aka.ms/vs/17/release/vc_redist.x64.exe and vc_redist.x86.exe (install BOTH on 64-bit Windows). Never download single DLL files from "DLL" websites.' 'फक्त Microsoft कडून download करा: aka.ms/vs/17/release/vc_redist.x64.exe आणि vc_redist.x86.exe (64-bit Windows वर दोन्ही install करा). "DLL" websites वरून एकटी DLL file कधीही download करू नका.' 'सिर्फ़ Microsoft से download करें: aka.ms/vs/17/release/vc_redist.x64.exe और vc_redist.x86.exe (64-bit Windows पर दोनों install करें)। "DLL" websites से अकेली DLL file कभी download न करें।'
        if (-not (Test-TXWinget)) { return (New-TSFix $false (TT 'Windows'' package installer (winget) is not available here.' 'Windows चा package installer (winget) इथे उपलब्ध नाही.' 'Windows का package installer (winget) यहाँ उपलब्ध नहीं है।') -Manual $man) }
        Step 'Installing the Visual C++ runtime from Microsoft' 'Microsoft कडून Visual C++ runtime install करत आहे' 'Microsoft से Visual C++ runtime install कर रहे हैं'
        $ok = @(); foreach ($a in $arch) { if (Invoke-TXWinget "Microsoft.VCRedist.2015+.$a") { $ok += $a } }
        $left = @(Get-TXVcMissing)
        if (-not $left.Count) { return (New-TSFix $true (TT "I installed / repaired the Microsoft Visual C++ runtime ($($arch -join ', ')). Open the program again." "Microsoft Visual C++ runtime install / दुरुस्त केला ($($arch -join ', ')). Program पुन्हा उघडा." "Microsoft Visual C++ runtime install / ठीक किया ($($arch -join ', '))। Program फिर खोलें।")) }
        return (New-TSFix $false (TT "The runtime could not be installed (no internet?) - still missing: $($left -join ', ')." "Runtime install होऊ शकला नाही (internet नाही?) - अजून नाही: $($left -join ', ')." "Runtime install नहीं हो सका (internet नहीं?) - अभी नहीं: $($left -join ', ')।") -Manual $man)
    }
    NoVerify = $true
}

# games: d3dx9_43.dll / xinput1_3.dll missing
$script:D['directx-games'] = @{
    Check = {
        Step 'Checking the DirectX files games need' 'Games ना लागणाऱ्या DirectX files तपासत आहे' 'Games को चाहिए DirectX files जाँच रहे हैं'
        $dirs = @("$env:WINDIR\System32"); if ([Environment]::Is64BitOperatingSystem) { $dirs += "$env:WINDIR\SysWOW64" }
        $miss = @(foreach ($d in $dirs) { foreach ($f in 'd3dx9_43.dll', 'xinput1_3.dll', 'd3dcompiler_43.dll') { if (-not (Test-Path -LiteralPath (Join-Path $d $f))) { "$f ($(Split-Path $d -Leaf))" } } })
        if ($miss.Count) { return (New-TSCheck $true (TT "Older DirectX files that many games need are missing: $(Format-TXList $miss 3)." "अनेक games ना लागणाऱ्या जुन्या DirectX files नाहीत: $(Format-TXList $miss 3)." "कई games को चाहिए पुरानी DirectX files नहीं हैं: $(Format-TXList $miss 3)।")) }
        return (New-TSCheck $null (TT 'The DirectX files are present. If a game still crashes, update the graphics driver and install the Visual C++ runtime.' 'DirectX files आहेत. Game तरीही crash होत असेल तर graphics driver update करा आणि Visual C++ runtime install करा.' 'DirectX files हैं। Game फिर भी crash हो तो graphics driver update करें और Visual C++ runtime install करें।'))
    }
    Fix = {
        $man = TT 'Official installer: Microsoft "DirectX End-User Runtime Web Installer" (dxwebsetup.exe) from microsoft.com. Never copy single DLLs from DLL websites.' 'अधिकृत installer: microsoft.com वरील Microsoft "DirectX End-User Runtime Web Installer" (dxwebsetup.exe). DLL websites वरून एकट्या DLL कधीही copy करू नका.' 'आधिकारिक installer: microsoft.com का Microsoft "DirectX End-User Runtime Web Installer" (dxwebsetup.exe)। DLL websites से अकेली DLL कभी copy न करें।'
        Step 'Installing the DirectX runtime from Microsoft' 'Microsoft कडून DirectX runtime install करत आहे' 'Microsoft से DirectX runtime install कर रहे हैं'
        if (Invoke-TXWinget 'Microsoft.DirectX') {
            $after = & $script:D['directx-games'].Check
            if ($after.Found -ne $true) { return (New-TSFix $true (TT 'I installed the Microsoft DirectX runtime. Start the game again.' 'Microsoft DirectX runtime install केला. Game पुन्हा सुरू करा.' 'Microsoft DirectX runtime install किया। Game फिर शुरू करें।')) }
        }
        return (New-TSFix $false (TT 'The DirectX runtime could not be installed automatically (no internet / winget?).' 'DirectX runtime आपोआप install होऊ शकला नाही (internet / winget नाही?).' 'DirectX runtime अपने आप install नहीं हो सका (internet / winget नहीं?)।') -Manual $man)
    }
    NoVerify = $true
}

# .NET Framework 3.5 / .NET runtime errors
$script:D['dotnet-runtime'] = @{
    Check = {
        Step 'Checking .NET Framework' '.NET Framework तपासत आहे' '.NET Framework जाँच रहे हैं'
        $why = @(); $data = @{}
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
            if ($f.State -ne 'Enabled') { $why += TT '.NET Framework 3.5 is off - older programs (billing, Tally add-ons, government utilities) ask for it' '.NET Framework 3.5 बंद आहे - जुने programs (billing, Tally add-ons, सरकारी utilities) तो मागतात' '.NET Framework 3.5 बंद है - पुराने programs (billing, Tally add-ons, सरकारी utilities) इसे माँगते हैं'; $data.Fx3 = $true }
        } catch { }
        $ev = @(Get-TXEvents 'Application' @(1026) '.NET Runtime' 14)
        if ($ev.Count) {
            $apps = Format-TXList (@($ev | ForEach-Object { if ($_.Message -match '(?im)^Application:\s*(\S+)') { $Matches[1] } } | Select-Object -Unique)) 3
            $why += TT "$($ev.Count) .NET program crashes in 14 days ($apps)" "14 दिवसांत $($ev.Count) .NET program crashes ($apps)" "14 दिनों में $($ev.Count) .NET program crashes ($apps)"; $data.Crash = $true
        }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT '.NET Framework 3.5 is on and no .NET program crashed recently.' '.NET Framework 3.5 चालू आहे आणि अलीकडे कोणताही .NET program crash झाला नाही.' '.NET Framework 3.5 चालू है और हाल में कोई .NET program crash नहीं हुआ।'))
    }
    Fix = {
        param($chk)
        $man = TT 'If a program asks for ".NET Desktop Runtime 6 / 8", install exactly that version from Microsoft (dotnet.microsoft.com). Damaged .NET 4.x: Microsoft .NET Framework Repair Tool (aka.ms/DotnetRepairTool). Java programs: install Java from java.com / adoptium.net only.' 'Program ".NET Desktop Runtime 6 / 8" मागत असेल तर तीच version Microsoft कडून (dotnet.microsoft.com) install करा. बिघडलेले .NET 4.x: Microsoft .NET Framework Repair Tool (aka.ms/DotnetRepairTool). Java programs: Java फक्त java.com / adoptium.net वरून.' 'Program ".NET Desktop Runtime 6 / 8" माँगे तो वही version Microsoft से (dotnet.microsoft.com) install करें। खराब .NET 4.x: Microsoft .NET Framework Repair Tool (aka.ms/DotnetRepairTool)। Java programs: Java सिर्फ़ java.com / adoptium.net से।'
        if (-not $chk.Data.Fx3) { return (New-TSFix $null (TT '.NET 3.5 is already on; the crashing program needs its own runtime or a reinstall.' '.NET 3.5 आधीच चालू आहे; crash होणाऱ्या program ला स्वतःचा runtime किंवा reinstall लागतो.' '.NET 3.5 पहले से चालू है; crash होने वाले program को अपना runtime या reinstall चाहिए।') -Manual $man) }
        Step 'Turning on .NET Framework 3.5 (downloads from Windows Update, a few minutes)' '.NET Framework 3.5 चालू करत आहे (Windows Update वरून download, काही मिनिटे)' '.NET Framework 3.5 चालू कर रहे हैं (Windows Update से download, कुछ मिनट)'
        $code = Invoke-PDProcess -FilePath "$env:WINDIR\System32\dism.exe" -Arguments '/Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart' -ProgressLabel '.NET 3.5'
        if ($code -eq 0 -or $code -eq 3010) { return (New-TSFix $true (TT 'I turned on .NET Framework 3.5.' '.NET Framework 3.5 चालू केले.' '.NET Framework 3.5 चालू किया।') -Manual $man) }
        return (New-TSFix $false (TT ".NET 3.5 could not be turned on (DISM code $code) - it needs internet / Windows Update." ".NET 3.5 चालू होऊ शकले नाही (DISM code $code) - internet / Windows Update लागते." ".NET 3.5 चालू नहीं हो सका (DISM code $code) - internet / Windows Update चाहिए।") -Manual (Add-TT (TT 'Offline: mount the same Windows ISO and run "DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /Source:X:\sources\sxs /LimitAccess".' 'Offline: त्याच Windows ची ISO mount करून "DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /Source:X:\sources\sxs /LimitAccess" चालवा.' 'Offline: उसी Windows की ISO mount करके "DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /Source:X:\sources\sxs /LimitAccess" चलाएँ।') $man))
    }
    NoVerify = $true
}

# a program closes as soon as it opens - read the crash log and route to the right fix
$script:D['app-crash'] = @{
    Check = {
        Step 'Reading the program crash log' 'Program crash log वाचत आहे' 'Program crash log पढ़ रहे हैं'
        $cr = @(Get-TXCrashes 7 | Where-Object { $_.App -notmatch '^(?i)(explorer|svchost|searchhost|searchapp|backgroundtaskhost|runtimebroker)\.exe$' })
        if (-not $cr.Count) { return (New-TSCheck $false (TT 'No program crashed in the last 7 days.' 'मागच्या 7 दिवसांत कोणताही program crash झाला नाही.' 'पिछले 7 दिनों में कोई program crash नहीं हुआ।')) }
        $g = @($cr | Group-Object App | Sort-Object Count -Descending | Select-Object -First 3)
        $list = ($g | ForEach-Object { $m = @($_.Group | ForEach-Object Module | Select-Object -Unique)[0]; "$($_.Name) ×$($_.Count) ($m)" }) -join '; '
        return (New-TSCheck $true (TT "Programs that crashed this week: $list" "या आठवड्यात crash झालेले programs: $list" "इस हफ़्ते crash हुए programs: $list") @{ Mods = @($cr | ForEach-Object Module | Select-Object -Unique) })
    }
    Fix = {
        param($chk)
        $mods = (@($chk.Data.Mods) -join ' ')
        if ($mods -match '(?i)vcruntime|msvcp|ucrtbase' -and @(Get-TXVcMissing).Count) { return (& $script:D['vcredist-dll'].Fix (& $script:D['vcredist-dll'].Check)) }
        $hint = @()
        if ($mods -match '(?i)vcruntime|msvcp|ucrtbase') { $hint += TT 'Visual C++ runtime: reinstall it (vc_redist x64 + x86 from Microsoft).' 'Visual C++ runtime: पुन्हा install करा (Microsoft चे vc_redist x64 + x86).' 'Visual C++ runtime: फिर install करें (Microsoft के vc_redist x64 + x86)।' }
        if ($mods -match '(?i)clr\.dll|coreclr|mscor|\.ni\.dll') { $hint += TT '.NET: repair .NET / install the runtime the program asks for.' '.NET: .NET दुरुस्त करा / program मागतो तो runtime install करा.' '.NET: .NET ठीक करें / program जो runtime माँगे वह install करें।' }
        if ($mods -match '(?i)d3d|dxgi|xinput|nvwgf|nvd3d|atidxx|amdxx|igd|ig\d') { $hint += TT 'Graphics: install the latest graphics driver from Intel / NVIDIA / AMD and the DirectX runtime.' 'Graphics: Intel / NVIDIA / AMD कडून नवीन graphics driver आणि DirectX runtime install करा.' 'Graphics: Intel / NVIDIA / AMD से नया graphics driver और DirectX runtime install करें।' }
        if ($mods -match '(?i)ntdll|kernelbase|unknown') { $hint += TT 'Windows / the program itself: update or reinstall the program, then repair the system files (DISM + SFC).' 'Windows / program स्वतः: program update किंवा reinstall करा, मग system files दुरुस्त करा (DISM + SFC).' 'Windows / program खुद: program update या reinstall करें, फिर system files ठीक करें (DISM + SFC)।' }
        if (-not $hint.Count) { $hint += TT 'The crash is inside the named module: update or reinstall the program that owns it; an antivirus or overlay (screen recorder, game booster) can also be the cause.' 'Crash दाखवलेल्या module मध्ये आहे: तो ज्याचा आहे तो program update / reinstall करा; antivirus किंवा overlay (screen recorder, game booster) सुद्धा कारण असू शकते.' 'Crash दिखाए गए module में है: वह जिसका है वह program update / reinstall करें; antivirus या overlay (screen recorder, game booster) भी कारण हो सकता है।' }
        return (New-TSFix $null (TT 'I read the crash details; this is what to do:' 'Crash ची माहिती वाचली; हे करा:' 'Crash की जानकारी पढ़ी; यह करें:') -Manual (Join-TT $hint ' '))
    }
    NoVerify = $true
}

# microphone / camera blocked for apps (Zoom, Teams, Meet, WhatsApp)
$script:D['meeting-av'] = @{
    Check = {
        Step 'Checking microphone and camera permission for apps' 'Apps साठी microphone आणि camera परवानगी तपासत आहे' 'Apps के लिए microphone और camera अनुमति जाँच रहे हैं'
        $deny = @()
        foreach ($cap in 'microphone', 'webcam') {
            foreach ($k in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap", "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap", "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap\NonPackaged")) {
                if ((Get-ItemProperty -Path $k -Name Value -ErrorAction SilentlyContinue).Value -eq 'Deny') { $deny += [pscustomobject]@{ Cap = $cap; Key = $k } }
            }
        }
        if ($deny.Count) {
            $c = Format-TXList (@($deny | ForEach-Object { if ($_.Cap -eq 'webcam') { 'camera' } else { 'microphone' } } | Select-Object -Unique)) 2
            return (New-TSCheck $true (TT "The $c is blocked for apps in the Windows privacy settings - Zoom / Teams / Meet / WhatsApp cannot use it." "Windows privacy settings मध्ये apps साठी $c बंद आहे - Zoom / Teams / Meet / WhatsApp ते वापरू शकत नाहीत." "Windows privacy settings में apps के लिए $c बंद है - Zoom / Teams / Meet / WhatsApp उसे इस्तेमाल नहीं कर सकते।") @{ Deny = $deny })
        }
        return (New-TSCheck $null (TT 'Microphone and camera are allowed for apps. In the meeting app choose the right microphone / camera in its own settings, and close other apps that use the camera.' 'Apps साठी microphone आणि camera परवानगी आहे. Meeting app च्या settings मध्ये योग्य microphone / camera निवडा, आणि camera वापरणारे इतर apps बंद करा.' 'Apps के लिए microphone और camera की अनुमति है। Meeting app की settings में सही microphone / camera चुनें, और camera इस्तेमाल करने वाले दूसरे apps बंद करें।'))
    }
    Fix = {
        param($chk)
        New-TSRestorePointOnce
        $n = 0
        foreach ($d in @($chk.Data.Deny)) { try { Set-PDRegValue -Path $d.Key -Name 'Value' -Value 'Allow' -Type String; $n++ } catch { } }
        if (-not $n) { return (New-TSFix $false (TT 'The permission could not be changed.' 'परवानगी बदलता आली नाही.' 'अनुमति बदली नहीं जा सकी।') -Manual (TT 'Settings → Privacy → Microphone / Camera → allow apps and desktop apps.' 'Settings → Privacy → Microphone / Camera → apps आणि desktop apps ना परवानगी द्या.' 'Settings → Privacy → Microphone / Camera → apps और desktop apps को अनुमति दें।')) }
        return (New-TSFix $true (TT 'I allowed apps to use the microphone / camera again. Restart the meeting app.' 'Apps ना microphone / camera पुन्हा वापरू दिले. Meeting app पुन्हा सुरू करा.' 'Apps को microphone / camera फिर इस्तेमाल करने दिया। Meeting app फिर शुरू करें।'))
    }
}

# "Access denied" / cannot save - Controlled folder access (ransomware protection)
$script:D['file-locked'] = @{
    Check = {
        Step 'Checking ransomware protection and blocked programs' 'Ransomware protection आणि अडवलेले programs तपासत आहे' 'Ransomware protection और रोके गए programs जाँच रहे हैं'
        $cfa = $null; try { $cfa = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess } catch { }
        $ev = @(Get-TXEvents 'Microsoft-Windows-Windows Defender/Operational' @(1123) $null 14)
        if ($ev.Count) {
            $apps = Format-TXList (@($ev | ForEach-Object { if ($_.Message -match '(?im)(Process Name|प्रक्रिया)[^:]*:\s*(\S.+)$') { Split-Path $Matches[2].Trim() -Leaf } } | Select-Object -Unique)) 3
            return (New-TSCheck $true (TT "Windows ransomware protection blocked programs from saving files $($ev.Count) times ($apps)." "Windows ransomware protection ने programs ना files save करण्यापासून $($ev.Count) वेळा अडवले ($apps)." "Windows ransomware protection ने programs को files save करने से $($ev.Count) बार रोका ($apps)।"))
        }
        $t = if ($cfa -eq 1) { TT 'Ransomware protection (Controlled folder access) is on but blocked nothing recently.' 'Ransomware protection (Controlled folder access) चालू आहे पण अलीकडे काहीही अडवले नाही.' 'Ransomware protection (Controlled folder access) चालू है पर हाल में कुछ नहीं रोका।' } else { TT 'No program was blocked by ransomware protection.' 'Ransomware protection ने कोणताही program अडवला नाही.' 'Ransomware protection ने कोई program नहीं रोका।' }
        return (New-TSCheck $null (Add-TT $t (TT 'A file "in use" is held by an open program - close it, or find it with Process Explorer (Find → Handle).' '"In use" file एखाद्या उघड्या program ने धरलेली असते - तो बंद करा, किंवा Process Explorer (Find → Handle) ने शोधा.' '"In use" file किसी खुले program ने पकड़ी होती है - उसे बंद करें, या Process Explorer (Find → Handle) से खोजें।')))
    }
    Fix = {
        Start-Process 'windowsdefender://ransomwareprotection' -ErrorAction SilentlyContinue
        return (New-TSFix $null (TT 'I opened Ransomware protection.' 'Ransomware protection उघडले.' 'Ransomware protection खोला।') -Manual (TT 'If the blocked program is one you trust (Tally, billing, a scanner app): "Allow an app through Controlled folder access" → add it. Keep the protection on.' 'अडवलेला program विश्वासाचा असेल (Tally, billing, scanner app): "Allow an app through Controlled folder access" → तो जोडा. Protection चालूच ठेवा.' 'रोका गया program भरोसेमंद हो (Tally, billing, scanner app): "Allow an app through Controlled folder access" → उसे जोड़ें। Protection चालू ही रखें।'))
    }
    NoVerify = $true
}


# ================================================================== HARDWARE / STORAGE

# laptop "plugged in, not charging" (charge limit in the maker's app)
$script:D['charge-limit'] = @{
    Check = {
        Step 'Checking the charger and the battery charging' 'Charger आणि battery charging तपासत आहे' 'Charger और battery charging जाँच रहे हैं'
        $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $b) { return (New-TSCheck $false (TT 'This PC has no battery.' 'या PC ला battery नाही.' 'इस PC में battery नहीं है।')) }
        $pct = [int]$b.EstimatedChargeRemaining
        $vendor = Format-TXList (@(Get-TXInstalled '(?i)Vantage|MyASUS|ASUS Battery|Dell Power Manager|Dell Optimizer|HP Support Assistant|Care Center|Battery Health|Armoury Crate|MSI Center' | ForEach-Object DisplayName | Select-Object -Unique) + @(Get-AppxPackage -Name '*LenovoCompanion*', '*LenovoVantage*', '*ASUSPCAssistant*', '*MyASUS*' -ErrorAction SilentlyContinue | ForEach-Object Name)) 2
        if ($b.BatteryStatus -in 6, 7, 8, 9) { return (New-TSCheck $false (TT "The battery is charging ($pct%)." "Battery charge होत आहे ($pct%)." "Battery charge हो रही है ($pct%)।")) }
        if ($b.BatteryStatus -eq 2 -and $pct -lt 96) {
            $lim = if ($pct -ge 48 -and $pct -le 82) { TT ' - this is typical of a battery charge limit (conservation / battery-health mode)' ' - हे battery charge limit (conservation / battery-health mode) चे लक्षण आहे' ' - यह battery charge limit (conservation / battery-health mode) का लक्षण है' } else { TT '' '' '' }
            $vt = if ($vendor) { TT " The maker's app is installed: $vendor." " कंपनीचे app install आहे: $vendor." " कंपनी का app install है: $vendor।" } else { TT '' '' '' }
            return (New-TSCheck $true (TT "Plugged in but not charging at $pct%$($lim.en).$($vt.en)" "Charger लावलेला आहे पण $pct% वर charging होत नाही$($lim.mr).$($vt.mr)" "Charger लगा है पर $pct% पर charging नहीं हो रही$($lim.hi)।$($vt.hi)") @{ Pct = $pct; Vendor = $vendor })
        }
        if ($b.BatteryStatus -eq 1) { return (New-TSCheck $null (TT "Running on battery ($pct%) - plug in the charger and check again. If Windows still shows no charger, the adapter, its cable or the DC jack is faulty." "Battery वर चालू आहे ($pct%) - charger लावून पुन्हा तपासा. तरीही Windows ला charger दिसत नसेल तर adapter, त्याची cable किंवा DC jack खराब आहे." "Battery पर चल रहा है ($pct%) - charger लगाकर फिर जाँचें। फिर भी Windows को charger न दिखे तो adapter, उसकी cable या DC jack खराब है।")) }
        return (New-TSCheck $false (TT "On the charger, battery at $pct%." "Charger वर, battery $pct%." "Charger पर, battery $pct%।"))
    }
    Fix = {
        param($chk)
        return (New-TSFix $null (TT 'A charge limit protects the battery, so I did not change it.' 'Charge limit battery चे संरक्षण करते, म्हणून ते बदलले नाही.' 'Charge limit battery की सुरक्षा करता है, इसलिए उसे नहीं बदला।') -Manual (TT 'To charge to 100%: Lenovo Vantage → Battery → Conservation mode off; MyASUS → Battery Health Charging → Full capacity; Dell Power Manager → Battery → Standard; HP: BIOS → Battery care / Adaptive off; Acer Care Center → charge limit off. If no limit is set: try the original-wattage charger; if still not charging, the battery / charging circuit needs service.' '100% charge साठी: Lenovo Vantage → Battery → Conservation mode बंद; MyASUS → Battery Health Charging → Full capacity; Dell Power Manager → Battery → Standard; HP: BIOS → Battery care / Adaptive बंद; Acer Care Center → charge limit बंद. Limit नसेल तर: मूळ wattage चा charger वापरून पाहा; तरीही charge होत नसेल तर battery / charging circuit service ला द्या.' '100% charge के लिए: Lenovo Vantage → Battery → Conservation mode बंद; MyASUS → Battery Health Charging → Full capacity; Dell Power Manager → Battery → Standard; HP: BIOS → Battery care / Adaptive बंद; Acer Care Center → charge limit बंद। Limit न हो तो: मूल wattage का charger लगाकर देखें; फिर भी charge न हो तो battery / charging circuit service में दें।'))
    }
    NoVerify = $true
}

# screen flicker / "display driver stopped responding"
$script:D['screen-flicker'] = @{
    Check = {
        Step 'Looking for display driver crashes' 'Display driver crashes शोधत आहे' 'Display driver crashes खोज रहे हैं'
        $ev = @(Get-TXEvents 'System' @(4101) 'Display' 14)
        $lk = @(Get-ChildItem "$env:WINDIR\LiveKernelReports" -Recurse -File -Filter *.dmp -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-14) -and $_.FullName -match '(?i)watchdog|141|117' })
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)remote|virtual|parsec|mirage' } | Select-Object -First 1
        $drv = if ($gpu) { "$($gpu.Name) $($gpu.DriverVersion) ($(([datetime]$gpu.DriverDate).ToString('dd-MM-yyyy')))" } else { '-' }
        $n = $ev.Count + $lk.Count
        if ($n) { return (New-TSCheck $true (TT "The display driver stopped responding $n times in 14 days (graphics: $drv)." "14 दिवसांत display driver $n वेळा बंद पडला (graphics: $drv)." "14 दिनों में display driver $n बार रुका (graphics: $drv)।") @{ Gpu = $drv }) }
        return (New-TSCheck $null (TT "No display driver crashes were recorded (graphics: $drv). If the flicker also shows in the BIOS / start-up logo, it is the screen or its cable (hardware)." "Display driver crash ची नोंद नाही (graphics: $drv). BIOS / सुरुवातीच्या logo वरही flicker असेल तर screen किंवा तिची cable (hardware) खराब आहे." "Display driver crash का रिकॉर्ड नहीं (graphics: $drv)। BIOS / शुरुआती logo पर भी flicker हो तो screen या उसकी cable (hardware) खराब है।"))
    }
    Fix = {
        param($chk)
        return (New-TSFix $null (TT "The graphics driver ($($chk.Data.Gpu)) is unstable." "Graphics driver ($($chk.Data.Gpu)) अस्थिर आहे." "Graphics driver ($($chk.Data.Gpu)) अस्थिर है।") -Manual (TT 'If it started after an update: Device Manager → Display adapters → Properties → Driver → Roll Back. Otherwise install the driver from the laptop maker / Intel / AMD / NVIDIA. Turn off panel power saving (Intel PSR / AMD Vari-Bright). If the flicker shows in the BIOS too, the screen or its cable needs repair.' 'Update नंतर सुरू झाले असेल तर: Device Manager → Display adapters → Properties → Driver → Roll Back. नाहीतर laptop कंपनी / Intel / AMD / NVIDIA कडून driver install करा. Panel power saving (Intel PSR / AMD Vari-Bright) बंद करा. BIOS मध्येही flicker असेल तर screen किंवा cable दुरुस्त करावी लागेल.' 'Update के बाद शुरू हुआ हो तो: Device Manager → Display adapters → Properties → Driver → Roll Back. वरना laptop कंपनी / Intel / AMD / NVIDIA से driver install करें। Panel power saving (Intel PSR / AMD Vari-Bright) बंद करें। BIOS में भी flicker हो तो screen या cable ठीक करानी होगी।'))
    }
    NoVerify = $true
}

# brightness slider missing / brightness keys do nothing
$script:D['brightness'] = @{
    Check = {
        Step 'Checking the brightness control' 'Brightness control तपासत आहे' 'Brightness control जाँच रहे हैं'
        if (-not (Test-TSIsLaptop)) { return (New-TSCheck $null (TT 'On a desktop PC the brightness is set with the buttons on the monitor itself.' 'Desktop PC वर brightness monitor वरच्या buttons ने बदलतात.' 'Desktop PC पर brightness monitor के buttons से बदलती है।')) }
        $why = @(); $data = @{}
        $br = $null; try { $br = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1 } catch { }
        if (-not $br) { $why += TT 'Windows has no brightness control for the screen' 'Windows कडे screen च्या brightness चे control नाही' 'Windows के पास screen की brightness का control नहीं है' }
        if (@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)basic display' }).Count) { $why += TT 'the graphics driver is missing (Microsoft Basic Display Adapter)' 'graphics driver नाही (Microsoft Basic Display Adapter)' 'graphics driver नहीं है (Microsoft Basic Display Adapter)'; $data.Basic = $true }
        $mon = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue | Where-Object { $_.Status -in 'Error', 'Degraded' -or $_.Problem -eq 22 })
        if ($mon.Count) { $why += TT 'the monitor device is switched off in Device Manager' 'Device Manager मध्ये monitor device बंद आहे' 'Device Manager में monitor device बंद है'; $data.Mon = $mon }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT "The brightness control works (now $($br.CurrentBrightness)%). If the Fn keys do nothing, install the maker's hotkey utility." "Brightness control चालते (आत्ता $($br.CurrentBrightness)%). Fn keys चालत नसतील तर कंपनीचे hotkey utility install करा." "Brightness control चलता है (अभी $($br.CurrentBrightness)%)। Fn keys न चलें तो कंपनी का hotkey utility install करें।"))
    }
    Fix = {
        param($chk)
        New-TSRestorePointOnce
        foreach ($m in @($chk.Data.Mon)) { try { Enable-PnpDevice -InstanceId $m.InstanceId -Confirm:$false -ErrorAction Stop } catch { } }
        [void](Repair-TSDevices @(Get-TSProblemDevices @('Display', 'Monitor')))
        $after = & $script:D['brightness'].Check
        if ($after.Found -ne $true) { return (New-TSFix $true (TT 'I switched the monitor / display devices on again - the brightness slider is back.' 'Monitor / display devices पुन्हा चालू केले - brightness slider परत आला.' 'Monitor / display devices फिर चालू किए - brightness slider वापस आ गया।')) }
        return (New-TSFix $false (TT 'Brightness still cannot be controlled.' 'Brightness अजूनही बदलता येत नाही.' 'Brightness अभी भी नहीं बदल सकती।') -Manual (TT 'Install the graphics driver from the laptop maker / Intel / AMD (Repair → Drivers). Remote tools (TeamViewer / AnyDesk) can replace the monitor driver - Device Manager → Monitors → choose "Generic PnP Monitor". If the screen stays dim at every setting, the backlight is faulty (hardware).' 'Laptop कंपनी / Intel / AMD कडून graphics driver install करा (दुरुस्ती → Drivers). Remote tools (TeamViewer / AnyDesk) monitor driver बदलू शकतात - Device Manager → Monitors → "Generic PnP Monitor" निवडा. प्रत्येक setting वर screen मंदच राहत असेल तर backlight खराब आहे (hardware).' 'Laptop कंपनी / Intel / AMD से graphics driver install करें (मरम्मत → Drivers)। Remote tools (TeamViewer / AnyDesk) monitor driver बदल सकते हैं - Device Manager → Monitors → "Generic PnP Monitor" चुनें। हर setting पर screen धुंधली रहे तो backlight खराब है (hardware)।'))
    }
    NoVerify = $true
}

# pendrive / SD card "The disk is write protected"
$script:SdpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
$script:D['usb-write-protected'] = @{
    Check = {
        Step 'Checking pendrives and memory cards for write protection' 'Pendrive आणि memory cards चे write protection तपासत आहे' 'Pendrive और memory cards का write protection जाँच रहे हैं'
        $why = @(); $data = @{}
        $ro = @(); try { $ro = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -in 'USB', 'SD', 'MMC' -and $_.IsReadOnly }) } catch { }
        if ($ro.Count) { $why += TT "read-only: $(Format-TXList ($ro | ForEach-Object FriendlyName) 2)" "फक्त वाचता येणारे (read-only): $(Format-TXList ($ro | ForEach-Object FriendlyName) 2)" "सिर्फ़ पढ़ने लायक (read-only): $(Format-TXList ($ro | ForEach-Object FriendlyName) 2)"; $data.Disks = @($ro | ForEach-Object Number) }
        if ((Get-ItemProperty $script:SdpKey -Name WriteProtect -ErrorAction SilentlyContinue).WriteProtect -eq 1) { $why += TT 'Windows is set to block writing to all USB drives (WriteProtect = 1)' 'Windows सगळ्या USB drives वर लिहिणे बंद ठेवण्यासाठी लावलेले आहे (WriteProtect = 1)' 'Windows सभी USB drives पर लिखना बंद रखने के लिए लगा है (WriteProtect = 1)'; $data.Reg = $true }
        $pol = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}' -ErrorAction SilentlyContinue
        if ($pol.Deny_Write -eq 1) { $why += TT 'a policy blocks writing to removable disks (office PC setting)' 'Policy removable disks वर लिहिणे अडवते (office PC setting)' 'Policy removable disks पर लिखना रोकती है (office PC setting)'; $data.Pol = $true }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        $n = @(Get-TXRemovableRoots).Count
        if (-not $n) { return (New-TSCheck $null (TT 'No pendrive / memory card is plugged in - plug it in and check again. Also check the small lock switch on SD cards.' 'Pendrive / memory card लावलेले नाही - लावून पुन्हा तपासा. SD card वरचा छोटा lock switch पण पाहा.' 'Pendrive / memory card नहीं लगा - लगाकर फिर जाँचें। SD card का छोटा lock switch भी देखें।')) }
        return (New-TSCheck $false (TT 'The plugged-in pendrives / cards are writable.' 'लावलेल्या pendrives / cards वर लिहिता येते.' 'लगे pendrives / cards पर लिखा जा सकता है।'))
    }
    Fix = {
        param($chk)
        New-TSRestorePointOnce
        $did = @()
        foreach ($n in @($chk.Data.Disks)) { try { Set-Disk -Number $n -IsReadOnly $false -ErrorAction Stop; $did += "disk $n" } catch { } }
        if ($chk.Data.Reg) { try { Set-PDRegValue -Path $script:SdpKey -Name WriteProtect -Value 0; $did += 'WriteProtect = 0' } catch { } }
        $still = @(); try { $still = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -in 'USB', 'SD', 'MMC' -and $_.IsReadOnly }) } catch { }
        $man = TT 'Copy the data off first. A pendrive that stays read-only on every PC has a worn-out / locked chip - it cannot be repaired, replace it. SD card: slide the lock switch up.' 'आधी data काढून घ्या. प्रत्येक PC वर read-only राहणाऱ्या pendrive ची chip झिजलेली / locked आहे - ती दुरुस्त होत नाही, बदला. SD card: lock switch वर सरकवा.' 'पहले data निकाल लें। हर PC पर read-only रहने वाली pendrive की chip घिस गई / locked है - वह ठीक नहीं होती, बदलें। SD card: lock switch ऊपर करें।'
        if ($chk.Data.Pol) { $man = Add-TT (TT 'The write block comes from a policy: on an office PC ask the IT admin.' 'लिहिण्याची बंदी policy मुळे आहे: office PC वर IT admin ला विचारा.' 'लिखने की रोक policy से है: office PC पर IT admin से पूछें।') $man }
        if ($did.Count -and -not $still.Count) { return (New-TSFix $true (TT "I removed the write protection ($($did -join ', ')). Unplug and plug the pendrive in again." "Write protection काढले ($($did -join ', ')). Pendrive काढून पुन्हा लावा." "Write protection हटाया ($($did -join ', '))। Pendrive निकालकर फिर लगाएँ।") -Manual $man) }
        return (New-TSFix $false (TT 'The drive is still read-only - the lock is inside the pendrive / card itself (hardware).' 'Drive अजूनही read-only आहे - lock pendrive / card च्या आतच आहे (hardware).' 'Drive अभी भी read-only है - lock pendrive / card के अंदर ही है (hardware)।') -Manual $man)
    }
    NoVerify = $true
}

# pendrive / card / external disk shows RAW, 0 bytes or "You need to format the disk"
$script:D['usb-raw'] = @{
    Check = {
        Step 'Checking pendrives and external disks' 'Pendrives आणि external disks तपासत आहे' 'Pendrives और external disks जाँच रहे हैं'
        $why = @()
        try {
            foreach ($d in @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -in 'USB', 'SD', 'MMC' })) {
                if (-not $d.Size -or $d.OperationalStatus -match '(?i)no media') { $why += TT "$($d.FriendlyName) shows 0 bytes / No media - the controller has failed (hardware)" "$($d.FriendlyName) 0 bytes / No media दाखवतो - controller खराब झाला आहे (hardware)" "$($d.FriendlyName) 0 bytes / No media दिखाता है - controller खराब हो गया है (hardware)"; continue }
                if ($d.PartitionStyle -eq 'RAW') { $why += TT "$($d.FriendlyName) has no partition table (shows as Not Initialized)" "$($d.FriendlyName) ला partition table नाही (Not Initialized दिसते)" "$($d.FriendlyName) में partition table नहीं है (Not Initialized दिखता है)"; continue }
                foreach ($v in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue)) {
                    if ($v.FileSystemType -in 'Unknown', 'RAW' -or (-not $v.FileSystem -and $v.Size -gt 0)) { $why += TT "$($d.FriendlyName) $($v.DriveLetter): is RAW - Windows asks to format it" "$($d.FriendlyName) $($v.DriveLetter): RAW आहे - Windows format करायला सांगते" "$($d.FriendlyName) $($v.DriveLetter): RAW है - Windows format करने को कहता है" }
                }
            }
        } catch { }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ')) }
        if (-not @(Get-TXRemovableRoots).Count) { return (New-TSCheck $null (TT 'No pendrive / external disk is plugged in - plug it in (directly, not through a hub) and check again.' 'Pendrive / external disk लावलेले नाही - थेट (hub शिवाय) लावून पुन्हा तपासा.' 'Pendrive / external disk नहीं लगा - सीधे (hub के बिना) लगाकर फिर जाँचें।')) }
        return (New-TSCheck $false (TT 'The plugged-in pendrives / disks have a normal file system.' 'लावलेल्या pendrives / disks ची file system नेहमीसारखी आहे.' 'लगे pendrives / disks का file system सामान्य है।'))
    }
    Fix = {
        return (New-TSFix $false (TT 'I did not touch the drive: formatting or "repairing" it can destroy the data.' 'Drive ला हात लावला नाही: format किंवा "repair" केल्याने data नष्ट होऊ शकतो.' 'Drive को हाथ नहीं लगाया: format या "repair" करने से data नष्ट हो सकता है।') -Manual (TT 'Do NOT format if the data is needed. Recover the files to ANOTHER drive with TestDisk / PhotoRec or DMDE (Tools guide), then format the pendrive. 0 bytes / No media = dead controller: only a data-recovery lab can help. External HDD clicking: stop using it.' 'Data हवा असेल तर format करू नका. TestDisk / PhotoRec किंवा DMDE (Tools मार्गदर्शक) ने files दुसऱ्या drive वर परत मिळवा, मग pendrive format करा. 0 bytes / No media = controller खराब: फक्त data-recovery lab मदत करू शकते. External HDD टिक-टिक करत असेल तर वापर थांबवा.' 'Data चाहिए तो format न करें। TestDisk / PhotoRec या DMDE (Tools गाइड) से files दूसरे drive पर वापस लाएँ, फिर pendrive format करें। 0 bytes / No media = controller खराब: सिर्फ़ data-recovery lab मदद कर सकती है। External HDD टिक-टिक करे तो इस्तेमाल बंद करें।'))
    }
    NoVerify = $true
}

# new SSD / HDD not showing in This PC
$script:D['new-disk-missing'] = @{
    Check = {
        Step 'Checking all disks for missing drive letters' 'सगळ्या disks वर हरवलेले drive letters तपासत आहे' 'सभी disks पर गायब drive letters जाँच रहे हैं'
        $why = @(); $data = @{ Off = @(); NoLetter = @(); Raw = @() }
        try {
            foreach ($d in @(Get-Disk -ErrorAction Stop)) {
                if ($d.IsOffline) { $data.Off += $d.Number; $why += TT "disk $($d.Number) ($($d.FriendlyName)) is Offline" "disk $($d.Number) ($($d.FriendlyName)) Offline आहे" "disk $($d.Number) ($($d.FriendlyName)) Offline है"; continue }
                if ($d.PartitionStyle -eq 'RAW' -and $d.Size -gt 1GB -and $d.BusType -notin 'USB', 'SD', 'MMC') { $data.Raw += $d.Number; $why += TT "disk $($d.Number) ($($d.FriendlyName), $(Format-PDSize $d.Size)) is not initialized - a new disk" "disk $($d.Number) ($($d.FriendlyName), $(Format-PDSize $d.Size)) initialize केलेला नाही - नवीन disk" "disk $($d.Number) ($($d.FriendlyName), $(Format-PDSize $d.Size)) initialize नहीं हुआ - नई disk"; continue }
                foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object { -not $_.DriveLetter -and $_.Type -eq 'Basic' -and -not $_.IsHidden -and $_.Size -gt 1GB })) {
                    $v = $p | Get-Volume -ErrorAction SilentlyContinue
                    if ($v -and $v.FileSystem -in 'NTFS', 'exFAT', 'FAT32', 'ReFS') { $data.NoLetter += $p; $why += TT "a $(Format-PDSize $p.Size) partition on disk $($d.Number) has no drive letter" "disk $($d.Number) वरच्या $(Format-PDSize $p.Size) partition ला drive letter नाही" "disk $($d.Number) के $(Format-PDSize $p.Size) partition को drive letter नहीं" }
                }
            }
        } catch { return (New-TSCheck $null (TT 'The disks could not be read.' 'Disks वाचता आल्या नाहीत.' 'Disks पढ़ी नहीं जा सकीं।')) }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT 'Every disk Windows sees is online and has a drive letter. A disk not listed at all is a BIOS / cable / hardware matter (SATA / NVMe mode, power cable). 1 TB shows as 931 GB - that is normal.' 'Windows ला दिसणारी प्रत्येक disk online आहे आणि तिला drive letter आहे. यादीतच नसलेली disk BIOS / cable / hardware चा प्रश्न आहे (SATA / NVMe mode, power cable). 1 TB = 931 GB दिसणे नेहमीचे आहे.' 'Windows को दिखने वाली हर disk online है और उसे drive letter है। सूची में ही न दिखने वाली disk BIOS / cable / hardware का मामला है (SATA / NVMe mode, power cable)। 1 TB का 931 GB दिखना सामान्य है।'))
    }
    Fix = {
        param($chk)
        $did = @()
        foreach ($n in @($chk.Data.Off)) { try { Set-Disk -Number $n -IsOffline $false -ErrorAction Stop; $did += TT "brought disk $n online" "disk $n online केली" "disk $n online की" } catch { } }
        foreach ($p in @($chk.Data.NoLetter)) { try { Add-PartitionAccessPath -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -AssignDriveLetter -ErrorAction Stop; $did += TT "gave a drive letter to the partition on disk $($p.DiskNumber)" "disk $($p.DiskNumber) वरच्या partition ला drive letter दिले" "disk $($p.DiskNumber) के partition को drive letter दिया" } catch { } }
        $man = $null
        if (@($chk.Data.Raw).Count) { $man = TT "Disk $(@($chk.Data.Raw) -join ', ') is not initialized. ONLY if it is a brand-new / empty disk: Disk Management → Initialize (GPT) → New Simple Volume. If it had data, do not initialize - recover it first (TestDisk)." "Disk $(@($chk.Data.Raw) -join ', ') initialize केलेली नाही. फक्त ती नवीन / रिकामी disk असेल तरच: Disk Management → Initialize (GPT) → New Simple Volume. त्यावर data होता तर initialize करू नका - आधी data परत मिळवा (TestDisk)." "Disk $(@($chk.Data.Raw) -join ', ') initialize नहीं हुई। सिर्फ़ नई / खाली disk हो तभी: Disk Management → Initialize (GPT) → New Simple Volume। उस पर data था तो initialize न करें - पहले data वापस लाएँ (TestDisk)।" }
        if (-not $did.Count) { return (New-TSFix $false (TT 'Nothing could be changed automatically.' 'आपोआप काहीही बदलता आले नाही.' 'अपने आप कुछ नहीं बदला जा सका।') -Manual $man) }
        return (New-TSFix $true (Add-TT (TT 'I' 'मी' 'मैंने') (Join-TT $did ', ')) -Manual $man)
    }
}

# USB devices disconnect and reconnect (USB power saving)
$script:SubUsb = '2a737441-1930-4402-8d77-b2bebba308a3'; $script:UsbSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$script:D['usb-disconnect'] = @{
    Check = {
        Step 'Checking USB power saving' 'USB power saving तपासत आहे' 'USB power saving जाँच रहे हैं'
        $v = Get-TXPowerIndex $script:SubUsb $script:UsbSuspend
        if ($null -eq $v) { return (New-TSCheck $null (TT 'The USB power setting is not available on this PC. Try another port / cable, and a powered hub for external hard disks.' 'या PC वर USB power setting उपलब्ध नाही. दुसरा port / cable वापरा, आणि external hard disk साठी powered hub.' 'इस PC पर USB power setting उपलब्ध नहीं। दूसरा port / cable लगाएँ, और external hard disk के लिए powered hub.')) }
        if ($v.AC -eq 1 -or $v.DC -eq 1) { return (New-TSCheck $true (TT 'USB selective suspend (power saving) is on - Windows switches idle USB devices off, which makes them disconnect / lag.' 'USB selective suspend (power saving) चालू आहे - Windows वापरात नसलेले USB devices बंद करते, त्यामुळे ते disconnect होतात / अडखळतात.' 'USB selective suspend (power saving) चालू है - Windows बेकार USB devices बंद करता है, इससे वे disconnect होते / अटकते हैं।')) }
        return (New-TSCheck $false (TT 'USB power saving is already off. Frequent disconnects then mean a loose port / cable or not enough power (use a powered hub / Y-cable for external disks).' 'USB power saving आधीच बंद आहे. तरी disconnect होत असेल तर port / cable सैल आहे किंवा power कमी पडतो (external disk साठी powered hub / Y-cable).' 'USB power saving पहले से बंद है। फिर भी disconnect हो तो port / cable ढीला है या power कम पड़ती है (external disk के लिए powered hub / Y-cable)।'))
    }
    Fix = {
        Set-TXPowerIndex $script:SubUsb $script:UsbSuspend 0
        return (New-TSFix $true (TT 'I turned off USB power saving (selective suspend) in the power plan.' 'Power plan मध्ये USB power saving (selective suspend) बंद केले.' 'Power plan में USB power saving (selective suspend) बंद किया।') -Manual (TT 'If it still disconnects: Device Manager → USB Root Hub → Power Management → untick "Allow the computer to turn off this device", and try another port / cable.' 'तरीही disconnect होत असेल तर: Device Manager → USB Root Hub → Power Management → "Allow the computer to turn off this device" काढा, आणि दुसरा port / cable वापरा.' 'फिर भी disconnect हो तो: Device Manager → USB Root Hub → Power Management → "Allow the computer to turn off this device" हटाएँ, और दूसरा port / cable लगाएँ।'))
    }
}


# ================================================================== INDIA

# Aadhaar fingerprint / iris device - RD Service (UIDAI: 127.0.0.1, ports 11100-11120)
$script:RdDevice = '(?i)mantra|mfs ?1\d\d|morpho|mso ?1300|idemia|startek|fm ?220|precision|evolute|tatvik|cogent|secugen|marc ?11|mis ?100'
$script:RdService = '(?i)rd ?service|avdm|mantra|morpho|idemia|startek|acpl|precision.*rd|evolute|tatvik'
function Get-TXRdStatus {
    # the same harmless "RDSERVICE" discovery request the Aadhaar portals send (no capture, no finger needed)
    foreach ($p in 11100..11120) {
        try {
            $r = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$p/")
            $r.Method = 'RDSERVICE'; $r.Timeout = 1500; $r.ReadWriteTimeout = 1500; $r.Proxy = $null
            $resp = $r.GetResponse(); $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $txt = $sr.ReadToEnd(); $resp.Close()
            if ($txt -match 'status="(\w+)"') { return [pscustomobject]@{ Port = $p; Status = $Matches[1].ToUpper(); Info = $(if ($txt -match 'info="([^"]*)"') { $Matches[1] } else { '' }) } }
        } catch { }
    }
    return $null
}
$script:D['aadhaar-biometric-rd'] = @{
    Check = {
        Step 'Checking the Aadhaar fingerprint / iris device and its RD Service' 'Aadhaar fingerprint / iris device आणि त्याची RD Service तपासत आहे' 'Aadhaar fingerprint / iris device और उसकी RD Service जाँच रहे हैं'
        $dev = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match $script:RdDevice })
        $svc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $script:RdService -or $_.Name -match $script:RdService })
        if (-not $dev.Count -and -not $svc.Count) { return (New-TSCheck $null (TT 'No Aadhaar fingerprint / iris device or RD Service is installed. Install the device driver, then its RD Service, from the maker''s official site only.' 'Aadhaar fingerprint / iris device किंवा RD Service install नाही. आधी device driver, मग RD Service - फक्त कंपनीच्या official site वरून install करा.' 'Aadhaar fingerprint / iris device या RD Service install नहीं है। पहले device driver, फिर RD Service - सिर्फ़ कंपनी की official site से install करें।')) }
        $why = @(); $data = @{ Svc = @(); Bad = @() }
        $l0 = @($dev | Where-Object { $_.FriendlyName -match '(?i)mfs ?100\b|fm ?220u?\b|mso ?1300 ?e2?\b' -and $_.FriendlyName -notmatch '(?i)l1|e3' })
        if ($l0.Count) { $why += TT "$($l0[0].FriendlyName) looks like an old L0 device - UIDAI stopped L0 devices in 2025; only an L1 device (e.g. MFS110, MSO 1300 E3 L1) works" "$($l0[0].FriendlyName) जुने L0 device दिसते - UIDAI ने 2025 मध्ये L0 devices बंद केले; फक्त L1 device (उदा. MFS110, MSO 1300 E3 L1) चालते" "$($l0[0].FriendlyName) पुराना L0 device लगता है - UIDAI ने 2025 में L0 devices बंद किए; सिर्फ़ L1 device (जैसे MFS110, MSO 1300 E3 L1) चलता है"; $data.L0 = $true }
        $bad = @($dev | Where-Object { $_.Status -ne 'OK' })
        if ($bad.Count) { $why += TT "the device driver has a problem ($($bad[0].FriendlyName))" "device driver मध्ये दोष आहे ($($bad[0].FriendlyName))" "device driver में खराबी है ($($bad[0].FriendlyName))"; $data.Bad = $bad }
        if (-not $dev.Count) { $why += TT 'the device is not detected - check the USB cable / try a USB 2.0 port' 'device सापडत नाही - USB cable तपासा / USB 2.0 port वापरून पाहा' 'device नहीं मिल रहा - USB cable जाँचें / USB 2.0 port आज़माएँ' }
        $stopped = @($svc | Where-Object { $_.Status -ne 'Running' })
        if ($stopped.Count) { $why += TT "the RD Service is stopped ($($stopped[0].DisplayName))" "RD Service बंद आहे ($($stopped[0].DisplayName))" "RD Service बंद है ($($stopped[0].DisplayName))"; $data.Svc = $stopped }
        if (-not $svc.Count) { $why += TT 'the RD Service is not installed' 'RD Service install नाही' 'RD Service install नहीं है' }
        $rd = $null
        if ($svc.Count -and -not $stopped.Count) {
            $rd = Get-TXRdStatus
            if (-not $rd) { $why += TT 'the RD Service does not answer on 127.0.0.1 ports 11100-11120' 'RD Service 127.0.0.1 च्या 11100-11120 ports वर उत्तर देत नाही' 'RD Service 127.0.0.1 के 11100-11120 ports पर जवाब नहीं देती' }
            elseif ($rd.Status -ne 'READY') { $why += TT "the RD Service reports $($rd.Status) on port $($rd.Port) $($rd.Info)" "RD Service port $($rd.Port) वर $($rd.Status) सांगते $($rd.Info)" "RD Service port $($rd.Port) पर $($rd.Status) बताती है $($rd.Info)" }
        }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT "The device and RD Service are READY (port $($rd.Port)). If the portal still fails: correct date / time, and the portal must be opened in the browser the RD Service variant supports (HTTP / HTTPS)." "Device आणि RD Service READY आहेत (port $($rd.Port)). तरीही portal चालत नसेल तर: date / time बरोबर करा, आणि RD Service च्या प्रकाराला (HTTP / HTTPS) चालणाऱ्या browser मध्ये portal उघडा." "Device और RD Service READY हैं (port $($rd.Port))। फिर भी portal न चले तो: date / time सही करें, और RD Service के प्रकार (HTTP / HTTPS) के अनुसार browser में portal खोलें।"))
    }
    Fix = {
        param($chk)
        $did = @()
        foreach ($s in @($chk.Data.Svc)) { try { Set-Service $s.Name -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service $s.Name -ErrorAction Stop; $did += $s.DisplayName } catch { } }
        if (@($chk.Data.Bad).Count) { $r = @(Repair-TSDevices @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.Name -match $script:RdDevice })); if ($r.Count) { $did += $r } }
        $t = Invoke-PDQuickFix -Id 'time'; if ($t.Ok) { $did += 'date / time' }
        $man = TT 'Driver first, then RD Service, both "Run as administrator", only from the official site (Mantra: mantratec.com → Download; IDEMIA / Morpho and Startek: their official distributor). Test on the maker''s RD test page (status must be READY). An L0 device needs replacing with an L1 device; an expired RD registration is renewed by the vendor. Never edit the RD config files.' 'आधी driver, मग RD Service, दोन्ही "Run as administrator", फक्त official site वरून (Mantra: mantratec.com → Download; IDEMIA / Morpho आणि Startek: त्यांचे official distributor). कंपनीच्या RD test page वर तपासा (status READY हवा). L0 device बदलून L1 घ्यावे लागते; संपलेली RD registration vendor renew करतो. RD config files कधीही बदलू नका.' 'पहले driver, फिर RD Service, दोनों "Run as administrator", सिर्फ़ official site से (Mantra: mantratec.com → Download; IDEMIA / Morpho और Startek: उनके official distributor)। कंपनी के RD test page पर जाँचें (status READY होना चाहिए)। L0 device बदलकर L1 लेना होगा; खत्म RD registration vendor renew करता है। RD config files कभी न बदलें।'
        if ($chk.Data.L0) { return (New-TSFix $false (TT 'An old L0 device cannot be fixed by software.' 'जुने L0 device software ने दुरुस्त होत नाही.' 'पुराना L0 device software से ठीक नहीं होता।') -Manual $man) }
        $after = & $script:D['aadhaar-biometric-rd'].Check
        $txt = if ($did.Count) { TT "I started / repaired: $($did -join ', ')." "सुरू / दुरुस्त केले: $($did -join ', ')." "शुरू / ठीक किया: $($did -join ', ')।" } else { TT 'Nothing could be repaired automatically.' 'आपोआप काहीही दुरुस्त झाले नाही.' 'अपने आप कुछ ठीक नहीं हुआ।' }
        if ($after.Found -eq $false) { return (New-TSFix $true (Add-TT $txt (TT 'The device is READY now.' 'Device आता READY आहे.' 'Device अब READY है।'))) }
        return (New-TSFix $false $txt -Manual $man)
    }
    NoVerify = $true
}

# DSC (digital signature) USB token not detected on GST / Income Tax / MCA / e-tender
$script:DscDevice = '(?i)epass|feitian|proxkey|watchdata|safenet|etoken|hyperpki|mtoken|trust ?key|smart ?card'
$script:D['dsc-token'] = @{
    Check = {
        Step 'Checking the DSC token, its driver and the signing utility' 'DSC token, त्याचा driver आणि signing utility तपासत आहे' 'DSC token, उसका driver और signing utility जाँच रहे हैं'
        $tok = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -eq 'SmartCardReader' -or $_.FriendlyName -match $script:DscDevice -or $_.InstanceId -like '*VID_096E*' })
        $sw = @(Get-TXInstalled '(?i)emsigner|embridge|epass|proxkey|safenet|watchdata|hyperpki')
        if (-not $tok.Count -and -not $sw.Count) { return (New-TSCheck $null (TT 'No DSC token is plugged in and no token driver / signer (emSigner, emBridge) is installed.' 'DSC token लावलेला नाही आणि token driver / signer (emSigner, emBridge) install नाही.' 'DSC token नहीं लगा और token driver / signer (emSigner, emBridge) install नहीं है।')) }
        $why = @(); $data = @{}
        if (-not $tok.Count) { $why += TT 'the token is not detected - plug it in (try a USB 2.0 port) and install its driver from the maker' 'token सापडत नाही - लावा (USB 2.0 port वापरून पाहा) आणि कंपनीकडून त्याचा driver install करा' 'token नहीं मिल रहा - लगाएँ (USB 2.0 port आज़माएँ) और कंपनी से उसका driver install करें' }
        $bad = @($tok | Where-Object { $_.Status -ne 'OK' })
        if ($bad.Count) { $why += TT "the token driver has a problem ($($bad[0].FriendlyName)) - Windows 11 needs the latest token driver" "token driver मध्ये दोष आहे ($($bad[0].FriendlyName)) - Windows 11 ला नवीन token driver लागतो" "token driver में खराबी है ($($bad[0].FriendlyName)) - Windows 11 को नया token driver चाहिए"; $data.Bad = $true }
        $sc = Get-Service SCardSvr -ErrorAction SilentlyContinue
        if ($tok.Count -and $sc -and $sc.Status -ne 'Running') { $why += TT 'the Smart Card service is stopped' 'Smart Card service बंद आहे' 'Smart Card service बंद है'; $data.Svc = $true }
        $em = @($sw | Where-Object { $_.DisplayName -match '(?i)emsigner|embridge' })
        if ($em.Count -and -not (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)emsigner|embridge' })) { $why += TT "$($em[0].DisplayName) is installed but not running (the portal cannot reach the token)" "$($em[0].DisplayName) install आहे पण चालू नाही (portal ला token पोहोचत नाही)" "$($em[0].DisplayName) install है पर चालू नहीं (portal token तक नहीं पहुँचता)"; $data.Em = $em[0] }
        $exp = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -and $_.NotAfter -lt (Get-Date) -and $_.Issuer -match '(?i)emudhra|capricorn|vsign|ncode|sify|idsign|pantasign|xtra|safescrypt|verasys|gnfc|cdac' })
        if ($exp.Count) { $why += TT "an expired DSC certificate is present ($($exp[0].GetNameInfo('SimpleName', $false)), expired $($exp[0].NotAfter.ToString('dd-MM-yyyy'))) - renew it with the CA" "संपलेले DSC certificate आहे ($($exp[0].GetNameInfo('SimpleName', $false)), $($exp[0].NotAfter.ToString('dd-MM-yyyy')) ला संपले) - CA कडून renew करा" "खत्म DSC certificate है ($($exp[0].GetNameInfo('SimpleName', $false)), $($exp[0].NotAfter.ToString('dd-MM-yyyy')) को खत्म) - CA से renew करें" }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT 'The token is detected, its driver works and the Smart Card service runs. If the portal still fails: open https://127.0.0.1:1585 once and accept the certificate (emSigner), and register the DSC on the portal.' 'Token सापडतो, त्याचा driver चालतो आणि Smart Card service चालू आहे. तरीही portal चालत नसेल तर: https://127.0.0.1:1585 एकदा उघडून certificate accept करा (emSigner), आणि portal वर DSC register करा.' 'Token मिलता है, उसका driver चलता है और Smart Card service चालू है। फिर भी portal न चले तो: https://127.0.0.1:1585 एक बार खोलकर certificate accept करें (emSigner), और portal पर DSC register करें।'))
    }
    Fix = {
        param($chk)
        $did = @()
        if ($chk.Data.Svc) { try { Set-Service SCardSvr -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service SCardSvr -ErrorAction Stop; Start-Service CertPropSvc -ErrorAction SilentlyContinue; $did += 'Smart Card service' } catch { } }
        if ($chk.Data.Bad) { $r = @(Repair-TSDevices @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and ($_.PNPClass -eq 'SmartCardReader' -or $_.Name -match $script:DscDevice) })); if ($r.Count) { $did += $r } }
        if ($chk.Data.Em -and $chk.Data.Em.InstallLocation) {
            $exe = Get-ChildItem -LiteralPath $chk.Data.Em.InstallLocation -Filter *.exe -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)emsigner|embridge' } | Select-Object -First 1
            if ($exe) { try { Start-Process -FilePath $exe.FullName -ErrorAction Stop; $did += $exe.BaseName } catch { } }
        }
        $txt = if ($did.Count) { TT "I started / repaired: $($did -join ', ')." "सुरू / दुरुस्त केले: $($did -join ', ')." "शुरू / ठीक किया: $($did -join ', ')।" } else { TT 'Nothing could be started automatically.' 'आपोआप काहीही सुरू करता आले नाही.' 'अपने आप कुछ शुरू नहीं हो सका।' }
        return (New-TSFix $null $txt -Manual (TT 'Token driver from the maker (ePass2003: ftsafe.com, ProxKey: proxkey.com, SafeNet: Thales). GST: emSigner from the GST portal (Register / Update DSC page); Income Tax: emBridge from the e-filing portal → Downloads. Open https://127.0.0.1:1585 once and accept. Do not try the PIN many times - the token locks permanently. Expired / PAN-mismatch certificates are fixed by the CA, not on the PC.' 'Token driver कंपनीकडून (ePass2003: ftsafe.com, ProxKey: proxkey.com, SafeNet: Thales). GST: GST portal वरून emSigner (Register / Update DSC page); Income Tax: e-filing portal → Downloads मधून emBridge. https://127.0.0.1:1585 एकदा उघडून accept करा. PIN पुन्हा पुन्हा चुकवू नका - token कायमचा lock होतो. संपलेले / PAN न जुळणारे certificate CA दुरुस्त करतो, PC वर नाही.' 'Token driver कंपनी से (ePass2003: ftsafe.com, ProxKey: proxkey.com, SafeNet: Thales)। GST: GST portal से emSigner (Register / Update DSC page); Income Tax: e-filing portal → Downloads से emBridge. https://127.0.0.1:1585 एक बार खोलकर accept करें। PIN बार-बार गलत न डालें - token हमेशा के लिए lock हो जाता है। खत्म / PAN न मिलने वाला certificate CA ठीक करता है, PC पर नहीं।'))
    }
    NoVerify = $true
}

# pendrive "shortcut virus" - files hidden, shortcuts that start a script
function Get-TXShortcutVirus([string]$Root) {
    $res = [pscustomobject]@{ Root = $Root; Lnk = @(); Hidden = @(); Scripts = @() }
    $items = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'System Volume Information', '$RECYCLE.BIN', 'RECYCLER' })
    $sh = $null; try { $sh = New-Object -ComObject WScript.Shell } catch { }
    foreach ($i in $items) {
        if ($i.Extension -eq '.lnk' -and $sh) {
            try { $l = $sh.CreateShortcut($i.FullName); if ("$($l.TargetPath) $($l.Arguments)" -match '(?i)wscript|cscript|cmd(\.exe)?\b|rundll32|powershell|mshta|\.vbs|\.vbe|\.js\b|\.jse|\.wsf') { $res.Lnk += $i } } catch { }
        } elseif ($i.Name -match '(?i)\.(vbs|vbe|js|jse|wsf)$' -or $i.Name -eq 'autorun.inf') { $res.Scripts += $i }
        elseif (($i.Attributes -band [IO.FileAttributes]::Hidden) -and ($i.Attributes -band [IO.FileAttributes]::System)) { $res.Hidden += $i }
    }
    return $res
}
$script:D['pendrive-shortcut-virus'] = @{
    Check = {
        Step 'Checking pendrives / memory cards for the shortcut virus' 'Pendrive / memory card वर shortcut virus तपासत आहे' 'Pendrive / memory card पर shortcut virus जाँच रहे हैं'
        $roots = @(Get-TXRemovableRoots)
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction SilentlyContinue | Where-Object {
                $cl = [string]$_.CommandLine
                $cl -match '(?i)\.(vbs|vbe|js|jse|wsf)' -and ($cl -match '(?i)\\temp\\|\\appdata\\' -or @($roots | Where-Object { $cl -like "*$_*" }).Count) })
        if (-not $roots.Count -and -not $procs.Count) { return (New-TSCheck $null (TT 'No pendrive / memory card is plugged in - plug in the infected one and check again (do NOT open its shortcuts).' 'Pendrive / memory card लावलेले नाही - virus असलेले लावून पुन्हा तपासा (त्यातले shortcuts उघडू नका).' 'Pendrive / memory card नहीं लगा - virus वाला लगाकर फिर जाँचें (उसके shortcuts न खोलें)।')) }
        $found = @(); $why = @()
        foreach ($r in $roots) {
            $x = Get-TXShortcutVirus "$r\"
            if ($x.Lnk.Count -or $x.Scripts.Count -or ($x.Hidden.Count -and $x.Lnk.Count)) { $found += $x; $why += TT "$r has $($x.Lnk.Count) virus shortcuts, $($x.Scripts.Count) script files and $($x.Hidden.Count) hidden folders / files" "$r वर $($x.Lnk.Count) virus shortcuts, $($x.Scripts.Count) script files आणि $($x.Hidden.Count) लपवलेले folders / files" "$r पर $($x.Lnk.Count) virus shortcuts, $($x.Scripts.Count) script files और $($x.Hidden.Count) छिपे folders / files" }
            elseif ($x.Hidden.Count) { $found += $x; $why += TT "$r has $($x.Hidden.Count) hidden folders / files (the shortcut virus hides them)" "$r वर $($x.Hidden.Count) लपवलेले folders / files (shortcut virus त्यांना लपवतो)" "$r पर $($x.Hidden.Count) छिपे folders / files (shortcut virus उन्हें छिपाता है)" }
        }
        if ($procs.Count) { $why += TT "the virus is running on this PC too ($($procs.Count) script processes) - it will infect every pendrive" "virus या PC वरही चालू आहे ($($procs.Count) script processes) - तो प्रत्येक pendrive ला लागेल" "virus इस PC पर भी चल रहा है ($($procs.Count) script processes) - वह हर pendrive में लगेगा" }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') @{ Found = $found; Host = $procs }) }
        return (New-TSCheck $false (TT "No shortcut virus on $($roots -join ', ')." "$($roots -join ', ') वर shortcut virus नाही." "$($roots -join ', ') पर shortcut virus नहीं।"))
    }
    Fix = {
        param($chk)
        $did = @()
        foreach ($p in @($chk.Data.Host)) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $did += TT 'stopped the virus script on this PC' 'या PC वरची virus script थांबवली' 'इस PC की virus script रोकी' } catch { } }
        foreach ($x in @($chk.Data.Found)) {
            $q = Join-Path $x.Root '_Sanjeevani_virus_quarantine'
            $bad = @($x.Lnk) + @($x.Scripts)
            if ($bad.Count) {
                $null = New-Item -ItemType Directory -Path $q -Force -ErrorAction SilentlyContinue
                foreach ($f in $bad) { try { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $q ($f.Name + '.virus')) -Force -ErrorAction Stop } catch { } }
                $did += TT "moved $($bad.Count) virus shortcuts / scripts on $($x.Root) to _Sanjeevani_virus_quarantine (renamed .virus, harmless)" "$($x.Root) वरचे $($bad.Count) virus shortcuts / scripts _Sanjeevani_virus_quarantine मध्ये हलवले (.virus नाव, निरुपद्रवी)" "$($x.Root) के $($bad.Count) virus shortcuts / scripts _Sanjeevani_virus_quarantine में हटाए (.virus नाम, हानिरहित)"
            }
            $null = & attrib.exe -h -s -r "$($x.Root)*" /s /d 2>&1
            $did += TT "showed the hidden files on $($x.Root) again" "$($x.Root) वरच्या लपवलेल्या files पुन्हा दाखवल्या" "$($x.Root) की छिपी files फिर दिखाईं"
        }
        try { Set-PDRegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun -Value 255; $did += TT 'switched AutoRun off' 'AutoRun बंद केले' 'AutoRun बंद किया' } catch { }
        return (New-TSFix $true (Add-TT (TT 'I' 'मी' 'मैंने') (Join-TT $did ', ')) -Manual (TT 'Your files are back. Now run the virus check on THIS PC (it re-infects every pendrive), copy the data to the PC, format the pendrive and copy the data back. Delete the quarantine folder after that.' 'तुमच्या files परत आल्या. आता या PC वर virus तपासणी करा (तो प्रत्येक pendrive ला पुन्हा लावतो), data PC वर copy करा, pendrive format करा आणि data परत copy करा. नंतर quarantine folder delete करा.' 'आपकी files वापस आ गईं। अब इस PC पर virus जाँच करें (वह हर pendrive में फिर लगाता है), data PC पर copy करें, pendrive format करें और data वापस copy करें। बाद में quarantine folder delete करें।'))
    }
}

# unlicensed Windows / KMS activator (malware risk) - legal licences only
$script:D['pirated-kms'] = @{
    Check = {
        Step 'Checking the Windows licence and activator traces' 'Windows licence आणि activator चे अवशेष तपासत आहे' 'Windows licence और activator के निशान जाँच रहे हैं'
        $why = @(); $data = @{}
        $lp = $null
        try { $lp = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | Select-Object -First 1 } catch { }
        $domain = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain
        if ($lp) {
            if ($lp.LicenseStatus -ne 1) { $why += TT 'Windows is not activated' 'Windows activate नाही' 'Windows activate नहीं है'; $data.Unlicensed = $true }
            $kms = "$($lp.KeyManagementServiceMachine) $($lp.DiscoveredKeyManagementServiceMachineName)".Trim()
            if ($lp.Description -match 'VOLUME_KMSCLIENT' -and -not $domain) { $why += TT "Windows uses KMS activation$(if ($kms) { " ($kms)" }) on a home / shop PC - this is how pirate activators work" "घरच्या / दुकानाच्या PC वर Windows KMS activation$(if ($kms) { " ($kms)" }) वापरते - pirate activators असेच चालतात" "घर / दुकान के PC पर Windows KMS activation$(if ($kms) { " ($kms)" }) इस्तेमाल करता है - pirate activators ऐसे ही चलते हैं"; $data.Kms = $true }
        }
        $art = @()
        $art += @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match '(?i)kms|autopico|activat(or|ion).*(auto|renew)' } | ForEach-Object TaskName)
        $art += @('C:\Windows\System32\SppExtComObjHook.dll', "$env:ProgramFiles\KMSpico", "$env:ProgramData\KMSAutoS", "${env:ProgramFiles(x86)}\KMSpico" | Where-Object { Test-Path -LiteralPath $_ })
        $art += @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^(kms|service_kms|kmseldi)' } | ForEach-Object Name)
        if ($art.Count) { $why += TT "activator (crack) traces found: $(Format-TXList $art 3) - such tools often carry password-stealing malware" "activator (crack) चे अवशेष सापडले: $(Format-TXList $art 3) - अशा tools मध्ये बहुतेक password चोरणारे virus असतात" "activator (crack) के निशान मिले: $(Format-TXList $art 3) - ऐसे tools में अक्सर password चुराने वाले virus होते हैं"; $data.Art = $art }
        $data.Oem = $false; try { $data.Oem = [bool]((Get-CimInstance SoftwareLicensingService -ErrorAction Stop).OA3xOriginalProductKey) } catch { }
        if ($why.Count) { return (New-TSCheck $true (Join-TT $why '; ') $data) }
        return (New-TSCheck $false (TT 'Windows is genuinely activated and no activator traces were found.' 'Windows खरे activate आहे आणि activator चे अवशेष सापडले नाहीत.' 'Windows असली तरह activate है और activator के निशान नहीं मिले।'))
    }
    Fix = {
        param($chk)
        Start-PDQuickVirusScan
        $oem = if ($chk.Data.Oem) { TT 'Good news: this PC has a genuine Windows key stored in its BIOS - Settings → Activation → Troubleshoot / reinstall the same edition and it activates by itself.' 'चांगली बातमी: या PC च्या BIOS मध्ये खरी Windows key आहे - Settings → Activation → Troubleshoot / त्याच edition ची पुन्हा install केल्यावर आपोआप activate होते.' 'अच्छी खबर: इस PC के BIOS में असली Windows key है - Settings → Activation → Troubleshoot / उसी edition को फिर install करने पर अपने आप activate होता है।' } else { TT 'Buy a genuine licence (Windows Home / Pro, Microsoft 365) or use free LibreOffice instead of a cracked Office.' 'खरे licence घ्या (Windows Home / Pro, Microsoft 365) किंवा cracked Office ऐवजी मोफत LibreOffice वापरा.' 'असली licence लें (Windows Home / Pro, Microsoft 365) या cracked Office की जगह मुफ़्त LibreOffice इस्तेमाल करें।' }
        return (New-TSFix $null (TT 'I ran a quick virus scan. Activation was not touched - only a genuine licence is a real fix.' 'Quick virus scan केला. Activation ला हात लावला नाही - खरे licence हाच खरा उपाय.' 'Quick virus scan किया। Activation को हाथ नहीं लगाया - असली licence ही असली उपाय है।') -Manual (Add-TT $oem (TT 'Remove the activator (its task / folder), run a full virus scan and change important passwords (email, bank) if a crack was used.' 'Activator (त्याचा task / folder) काढा, पूर्ण virus scan करा आणि crack वापरला असल्यास महत्त्वाचे passwords (email, bank) बदला.' 'Activator (उसका task / folder) हटाएँ, पूरा virus scan करें और crack इस्तेमाल हुआ हो तो ज़रूरी passwords (email, bank) बदलें।')))
    }
    NoVerify = $true
}
