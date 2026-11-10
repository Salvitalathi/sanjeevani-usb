# Sanjeevani PC Doctor - registry check.
#
# Not a "registry cleaner": deleting thousands of leftover entries does not make Windows faster and can break it
# (Microsoft advises against such cleaners). Only entries that cause real problems are checked:
#   malware  - settings viruses change: Task Manager / Registry Editor / Command Prompt / Run / Folder Options blocked,
#              Windows Defender switched off by policy, Winlogon Shell / Userinit hijack, "Image File Execution
#              Options" debugger hijacks (a program opens something else), .exe / .lnk / .bat file-type hijacks,
#              "show hidden files" switch broken, proxy set behind the user's back
#   broken   - startup entries whose program no longer exists (errors at every start), entries in "Programs and
#              Features" whose uninstaller and folder are gone, App Paths to missing programs
# Every fix: restore point first, the key is saved to Reports\...\backup (JSON, plus .reg when reg.exe is allowed)
# and journaled, so Undo restores it - even when the virus blocked reg.exe / regedit.
Set-StrictMode -Off

function ConvertTo-PDRegExePath([string]$Key) { return ($Key -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\' -replace '^HKCR:\\', 'HKCR\') }

# Program file a command line starts ("C:\x\a.exe" -arg, rundll32 "C:\y.dll",Entry, %ProgramFiles%\z.exe)
function Get-PDCommandTarget([string]$Command) {
    if (-not $Command) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    $first = $null
    if ($c -match '^"([^"]+)"') { $first = $Matches[1] }
    elseif ($c -match '^(.+?\.(exe|com|bat|cmd|vbs|vbe|js|wsf|msc|cpl|scr|pif))(\s|,|$)') { $first = $Matches[1] }
    else { $first = ($c -split '\s+')[0] }
    # rundll32 / regsvr32 / wscript / cmd /c: the real target is the file they run
    if ($first -match '(?i)(^|\\)(rundll32|regsvr32|wscript|cscript|mshta)(\.exe)?$') {
        $rest = $c.Substring([math]::Min($c.Length, $c.IndexOf($first) + $first.Length)).Trim().Trim('"')
        if ($rest -match '^(?:/\w+\s+)*"?([A-Za-z]:\\[^",]+?\.(dll|ocx|cpl|vbs|vbe|js|wsf|hta))') { return $Matches[1] }
        return $null
    }
    return $first
}

function Test-PDTargetExists([string]$Path) {
    if (-not $Path) { return $true }
    if ($Path -match '^[A-Za-z]:\\') { return (Test-Path -LiteralPath $Path) }
    if ($Path -match '\\') { return $true }          # relative path - cannot judge
    if (Get-Command $Path -ErrorAction SilentlyContinue) { return $true }
    foreach ($d in "$env:WINDIR\System32", "$env:WINDIR", "$env:WINDIR\SysWOW64") { if (Test-Path -LiteralPath (Join-Path $d $Path)) { return $true } }
    if ($Path -notmatch '\.\w{2,4}$' -and (Get-Command "$Path.exe" -ErrorAction SilentlyContinue)) { return $true }
    return $false
}

function ConvertTo-PDInt($v) { try { return [int64]$v } catch { return 0 } }

function New-PDRegIssue {
    param([string]$Kind, [string]$Severity, [string]$Title, [string]$Detail, [string]$Key, [string]$Name, [string]$Action, $Value = $null, [string]$Type = 'String', [bool]$Selected = $true)
    [pscustomobject]@{ Kind = $Kind; Severity = $Severity; Title = $Title; Detail = $Detail; Key = $Key; Name = $Name; Action = $Action; Value = $Value; Type = $Type; Selected = $Selected }
}

function Get-PDRegValue([string]$Key, [string]$Name) {
    try { $k = Get-Item -LiteralPath $Key -ErrorAction Stop; return $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames') } catch { return $null }
}

function Get-PDRegistryIssues {
    $out = New-Object System.Collections.ArrayList
    $domain = $false
    try { $domain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
    $orgNote = if ($domain) { L ' (This PC is in an office domain - IT may have set this on purpose.)' ' (हा PC office domain मध्ये आहे - IT ने मुद्दाम लावले असू शकते.)' ' (यह PC office domain में है - IT ने जानबूझकर लगाया हो सकता है।)' } else { '' }

    # --- blocked tools (policies viruses set)
    $pol = @(
        @('Software\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableTaskMgr', (L 'Task Manager is disabled' 'Task Manager बंद केलेला आहे' 'Task Manager बंद किया गया है')),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableRegistryTools', (L 'Registry Editor is disabled' 'Registry Editor बंद केलेला आहे' 'Registry Editor बंद किया गया है')),
        @('Software\Policies\Microsoft\Windows\System', 'DisableCMD', (L 'Command Prompt is disabled' 'Command Prompt बंद केलेला आहे' 'Command Prompt बंद किया गया है')),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoRun', (L 'Start → Run is disabled' 'Start → Run बंद केलेले आहे' 'Start → Run बंद किया गया है')),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoFolderOptions', (L 'Folder Options disabled (hidden files cannot be shown)' 'Folder Options बंद (लपवलेल्या files दाखवता येत नाहीत)' 'Folder Options बंद (छिपी files नहीं दिखा सकते)')),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoControlPanel', (L 'Control Panel / Settings are disabled' 'Control Panel / Settings बंद केलेले आहे' 'Control Panel / Settings बंद किए गए हैं')),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoDrives', (L 'Drives are hidden' 'Drives लपवलेले आहेत' 'Drives छिपाए गए हैं')),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoViewOnDrive', (L 'Drives cannot be opened' 'Drives उघडता येत नाहीत' 'Drives खुल नहीं सकते'))
    )
    foreach ($root in 'HKCU:', 'HKLM:') {
        foreach ($p in $pol) {
            $k = "$root\$($p[0])"; $v = Get-PDRegValue $k $p[1]
            if ($v -and (ConvertTo-PDInt $v) -ne 0) {
                [void]$out.Add((New-PDRegIssue 'malware' 'Critical' $p[2] ("$k\$($p[1]) = $v. " + (L 'Viruses usually disable this so that the user cannot remove them.' 'बहुतेक virus हे बंद करतात म्हणजे user त्यांना काढू शकत नाही.' 'ज़्यादातर virus इसे बंद करते हैं ताकि user उन्हें हटा न सके।') + $orgNote) $k $p[1] 'removevalue' -Selected (-not $domain)))
            }
        }
    }
    # --- Microsoft Defender switched off by policy
    $thirdAv = $false
    try { $thirdAv = [bool](@(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' }).Count) } catch { }
    foreach ($d in @(@('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender', 'DisableAntiSpyware'), @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableRealtimeMonitoring'))) {
        $v = Get-PDRegValue $d[0] $d[1]
        if ($v -and (ConvertTo-PDInt $v) -ne 0) {
            $det = if ($thirdAv) { L 'Another antivirus is installed - fine if it turned Defender off.' 'दुसरा antivirus install आहे - त्याने बंद केले असेल तर ठीक.' 'दूसरा antivirus install है - उसने बंद किया हो तो ठीक।' } else { L 'No other antivirus - a virus has probably turned Defender off.' 'दुसरा antivirus नाही - virus ने Defender बंद केल्याची शक्यता.' 'दूसरा antivirus नहीं - virus ने Defender बंद किया होगा।' }
            [void]$out.Add((New-PDRegIssue 'malware' $(if ($thirdAv) { 'Warning' } else { 'Critical' }) (L 'Microsoft Defender is disabled by policy' 'Microsoft Defender policy ने बंद केलेला आहे' 'Microsoft Defender policy से बंद किया गया है') ("$($d[0])\$($d[1]) = $v. $det" + $orgNote) $d[0] $d[1] 'removevalue' -Selected (-not $thirdAv -and -not $domain)))
        }
    }
    # --- Winlogon hijack
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $shell = [string](Get-PDRegValue $wl 'Shell')
    if ($shell -and $shell.Trim() -ine 'explorer.exe') {
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' (L 'Another program runs when Windows starts (Winlogon Shell)' 'Windows सुरू होताना दुसरा program चालतो (Winlogon Shell)' 'Windows शुरू होते समय दूसरा program चलता है (Winlogon Shell)') ("Shell = `"$shell`" - " + (L 'should be' 'असायला हवे' 'होना चाहिए') + ' explorer.exe') $wl 'Shell' 'setvalue' 'explorer.exe' 'String'))
    }
    $ui = [string](Get-PDRegValue $wl 'Userinit')
    if ($ui -and ([Environment]::ExpandEnvironmentVariables($ui).Trim().TrimEnd(',') -ine "$env:WINDIR\system32\userinit.exe")) {
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' (L 'An unknown program runs after login (Winlogon Userinit)' 'Login नंतर अनोळखी program चालतो (Winlogon Userinit)' 'Login के बाद अनजान program चलता है (Winlogon Userinit)') "Userinit = `"$ui`"" $wl 'Userinit' 'setvalue' "$env:WINDIR\system32\userinit.exe," 'String'))
    }
    $hcuShell = Get-PDRegValue 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Shell'
    if ($hcuShell) { [void]$out.Add((New-PDRegIssue 'malware' 'Critical' (L 'The Windows shell is changed for this user' 'या user साठी Windows shell बदललेला आहे' 'इस user के लिए Windows shell बदला गया है') "HKCU Winlogon Shell = `"$hcuShell`"" 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Shell' 'removevalue')) }
    # --- IFEO debugger hijack: opening program X really starts program Y
    $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    foreach ($k in @(Get-ChildItem -LiteralPath $ifeo -ErrorAction SilentlyContinue)) {
        $dbg = $k.GetValue('Debugger', $null)
        if (-not $dbg) { continue }
        if ($dbg -match '(?i)procexp|vsjitdebugger|windbg|ntsd\.exe|cdb\.exe') { continue }   # Process Explorer replacing Task Manager, developer debuggers
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' ((L 'Opening {0} runs something else' '{0} उघडल्यावर दुसरेच काहीतरी चालते' '{0} खोलने पर कुछ और ही चलता है') -f $k.PSChildName) ("Debugger = `"$dbg`" (Image File Execution Options) - " + (L 'viruses use this to block antivirus / tools.' 'virus antivirus / tools अडवण्यासाठी हे वापरतात.' 'virus antivirus / tools रोकने के लिए यह इस्तेमाल करते हैं।')) $k.PSPath 'Debugger' 'removevalue'))
    }
    # --- file type hijacks
    $assoc = @(@('.exe', 'exefile'), @('.lnk', 'lnkfile'), @('.bat', 'batfile'), @('.cmd', 'cmdfile'), @('.com', 'comfile'))
    foreach ($a in $assoc) {
        $v = Get-PDRegValue "HKLM:\SOFTWARE\Classes\$($a[0])" ''
        if ($v -and $v -ine $a[1]) { [void]$out.Add((New-PDRegIssue 'malware' 'Critical' ((L 'The file type of {0} files is changed' '{0} files चा प्रकार बदललेला आहे' '{0} files का प्रकार बदला गया है') -f $a[0]) ("HKLM\SOFTWARE\Classes\$($a[0]) = `"$v`" - " + (L 'should be' 'असायला हवे' 'होना चाहिए') + " $($a[1])") "HKLM:\SOFTWARE\Classes\$($a[0])" '' 'setvalue' $a[1] 'String')) }
        if (Test-Path -LiteralPath "HKCU:\Software\Classes\$($a[0])") {
            [void]$out.Add((New-PDRegIssue 'malware' 'Critical' ((L 'This user has a different file type for {0} files' '{0} files साठी या user चा वेगळा प्रकार' '{0} files के लिए इस user का अलग प्रकार') -f $a[0]) ("HKCU\Software\Classes\$($a[0]) - " + (L 'a virus can run when programs / shortcuts open.' 'programs / shortcuts उघडताना virus चालू शकतो.' 'programs / shortcuts खोलते समय virus चल सकता है।')) "HKCU:\Software\Classes\$($a[0])" '' 'removekey'))
        }
    }
    $exeCmd = Get-PDRegValue 'HKLM:\SOFTWARE\Classes\exefile\shell\open\command' ''
    if ($exeCmd -and $exeCmd -notmatch '^"%1"\s*%\*$') {
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' (L 'The way programs (.exe) open is changed' 'Programs (.exe) उघडण्याची पद्धत बदललेली आहे' 'Programs (.exe) खुलने का तरीका बदला गया है') ("exefile\shell\open\command = `"$exeCmd`" - " + (L 'should be' 'असायला हवे' 'होना चाहिए') + ' "%1" %*') 'HKLM:\SOFTWARE\Classes\exefile\shell\open\command' '' 'setvalue' '"%1" %*' 'String'))
    }
    # --- "show hidden files" switch broken (viruses hide themselves this way)
    $hk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Folder\Hidden\SHOWALL'
    $cv = Get-PDRegValue $hk 'CheckedValue'
    if ($null -ne $cv -and (ConvertTo-PDInt $cv) -ne 1) {
        [void]$out.Add((New-PDRegIssue 'malware' 'Warning' (L 'The "Show hidden files" option does not work' '"Hidden files दाखवा" option काम करत नाही' '"Hidden files दिखाएँ" option काम नहीं करता') ("SHOWALL\CheckedValue = $cv - " + (L 'should be' 'असायला हवे' 'होना चाहिए') + ' 1') $hk 'CheckedValue' 'setvalue' 1 'DWord'))
    }
    # --- proxy behind the user's back (adware) - not selected by default: offices use proxies
    $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ((ConvertTo-PDInt (Get-PDRegValue $is 'ProxyEnable')) -eq 1) {
        [void]$out.Add((New-PDRegIssue 'malware' 'Warning' (L 'An internet proxy is on' 'Internet proxy चालू आहे' 'Internet proxy चालू है') ("Proxy = $(Get-PDRegValue $is 'ProxyServer'). " + (L 'Without an office proxy, adware may have set it - slow internet / ads.' 'Office मध्ये proxy नसेल तर adware ने लावले असू शकते - internet हळू / ads.' 'Office में proxy न हो तो adware ने लगाया हो सकता है - internet धीमा / ads.')) $is 'ProxyEnable' 'setvalue' 0 'DWord' -Selected $false))
    }
    $pac = Get-PDRegValue $is 'AutoConfigURL'
    if ($pac) { [void]$out.Add((New-PDRegIssue 'malware' 'Warning' (L 'An internet auto-config (PAC) script is set' 'Internet auto-config (PAC) script लावलेला आहे' 'Internet auto-config (PAC) script लगा है') "AutoConfigURL = $pac" $is 'AutoConfigURL' 'removevalue' -Selected $false)) }

    # --- startup entries whose program is gone
    $runKeys = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce')
    foreach ($rk in $runKeys) {
        $k = Get-Item -LiteralPath $rk -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            $cmd = [string]$k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
            $t = Get-PDCommandTarget $cmd
            if ($t -and -not (Test-PDTargetExists $t)) {
                [void]$out.Add((New-PDRegIssue 'broken' 'Info' ((L 'Startup entry without its program: ' 'Startup entry चा program नाही: ' 'Startup entry का program नहीं: ') + $n) ("$cmd - " + (L 'the program is gone, but Windows looks for it at every start.' 'program काढलेला आहे, पण Windows प्रत्येक start ला तो शोधतो.' 'program हटा दिया गया है, पर Windows हर start पर उसे ढूँढता है।')) $rk $n 'removevalue'))
            }
        }
    }
    # --- "Programs and Features" entries whose uninstaller and folder are gone
    $unKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($uk in $unKeys) {
        foreach ($k in @(Get-ChildItem -LiteralPath $uk -ErrorAction SilentlyContinue)) {
            $name = $k.GetValue('DisplayName'); $us = [string]$k.GetValue('UninstallString')
            if (-not $name -or -not $us) { continue }
            if ($k.GetValue('SystemComponent') -eq 1 -or $k.GetValue('WindowsInstaller') -eq 1 -or $us -match '(?i)msiexec') { continue }
            $t = Get-PDCommandTarget $us
            if (-not $t -or (Test-PDTargetExists $t)) { continue }
            $loc = [string]$k.GetValue('InstallLocation')
            if ($loc -and (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($loc).Trim('"')))) { continue }   # program folder still there
            [void]$out.Add((New-PDRegIssue 'broken' 'Info' ((L 'Broken entry in the programs list: ' 'Programs यादीतील तुटलेली entry: ' 'Programs सूची की टूटी entry: ') + $name) ((L 'Neither the uninstaller ({0}) nor the folder exists - removing it from the list avoids confusion.' 'Uninstall program ({0}) आणि folder दोन्ही नाहीत - यादीतून काढल्यास गोंधळ कमी.' 'Uninstall program ({0}) और folder दोनों नहीं हैं - सूची से हटाने पर गड़बड़ कम।') -f $t) $k.PSPath '' 'removekey'))
        }
    }
    # --- App Paths to missing programs
    foreach ($ap in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths') {
        foreach ($k in @(Get-ChildItem -LiteralPath $ap -ErrorAction SilentlyContinue)) {
            $v = [string]$k.GetValue('', $null, 'DoNotExpandEnvironmentNames')
            if (-not $v) { continue }
            $t = [Environment]::ExpandEnvironmentVariables($v.Trim().Trim('"'))
            if ($t -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $t)) {
                [void]$out.Add((New-PDRegIssue 'broken' 'Info' ((L 'App Path without its program: ' 'App Path चा program नाही: ' 'App Path का program नहीं: ') + $k.PSChildName) ("$t " + (L 'is missing.' 'नाही.' 'नहीं है।')) $k.PSPath '' 'removekey'))
            }
        }
    }
    return @($out)
}

function Repair-PDRegistryIssues {
    param([Parameter(Mandatory)][object[]]$Issues, [switch]$NoRestorePoint)
    if (-not $NoRestorePoint) { [void](New-PDRestorePoint 'Sanjeevani: registry repair') }
    $done = 0; $failed = 0; $n = 0
    foreach ($i in $Issues) {
        $n++
        try {
            $key = ($i.Key -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:' -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_CURRENT_USER', 'HKCU:')
            $label = ($key -replace '[^\w]+', '_'); if ($label.Length -gt 60) { $label = $label.Substring($label.Length - 60) }
            # own backup (works even when a virus blocked reg.exe / regedit) + a .reg copy when reg.exe is allowed
            $bak = Save-PDRegTree -Key $key -Name ("reg-$n-$label")
            if (-not (Test-Path -LiteralPath $bak)) { throw "backup of $key failed - not changed" }
            Add-PDUndo @{ Type = 'RegTree'; File = $bak; Label = $i.Title }
            try { [void](Save-PDRegBackup -RegPath (ConvertTo-PDRegExePath $key) -Name ("reg-$n-$label")) } catch { }
            switch ($i.Action) {
                'removevalue' { Remove-ItemProperty -LiteralPath $key -Name $i.Name -ErrorAction Stop }
                'removekey'   { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop }
                'setvalue'    {
                    $nm = if ($i.Name) { $i.Name } else { '(default)' }
                    Set-ItemProperty -LiteralPath $key -Name $nm -Value $i.Value -Type $i.Type -ErrorAction Stop
                }
            }
            Write-PDLog "Registry fixed: $($i.Title)" 'OK'
            $done++
        } catch { $failed++; Write-PDLog ("Registry: {0} - {1}" -f $i.Title, $_.Exception.Message) 'WARN' }
    }
    return [pscustomobject]@{ Fixed = $done; Failed = $failed }
}

Export-ModuleMember -Function Get-PDRegistryIssues, Repair-PDRegistryIssues, Get-PDCommandTarget, Test-PDTargetExists
