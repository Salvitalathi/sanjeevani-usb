#Requires -Version 5.1
<#
    Sanjeevani test suite - runs in Windows PowerShell 5.1 (GitHub Actions windows-latest).
    Static checks + safe smoke tests of PC Doctor. Nothing here touches real user data:
    file-move tests use temp folders, registry tests use HKCU:\Software\SanjeevaniTest,
    and visual-effects changes are undone at the end.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
$Root = Split-Path $PSScriptRoot
$Kit = Join-Path $Root 'kit'
$script:Failed = 0
$script:Results = @()

function Test-Case([string]$Name, [scriptblock]$Body) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = & $Body
        if ($r -is [bool] -and -not $r) { throw 'check returned $false' }
        Write-Host ("PASS  {0}  ({1:N1}s)" -f $Name, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
        $script:Results += [pscustomobject]@{ Test = $Name; Result = 'PASS'; Detail = '' }
    } catch {
        $script:Failed++
        Write-Host ("FAIL  {0}: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        $script:Results += [pscustomobject]@{ Test = $Name; Result = 'FAIL'; Detail = $_.Exception.Message }
    }
}
function Assert($cond, [string]$msg) { if (-not $cond) { throw $msg } }

Write-Host "PowerShell $($PSVersionTable.PSVersion) on $([Environment]::OSVersion.VersionString)"

# ------------------------------------------------------------------ static
$psFiles = @(Get-ChildItem $Root -Recurse -Include *.ps1, *.psm1 -File | Where-Object { $_.FullName -notmatch '\\dist\\' })

Test-Case 'All PowerShell files parse (PS 5.1 parser)' {
    $bad = @()
    foreach ($f in $psFiles) {
        $tok = $null; $err = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err)
        foreach ($e in $err) { $bad += "$($f.Name):$($e.Extent.StartLineNumber) $($e.Message)" }
    }
    Assert ($bad.Count -eq 0) ($bad -join "`n")
}

Test-Case 'Files with non-ASCII text have a UTF-8 BOM' {
    $bad = @()
    foreach ($f in $psFiles) {
        $b = [IO.File]::ReadAllBytes($f.FullName)
        $hasBom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
        $nonAscii = [bool]($b | Where-Object { $_ -gt 127 } | Select-Object -First 1)
        if ($nonAscii -and -not $hasBom) { $bad += $f.Name }
    }
    Assert ($bad.Count -eq 0) ('missing BOM: ' + ($bad -join ', '))
}

Test-Case 'Batch files use CRLF line endings' {
    $bad = @()
    foreach ($f in Get-ChildItem $Root -Recurse -Filter *.cmd -File) {
        $t = [IO.File]::ReadAllText($f.FullName)
        if (($t -replace "`r`n", '') -match "`n") { $bad += $f.Name }
    }
    Assert ($bad.Count -eq 0) ('LF-only: ' + ($bad -join ', '))
}

Test-Case 'All JSON files are valid' {
    foreach ($f in Get-ChildItem $Kit -Recurse -Filter *.json -File) {
        try { $null = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "$($f.Name): $($_.Exception.Message)" }
    }
    $true
}

