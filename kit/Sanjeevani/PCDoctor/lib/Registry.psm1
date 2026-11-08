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
    $orgNote = if ($domain) { ' (हा PC office domain मध्ये आहे - IT ने मुद्दाम लावले असू शकते.)' } else { '' }

    # --- blocked tools (policies viruses set)
    $pol = @(
        @('Software\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableTaskMgr', 'Task Manager बंद केलेला आहे'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableRegistryTools', 'Registry Editor बंद केलेला आहे'),
        @('Software\Policies\Microsoft\Windows\System', 'DisableCMD', 'Command Prompt बंद केलेला आहे'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoRun', 'Start → Run बंद केलेले आहे'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoFolderOptions', 'Folder Options बंद (लपवलेल्या files दाखवता येत नाहीत)'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoControlPanel', 'Control Panel / Settings बंद केलेले आहे'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoDrives', 'Drives लपवलेले आहेत'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoViewOnDrive', 'Drives उघडता येत नाहीत')
    )
    foreach ($root in 'HKCU:', 'HKLM:') {
        foreach ($p in $pol) {
            $k = "$root\$($p[0])"; $v = Get-PDRegValue $k $p[1]
            if ($v -and (ConvertTo-PDInt $v) -ne 0) {
                [void]$out.Add((New-PDRegIssue 'malware' 'Critical' $p[2] ("$k\$($p[1]) = $v. बहुतेक virus हे बंद करतात म्हणजे user त्यांना काढू शकत नाही." + $orgNote) $k $p[1] 'removevalue' -Selected (-not $domain)))
            }
        }
    }
    # --- Microsoft Defender switched off by policy
    $thirdAv = $false
    try { $thirdAv = [bool](@(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' }).Count) } catch { }
    foreach ($d in @(@('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender', 'DisableAntiSpyware'), @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableRealtimeMonitoring'))) {
        $v = Get-PDRegValue $d[0] $d[1]
        if ($v -and (ConvertTo-PDInt $v) -ne 0) {
            $det = if ($thirdAv) { 'दुसरा antivirus install आहे - त्याने बंद केले असेल तर ठीक.' } else { 'दुसरा antivirus नाही - virus ने Defender बंद केल्याची शक्यता.' }
            [void]$out.Add((New-PDRegIssue 'malware' $(if ($thirdAv) { 'Warning' } else { 'Critical' }) 'Microsoft Defender policy ने बंद केलेला आहे' ("$($d[0])\$($d[1]) = $v. $det" + $orgNote) $d[0] $d[1] 'removevalue' -Selected (-not $thirdAv -and -not $domain)))
        }
    }
    # --- Winlogon hijack
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $shell = [string](Get-PDRegValue $wl 'Shell')
    if ($shell -and $shell.Trim() -ine 'explorer.exe') {
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' 'Windows सुरू होताना दुसरा program चालतो (Winlogon Shell)' "Shell = `"$shell`" - असायला हवे explorer.exe" $wl 'Shell' 'setvalue' 'explorer.exe' 'String'))
    }
    $ui = [string](Get-PDRegValue $wl 'Userinit')
    if ($ui -and ([Environment]::ExpandEnvironmentVariables($ui).Trim().TrimEnd(',') -ine "$env:WINDIR\system32\userinit.exe")) {
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' 'Login नंतर अनोळखी program चालतो (Winlogon Userinit)' "Userinit = `"$ui`"" $wl 'Userinit' 'setvalue' "$env:WINDIR\system32\userinit.exe," 'String'))
    }
    $hcuShell = Get-PDRegValue 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Shell'
    if ($hcuShell) { [void]$out.Add((New-PDRegIssue 'malware' 'Critical' 'या user साठी Windows shell बदललेला आहे' "HKCU Winlogon Shell = `"$hcuShell`"" 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Shell' 'removevalue')) }
    # --- IFEO debugger hijack: opening program X really starts program Y
    $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    foreach ($k in @(Get-ChildItem -LiteralPath $ifeo -ErrorAction SilentlyContinue)) {
        $dbg = $k.GetValue('Debugger', $null)
        if (-not $dbg) { continue }
        if ($dbg -match '(?i)procexp|vsjitdebugger|windbg|ntsd\.exe|cdb\.exe') { continue }   # Process Explorer replacing Task Manager, developer debuggers
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' ("{0} उघडल्यावर दुसरेच काहीतरी चालते" -f $k.PSChildName) "Debugger = `"$dbg`" (Image File Execution Options) - virus antivirus / tools अडवण्यासाठी हे वापरतात." $k.PSPath 'Debugger' 'removevalue'))
    }
    # --- file type hijacks
    $assoc = @(@('.exe', 'exefile'), @('.lnk', 'lnkfile'), @('.bat', 'batfile'), @('.cmd', 'cmdfile'), @('.com', 'comfile'))
    foreach ($a in $assoc) {
        $v = Get-PDRegValue "HKLM:\SOFTWARE\Classes\$($a[0])" ''
        if ($v -and $v -ine $a[1]) { [void]$out.Add((New-PDRegIssue 'malware' 'Critical' ("{0} files चा प्रकार बदललेला आहे" -f $a[0]) "HKLM\SOFTWARE\Classes\$($a[0]) = `"$v`" - असायला हवे $($a[1])" "HKLM:\SOFTWARE\Classes\$($a[0])" '' 'setvalue' $a[1] 'String')) }
        if (Test-Path -LiteralPath "HKCU:\Software\Classes\$($a[0])") {
            [void]$out.Add((New-PDRegIssue 'malware' 'Critical' ("{0} files साठी या user चा वेगळा प्रकार" -f $a[0]) "HKCU\Software\Classes\$($a[0]) - programs / shortcuts उघडताना virus चालू शकतो." "HKCU:\Software\Classes\$($a[0])" '' 'removekey'))
        }
    }
    $exeCmd = Get-PDRegValue 'HKLM:\SOFTWARE\Classes\exefile\shell\open\command' ''
    if ($exeCmd -and $exeCmd -notmatch '^"%1"\s*%\*$') {
        [void]$out.Add((New-PDRegIssue 'malware' 'Critical' 'Programs (.exe) उघडण्याची पद्धत बदललेली आहे' "exefile\shell\open\command = `"$exeCmd`" - असायला हवे `"%1`" %*" 'HKLM:\SOFTWARE\Classes\exefile\shell\open\command' '' 'setvalue' '"%1" %*' 'String'))
    }
    # --- "show hidden files" switch broken (viruses hide themselves this way)
    $hk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Folder\Hidden\SHOWALL'
    $cv = Get-PDRegValue $hk 'CheckedValue'
    if ($null -ne $cv -and (ConvertTo-PDInt $cv) -ne 1) {
        [void]$out.Add((New-PDRegIssue 'malware' 'Warning' '"Hidden files दाखवा" option काम करत नाही' "SHOWALL\CheckedValue = $cv - असायला हवे 1" $hk 'CheckedValue' 'setvalue' 1 'DWord'))
    }
    # --- proxy behind the user's back (adware) - not selected by default: offices use proxies
    $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ((ConvertTo-PDInt (Get-PDRegValue $is 'ProxyEnable')) -eq 1) {
        [void]$out.Add((New-PDRegIssue 'malware' 'Warning' 'Internet proxy चालू आहे' ("Proxy = $(Get-PDRegValue $is 'ProxyServer'). Office मध्ये proxy नसेल तर adware ने लावले असू शकते - internet हळू / ads." ) $is 'ProxyEnable' 'setvalue' 0 'DWord' -Selected $false))
    }
    $pac = Get-PDRegValue $is 'AutoConfigURL'
    if ($pac) { [void]$out.Add((New-PDRegIssue 'malware' 'Warning' 'Internet auto-config (PAC) script लावलेला आहे' "AutoConfigURL = $pac" $is 'AutoConfigURL' 'removevalue' -Selected $false)) }

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
                [void]$out.Add((New-PDRegIssue 'broken' 'Info' "Startup entry चा program नाही: $n" "$cmd - program काढलेला आहे, पण Windows प्रत्येक start ला तो शोधतो." $rk $n 'removevalue'))
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
            [void]$out.Add((New-PDRegIssue 'broken' 'Info' "Programs यादीतील तुटलेली entry: $name" "Uninstall program ($t) आणि folder दोन्ही नाहीत - यादीतून काढल्यास गोंधळ कमी." $k.PSPath '' 'removekey'))
        }
    }
    # --- App Paths to missing programs
    foreach ($ap in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths') {
        foreach ($k in @(Get-ChildItem -LiteralPath $ap -ErrorAction SilentlyContinue)) {
            $v = [string]$k.GetValue('', $null, 'DoNotExpandEnvironmentNames')
            if (-not $v) { continue }
            $t = [Environment]::ExpandEnvironmentVariables($v.Trim().Trim('"'))
            if ($t -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $t)) {
                [void]$out.Add((New-PDRegIssue 'broken' 'Info' "App Path चा program नाही: $($k.PSChildName)" "$t नाही." $k.PSPath '' 'removekey'))
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
            Write-PDLog "Registry दुरुस्त: $($i.Title)" 'OK'
            $done++
        } catch { $failed++; Write-PDLog ("Registry: {0} - {1}" -f $i.Title, $_.Exception.Message) 'WARN' }
    }
    return [pscustomobject]@{ Fixed = $done; Failed = $failed }
}

Export-ModuleMember -Function Get-PDRegistryIssues, Repair-PDRegistryIssues, Get-PDCommandTarget, Test-PDTargetExists