Test-Case 'Catalog regexes compile in .NET' {
    $cat = Get-Content (Join-Path $Kit 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in @($cat.isos) + @($cat.tools)) {
        foreach ($k in 'asset', 'file', 'regex', 'dirRegex') { if ($e.source.$k) { [void][regex]::new($e.source.$k) } }
        foreach ($k in 'exe', 'extract') { if ($e.$k) { [void][regex]::new($e.$k) } }
    }
    $apps = Get-Content (Join-Path $Kit 'Sanjeevani\PCDoctor\data\apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($r in $apps.rules) { [void][regex]::new($r.match) }
    $true
}

Test-Case 'Boot theme files present' {
    $t = Join-Path $Kit 'ventoy\theme\sanjeevani'
    foreach ($f in 'theme.txt', 'background.jpg', 'logo.png', 'select_c.png', 'menu_c.png', 'icons\rescue.png') { Assert (Test-Path (Join-Path $t $f)) "missing $f" }
    foreach ($fn in Get-Content (Join-Path $t 'fonts.list')) { if ($fn) { Assert (Test-Path (Join-Path $t $fn)) "missing font $fn" } }
    $txt = Get-Content (Join-Path $t 'theme.txt') -Raw
    Assert (($txt.ToCharArray() | Where-Object { $_ -eq '{' }).Count -eq ($txt.ToCharArray() | Where-Object { $_ -eq '}' }).Count) 'theme.txt braces unbalanced'
    $true
}

Test-Case 'PC Doctor window (XAML) loads' {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $src = Get-Content (Join-Path $Kit 'Sanjeevani\PCDoctor\PCDoctor.ps1') -Raw -Encoding UTF8
    $m = [regex]::Match($src, "(?s)\[xml\]\`$xaml = @'\r?\n(.*?)\r?\n'@")
    Assert $m.Success 'XAML block not found'
    [xml]$x = $m.Groups[1].Value
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    foreach ($n in 'FindingsList', 'StartupList', 'BloatList', 'FolderList', 'LogBox', 'Progress', 'TargetCombo', 'Win11List', 'AppList', 'ToolPanel') {
        Assert ($null -ne $win.FindName($n)) "element $n missing"
    }
    $win.Close()
    $true
}

# ------------------------------------------------------------------ modules
$fakeUsb = Join-Path $env:TEMP ('sjv-usb-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fakeUsb -Force | Out-Null
Copy-Item (Join-Path $Kit '*') $fakeUsb -Recurse -Force
$DataDir = Join-Path $fakeUsb 'Sanjeevani\PCDoctor\data'

Test-Case 'Modules import' {
    foreach ($m in 'Common', 'Diagnostics', 'Repair', 'Speed', 'Storage', 'Advisor', 'Report') {
        Import-Module (Join-Path $fakeUsb "Sanjeevani\PCDoctor\lib\$m.psm1") -Force -DisableNameChecking
    }
    $ctx = Initialize-PDContext -UsbRoot $fakeUsb
    Assert (Test-Path $ctx.ReportDir) 'report dir not created'
    $true
}

Test-Case 'Undo journal keeps every entry' {
    Remove-Item $global:PDCtx.UndoFile -ErrorAction SilentlyContinue
    Add-PDUndo @{ Type = 'Note'; Text = 'a' }
    Add-PDUndo @{ Type = 'Service'; Name = 'Fax'; StartType = 'Manual' }
    Add-PDUndo @{ Type = 'Note'; Text = 'c' }
    Add-PDUndo @{ Type = 'Note'; Text = 'd' }
    $u = @(Get-PDUndo)
    Assert ($u.Count -eq 4) "expected 4 entries, got $($u.Count)"
    Assert (@($u | Where-Object { $_.Type }).Count -eq 4) 'some entries lost their Type'
    Assert ($u[1].Name -eq 'Fax') 'entry order/content changed'
    Remove-Item $global:PDCtx.UndoFile
    $true
}

Test-Case 'Startup disable + Undo round trip (test registry key)' {
    $k = 'HKCU:\Software\SanjeevaniTest\StartupApproved'
    Remove-Item 'HKCU:\Software\SanjeevaniTest' -Recurse -Force -ErrorAction SilentlyContinue
    $item = [pscustomobject]@{ Name = 'DemoApp'; ApprovedKey = $k; ValueName = 'DemoApp'; Enabled = $true }
    Assert (Test-PDStartupEnabled $k 'DemoApp') 'should start enabled'
    Set-PDStartupState -Item $item -Enabled $false
    Assert (-not (Test-PDStartupEnabled $k 'DemoApp')) 'not disabled'
    Undo-PDChanges
    Assert (Test-PDStartupEnabled $k 'DemoApp') 'undo did not re-enable'
    Remove-Item 'HKCU:\Software\SanjeevaniTest' -Recurse -Force
    $true
}

Test-Case 'Visual effects tweak + Undo restores registry' {
    $vfx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    $before = (Get-ItemProperty $vfx -Name VisualFXSetting -ErrorAction SilentlyContinue).VisualFXSetting
    Set-PDVisualPerformance
    Assert ((Get-ItemProperty $vfx -Name VisualFXSetting).VisualFXSetting -eq 3) 'not applied'
    Undo-PDChanges
    $after = (Get-ItemProperty $vfx -Name VisualFXSetting -ErrorAction SilentlyContinue).VisualFXSetting
    Assert ("$after" -eq "$before") "not restored: before=$before after=$after"
    $true
}

Test-Case 'Safe file move never overwrites or loses data' {
    $t = Join-Path $env:TEMP ('sjv-move-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $src = Join-Path $t 'src'; $dst = Join-Path $t 'dst'
    New-Item -ItemType Directory -Path (Join-Path $src 'sub'), $dst -Force | Out-Null
    Set-Content (Join-Path $src 'a.txt') 'A'
    Set-Content (Join-Path $src 'sub\b.txt') 'B'
    Set-Content (Join-Path $src 'clash.txt') 'OLD-ON-C'
    (Get-Item (Join-Path $src 'clash.txt')).LastWriteTime = (Get-Date).AddDays(-10)
    Set-Content (Join-Path $dst 'clash.txt') 'NEWER-ON-D'
    # all-or-nothing (used for C:\ root folders): must change nothing
    $left = Move-PDTree -Source $src -Dest $dst -AllOrNothing
    Assert ($left -gt 0) 'clash not detected'
    Assert (Test-Path (Join-Path $src 'a.txt')) 'all-or-nothing deleted a source file'
    Assert ((Get-Content (Join-Path $dst 'clash.txt')) -eq 'NEWER-ON-D') 'destination file overwritten'
    # normal mode (known folders): moves what verified, keeps the clash on C:
    $left = Move-PDTree -Source $src -Dest $dst
    Assert ($left -eq 1) "expected 1 file left, got $left"
    Assert (-not (Test-Path (Join-Path $src 'a.txt'))) 'a.txt not moved'
    Assert ((Get-Content (Join-Path $dst 'sub\b.txt')) -eq 'B') 'b.txt missing at destination'
    Assert ((Get-Content (Join-Path $src 'clash.txt')) -eq 'OLD-ON-C') 'clash source deleted'
    Assert ((Get-Content (Join-Path $dst 'clash.txt')) -eq 'NEWER-ON-D') 'destination file overwritten'
    Remove-Item $t -Recurse -Force
    $true
}

Test-Case 'Windows 11 CPU heuristic' {
    $cases = @{
        'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz' = $true; 'Intel(R) Core(TM) i3-7100U CPU @ 2.40GHz' = $false
        '11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz' = $true; 'Intel(R) Core(TM) i5-4590 CPU @ 3.30GHz' = $false
        'Intel(R) Celeron(R) N4020 CPU @ 1.10GHz' = $true; 'AMD Ryzen 7 1700 Eight-Core Processor' = $false
        'AMD Ryzen 5 5600G with Radeon Graphics' = $true; 'AMD A6-9225 RADEON R4, 5 COMPUTE CORES 2C+2G' = $false
        'Intel(R) Core(TM) Ultra 5 125H' = $true; 'Intel(R) Core(TM)2 Duo CPU E7500 @ 2.93GHz' = $false
    }
    $bad = foreach ($k in $cases.Keys) { $r = Test-PDWin11Cpu $k; if ($r -ne $cases[$k]) { "$k -> $r" } }
    Assert (-not $bad) ($bad -join '; ')
    $true
}

Test-Case 'Startup suggestion rules' {
    $items = @(
        [pscustomobject]@{ Name = 'Spotify'; Command = 'C:\Users\x\AppData\Roaming\Spotify\Spotify.exe /minimized'; Enabled = $true }
        [pscustomobject]@{ Name = 'SecurityHealth'; Command = 'C:\Windows\system32\SecurityHealthSystray.exe'; Enabled = $true }
        [pscustomobject]@{ Name = 'RtkAudUService'; Command = 'C:\Windows\System32\RtkAudUService64.exe'; Enabled = $true }
        [pscustomobject]@{ Name = 'OneDrive'; Command = 'OneDrive.exe /background'; Enabled = $true }
    )
    $s = @(Get-PDSafeStartupToDisable -Items $items -DataDir $DataDir -RamGB 16) | ForEach-Object { $_.Name }
    Assert ($s -contains 'Spotify') 'Spotify should be suggested'
    Assert (-not ($s -contains 'SecurityHealth')) 'SecurityHealth must never be suggested'
    Assert (-not ($s -contains 'RtkAudUService')) 'audio driver must never be suggested'
    Assert (-not ($s -contains 'OneDrive')) 'OneDrive only on <=4 GB RAM'
    $true
}

Test-Case 'App advisor flags unwanted software' {
    $apps = @(
        [pscustomobject]@{ Name = 'uTorrent'; Uninstall = 'x'; SizeMB = 5 }
        [pscustomobject]@{ Name = 'Tally.ERP 9'; Uninstall = 'x'; SizeMB = 5 }
        [pscustomobject]@{ Name = 'Quick Heal Total Security'; Uninstall = 'x'; SizeMB = 5 }
        [pscustomobject]@{ Name = 'Avast Free Antivirus'; Uninstall = 'x'; SizeMB = 5 }
    )
    $info = [pscustomobject]@{ RAMGB = 16; Disks = @([pscustomobject]@{ IsSystem = $true; MediaType = 'SSD' }) }
    $a = @(Get-PDAppAdvice -Apps $apps -Info $info -DataDir $DataDir)
    Assert (($a | Where-Object App -eq 'uTorrent').Kind -eq 'pup') 'uTorrent not flagged'
    Assert (-not ($a | Where-Object App -like 'Tally*')) 'Tally must not be flagged'
    Assert (@($a | Where-Object Kind -eq 'av').Count -eq 2) 'two antivirus programs should be flagged'
    $true
}

$script:ScanResult = $null
Test-Case 'Quick scan runs on a real Windows' {
    $s = Invoke-PDScan -DataDir $DataDir
    $script:ScanResult = $s
    Assert ($s.Score -ge 5 -and $s.Score -le 100) "bad score $($s.Score)"
    Assert ($s.Info.RAMGB -gt 0) 'RAM not detected'
    Assert ($s.Info.CPU) 'CPU not detected'
    Assert (@($s.Findings).Count -ge 1) 'no findings'
    Write-Host ("      score {0}, {1} findings, {2} startup items, {3} apps, image {4}, OS {5} {6}" -f $s.Score, @($s.Findings).Count, @($s.Startup).Count, @($s.Apps).Count, $s.ImageHealth, $s.Info.OSCaption, $s.Info.OSBuild)
    foreach ($f in $s.Findings) { Write-Host ("      [{0}] {1}" -f $f.Severity, $f.Title) }
    $true
}

Test-Case 'OS advisor produces recommendations' {
    Assert $script:ScanResult 'scan missing'
    $adv = Get-PDOSAdvice -Info $script:ScanResult.Info -DataDir $DataDir
    Assert (@($adv.Recommendations).Count -ge 1) 'no recommendations'
    Assert (@($adv.Win11.Checks).Count -eq 6) 'win11 checks missing'
    foreach ($r in $adv.Recommendations) { Write-Host "      $($r.Title) [$($r.Fit)]" }
    $script:Adv = $adv
    $true
}

Test-Case 'HTML report is written' {
    $f = New-PDReport -Scan $script:ScanResult -OSAdvice $script:Adv -Actions @('test action')
    Assert (Test-Path $f) 'report missing'
    $html = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
    Assert ($html -match 'संजीवनी') 'Marathi text garbled in report'
    Copy-Item $f (Join-Path $Root 'test-report.html') -Force
    $true
}

Test-Case 'Storage helpers (read-only)' {
    $docs = Get-PDKnownFolderPath 'Documents'
    Assert $docs 'Documents path not found'
    $null = Get-PDStorageTargets
    $sh = Get-PDShrinkable
    Assert ($sh -ge 0) 'shrinkable negative'
    Write-Host "      Documents: $docs ; safe shrink: $(Format-PDSize $sh)"
    $true
}

Test-Case 'Drivers backup (DISM export) works' {
    $dest = Join-Path $env:TEMP ('sjv-drv-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $r = Backup-PDDrivers -Destination $dest
    Assert ($r.ExitCode -eq 0) "DISM export failed: $($r.ExitCode)"
    Assert (Test-Path $dest) 'backup folder missing'
    Write-Host "      exported $($r.Count) drivers ($(Format-PDSize $r.Bytes))"
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    $true
}

Test-Case 'Background job runner pattern (runspace + modules)' {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $rs.SessionStateProxy.SetVariable('PDLogQueue', $q)
    $rs.SessionStateProxy.SetVariable('PDCtx', $global:PDCtx)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $mods = @('Common', 'Diagnostics', 'Advisor') | ForEach-Object { Join-Path $fakeUsb "Sanjeevani\PCDoctor\lib\$_.psm1" }
    $wrapper = { param($Mods, $WorkText, $P) foreach ($m in $Mods) { Import-Module $m -Force -DisableNameChecking }; & ([scriptblock]::Create($WorkText)) $P }
    $work = { param($P) Write-PDLog 'hello from job'; [pscustomobject]@{ Ram = (Get-PDSystemInfo).RAMGB; X = $P.X } }
    [void]$ps.AddScript($wrapper.ToString()).AddArgument($mods).AddArgument($work.ToString()).AddArgument(@{ X = 42 })
    $out = $ps.Invoke()
    $last = $out[$out.Count - 1]
    $ps.Dispose(); $rs.Close()
    Assert ($last.X -eq 42) 'params not passed'
    Assert ($last.Ram -gt 0) 'module call failed in runspace'
    $line = $null; $got = $false
    while ($q.TryDequeue([ref]$line)) { if ($line -match 'hello from job') { $got = $true } }
    Assert $got 'log queue not shared'
    $true
}

Remove-Item $fakeUsb -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ summary
$md = "## Sanjeevani tests`n`n| Test | Result | Detail |`n|---|---|---|`n"
foreach ($r in $script:Results) { $md += "| $($r.Test) | $($r.Result) | $($r.Detail -replace '\|', '/' -replace "`n", ' ') |`n" }
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md -Encoding UTF8 }
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f ($script:Results.Count - $script:Failed), $script:Failed)
exit $script:Failed
