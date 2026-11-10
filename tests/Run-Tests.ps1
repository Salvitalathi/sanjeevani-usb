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

Test-Case 'Scripts define every function before the main flow calls it' {
    $bad = @()
    foreach ($f in @(Get-ChildItem $Root -File -Filter *.ps1) + @(Get-ChildItem (Join-Path $Kit 'Sanjeevani\PCDoctor') -Recurse -File -Filter *.ps1)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        $defs = @{}
        foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if (-not $defs.ContainsKey($fn.Name)) { $defs[$fn.Name] = $fn.Extent.StartOffset }
        }
        foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = $c.GetCommandName()
            if (-not $name -or -not $defs.ContainsKey($name)) { continue }
            # calls inside a function body run later, when that function is called; only the top-level flow matters
            $p = $c.Parent; $inFn = $false
            while ($p) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst] -or $p -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $inFn = $true; break }; $p = $p.Parent }
            if (-not $inFn -and $c.Extent.StartOffset -lt $defs[$name]) { $bad += "$($f.Name) line $($c.Extent.StartLineNumber): $name used before it is defined" }
        }
    }
    Assert (-not $bad.Count) ($bad -join '; ')
}

Test-Case 'No [math]::Max/Min mixes a small int with a byte count (Int32 overflow)' {
    # [math]::Max(0, $bytes) picks the Int32 overload and fails once the value passes 2 GB
    $bad = @()
    foreach ($f in $psFiles) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '[math]' -and $n.Member.Extent.Text -in 'Max', 'Min' }, $true)) {
            $args2 = @($c.Arguments)
            $hasInt = @($args2 | Where-Object { $_ -is [System.Management.Automation.Language.ConstantExpressionAst] -and $_.Value -is [int] }).Count
            $big = @($args2 | Where-Object { $_.Extent.Text -match '(?i)byte|size|free|need|total|after|before|\$now|keep|extent|length\b' -and $_.Extent.Text -notmatch '^\[(double|long|int64|uint64)\]' -and $_.Extent.Text -notmatch '\.(Count|Length)$' }).Count
            if ($hasInt -and $big) { $bad += "$($f.Name) line $($c.Extent.StartLineNumber): $($c.Extent.Text)" }
        }
    }
    Assert (-not $bad.Count) ($bad -join '; ')
    Assert ([math]::Max([double]0, [double](6795890688 - 0)) -eq 6795890688) 'double overload'
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

Test-Case 'Boot menu config: no \u0026 escapes, per-tool icons win' {
    $src = Get-Content (Join-Path $Root 'Setup-Sanjeevani.ps1') -Raw -Encoding UTF8
    $m = [regex]::Match($src, "(?m)^\`$json = \`$json\.Replace.*$")
    Assert $m.Success 'escape fix line missing in setup'
    $json = [ordered]@{ menu_alias = @([ordered]@{ image = '/ISO/06-clonezilla.iso'; alias = "Clonezilla  -  Disk Clone & Image <it's>" }) } | ConvertTo-Json -Depth 4
    Invoke-Expression $m.Value
    Assert ($json -notmatch '\\u00') "still escaped: $json"
    Assert ($json -match 'Disk Clone & Image') 'ampersand missing'
    $null = $json | ConvertFrom-Json
    $icons = Join-Path $Kit 'ventoy\theme\sanjeevani\icons'
    foreach ($g in 'vtoyiso', 'vtoyimg', 'vtoyefi') { Assert (-not (Test-Path (Join-Path $icons "$g.png"))) "$g.png would hide the tool icons" }
    $cat = Get-Content (Join-Path $Kit 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in $cat.isos) { Assert (Test-Path (Join-Path $icons "$($e.class).png")) "icon for class $($e.class) missing" }
    $true
}

Test-Case 'PC Doctor window (XAML) loads' {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $src = Get-Content (Join-Path $Kit 'Sanjeevani\PCDoctor\PCDoctor.ps1') -Raw -Encoding UTF8
    $m = [regex]::Match($src, "(?s)\[xml\]\`$xaml = @'\r?\n(.*?)\r?\n'@")
    Assert $m.Success 'XAML block not found'
    [xml]$x = $m.Groups[1].Value
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    foreach ($n in 'FindingsList', 'StartupList', 'BloatList', 'FolderList', 'LogBox', 'Progress', 'TargetCombo', 'Win11List', 'AppList', 'TgList', 'TgDetail', 'TgSearch', 'StopBtn', 'LangMr', 'LangEn', 'RegList', 'RegInfo', 'OptCard', 'OptPanel', 'AskBox', 'ChatPanel', 'ChatScroll', 'AskGoBtn', 'AiMode', 'AiStatus', 'AiSettings', 'AiKey', 'AiProvider') {
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
    foreach ($m in 'Common', 'Diagnostics', 'Repair', 'Speed', 'Storage', 'Advisor', 'Report', 'ToolGuide', 'Integrity', 'Registry', 'Ask', 'LocalAI', 'Troubleshoot') {
        Import-Module (Join-Path $fakeUsb "Sanjeevani\PCDoctor\lib\$m.psm1") -Force -DisableNameChecking
    }
    $ctx = Initialize-PDContext -UsbRoot $fakeUsb
    Assert (Test-Path $ctx.ReportDir) 'report dir not created'
    $true
}

Test-Case 'Tools guide: every tool has Marathi + English help and a valid check' {
    $g = Get-Content (Join-Path $DataDir 'toolguide.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cat = Get-Content (Join-Path $fakeUsb 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $src = Get-Content (Join-Path $fakeUsb 'Sanjeevani\PCDoctor\lib\ToolGuide.psm1') -Raw
    $handlers = [regex]::Matches($src, "(?m)^\s*'([a-z-]+)'\s+\{ return Invoke-TG") | ForEach-Object { $_.Groups[1].Value }
    $groups = @($g.groups | ForEach-Object { $_.id })
    $bad = @()
    foreach ($e in @($cat.isos) + @($cat.tools)) { if (-not $g.tools.($e.id)) { $bad += "no guide for $($e.id)" } }
    foreach ($p in $g.tools.PSObject.Properties) {
        $v = $p.Value
        if ($v.risk -notin 'safe', 'caution', 'danger') { $bad += "$($p.Name): risk" }
        if ($v.group -notin $groups) { $bad += "$($p.Name): group" }
        foreach ($l in 'mr', 'en') { if (-not $v.$l.what) { $bad += "$($p.Name): $l.what" }; if (-not @($v.$l.steps).Count) { $bad += "$($p.Name): $l.steps" } }
        if ($v.risk -eq 'danger' -and -not @($v.mr.warn).Count) { $bad += "$($p.Name): dangerous tool without warnings" }
        if ($v.auto -and $v.auto -notlike 'pd:*' -and $v.auto -notin $handlers) { $bad += "$($p.Name): unknown check $($v.auto)" }
        if ($v.auto -like 'pd:*' -and $v.auto.Substring(3) -notin 'speed', 'advisor', 'drivers', 'repair', 'storage', 'ask') { $bad += "$($p.Name): unknown PC Doctor page" }
    }
    Assert (-not $bad.Count) ($bad -join '; ')
}

Test-Case 'Tools guide: tool output parsers (CrystalDiskInfo, WizTree)' {
    $cdi = @"
----------------------------------------------------------------------------
 (1) Samsung SSD 860 EVO 500GB
----------------------------------------------------------------------------
           Model : Samsung SSD 860 EVO 500GB
   Health Status : Good (98 %)
     Temperature : 34 C (93 F)
----------------------------------------------------------------------------
 (2) WDC WD10EZEX
----------------------------------------------------------------------------
           Model : WDC WD10EZEX-08WN4A0
   Health Status : Caution
"@
    $d = @(ConvertFrom-TGDiskInfo $cdi)
    Assert ($d.Count -eq 2) "disks: $($d.Count)"
    Assert ($d[0].Health -eq 'Good' -and $d[0].Percent -eq 98 -and $d[0].TempC -eq 34) 'disk 1'
    Assert ($d[1].Health -eq 'Caution' -and $null -eq $d[1].TempC) 'disk 2 (no temperature must not borrow disk 1''s)'
    $wz = "Generated by WizTree 4.33 3/11/2026`r`n""File Name"",""Size"",""Allocated"",""Modified"",""Attributes"",""Files"",""Folders""`r`n""C:\"",100,100,,,1,1`r`n""C:\Users\"",80,80,,,1,1`r`n""C:\Users\Ram\Downloads\"",50,50,,,1,1"
    $w = @(ConvertFrom-TGWizTreeCsv $wz)
    Assert ($w.Count -eq 3) "rows: $($w.Count)"
    Assert ($w[2].Path -eq 'C:\Users\Ram\Downloads' -and $w[2].Size -eq 50 -and $w[2].Depth -eq 3) 'row 3'
    $f = Join-Path $env:TEMP 'sjv-ini-test.ini'
    Set-Content $f "[Settings]`r`nTheme=1`r`nSensorsOnly=0`r`n[Other]`r`nX=1"
    Set-TGIniValue $f 'Settings' @{ SensorsOnly = 1; AutoUpdate = 0 }
    $ini = Get-Content $f -Raw; Remove-Item $f
    Assert ($ini -match 'SensorsOnly=1' -and $ini -notmatch 'SensorsOnly=0' -and $ini -match 'Theme=1' -and $ini -match '(?s)AutoUpdate=0.*\[Other\]') "ini: $ini"
}

Test-Case 'Tools guide: built-in checks run on this Windows' {
    $null = Initialize-PDContext -UsbRoot $fakeUsb
    $global:PDState = [hashtable]::Synchronized(@{ Progress = -1; Status = ''; Cancel = $false })
    foreach ($h in 'battery', 'system-summary', 'network', 'crashes', 'memdiag', 'disk-health', 'keys') {
        $r = Invoke-TGAuto -Handler $h -UsbRoot $fakeUsb -P @{ ReportDir = $global:PDCtx.ReportDir }
        Assert ($r -and $r.HeadMr -and $r.HeadEn -and $r.Status -in 'ok', 'warn', 'bad', 'info') "$h returned no proper result"
        Write-Host ("      {0,-15} [{1}] {2} | {3}" -f $h, $r.Status, $r.HeadEn, (($r.LinesEn | Select-Object -First 2) -join ' / ')) -ForegroundColor DarkGray
    }
}

Test-Case 'Tools guide: real tools are found, set up and driven automatically' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Setup-Sanjeevani.ps1'), [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($fn.Name -in 'Get-7zr', 'Resolve-Source', 'Save-Url', 'Get-WebText', 'Ok', 'Say', 'Warn') { . ([scriptblock]::Create($fn.Extent.Text)) }
    }
    $UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SanjeevaniSetup/1.0'
    $BrowserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
    $Work = Join-Path $env:TEMP 'sjv-tg-dl'; New-Item -ItemType Directory $Work -Force | Out-Null
    $haveCurl = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
    $cat = Get-Content (Join-Path $fakeUsb 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $got = @{}
    foreach ($id in 'crystaldiskinfo', 'wiztree', 'produkey', 'bluescreenview', 'prime95', 'cpuz', 'hwinfo') {
        $e = $cat.tools | Where-Object { $_.id -eq $id }
        try {
            $r = Resolve-Source $e
            $tmp = Join-Path $Work ($id + '_' + $r.Name)
            Save-Url $r.Url $tmp $e.page
            $folder = Join-Path $fakeUsb ("Tools\$($e.category)\" + ($e.name -replace '[^\w\-\. ]', ''))
            New-Item -ItemType Directory $folder -Force | Out-Null
            $fs = [IO.File]::OpenRead($tmp); $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte(); $fs.Close()
            if ($b1 -eq 0x50 -and $b2 -eq 0x4B) { $z = "$tmp.zip"; Move-Item $tmp $z -Force; Expand-Archive $z $folder -Force }
            elseif ($b1 -eq 0x37 -and $b2 -eq 0x7A) { & (Get-7zr) x $tmp ("-o" + $folder) -y | Out-Null }
            else { Copy-Item $tmp (Join-Path $folder $r.Name) }
            $exe = Find-TGTool -UsbRoot $fakeUsb -Id $id
            Assert $exe "$id downloaded but its program was not found"
            $got[$id] = $exe
        } catch {
            if ($_.Exception.Message -match 'program was not found') { throw }
            Write-Host "      SKIP $id - download failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    $P = @{ ReportDir = $global:PDCtx.ReportDir; Minutes = 0.5 }
    $fails = @()
    $run = { param($h) $r = Invoke-TGAuto -Handler $h -UsbRoot $fakeUsb -P $P
        Write-Host ("      {0,-15} [{1}] {2} | {3}" -f $h, $r.Status, $r.HeadEn, (($r.LinesEn | Select-Object -First 3) -join ' / ')) -ForegroundColor DarkGray; $r }
    if ($got.crystaldiskinfo) {
        $r = & $run 'disk-health'
        $txt = Join-Path (Split-Path $got.crystaldiskinfo) 'DiskInfo.txt'
        if (-not (Test-Path $txt)) { $fails += 'CrystalDiskInfo /CopyExit wrote no DiskInfo.txt' }
        else {
            $raw = Get-Content $txt -Raw
            Write-Host '      --- DiskInfo.txt (start) ---' -ForegroundColor DarkGray
            ($raw -split "`r?`n" | Select-Object -First 45) | ForEach-Object { Write-Host "      | $_" -ForegroundColor DarkGray }
            # virtual disks on CI have no SMART data, so CrystalDiskInfo may list none; parsing must work when it does
            if (($raw -match '(?m)^\s*Model\s*:') -and ($r.LinesEn -match 'From Windows')) { $fails += 'CrystalDiskInfo listed disks but its result was not used' }
        }
    }
    if ($got.wiztree) { $r = & $run 'bigfolders'; if (-not ($r.Status -eq 'ok' -and $r.LinesEn.Count -ge 3)) { $fails += 'WizTree export gave no folder list' } }
    if ($got.produkey) { $r = & $run 'keys' }
    if ($got.bluescreenview) { $r = & $run 'crashes' }
    if ($got.cpuz) { $r = & $run 'system-summary'; if (-not ($r.File -and (Test-Path $r.File))) { $fails += 'CPU-Z -txt report not written' } }
    if ($got.hwinfo) {
        $r = & $run 'temps'
        Start-Sleep 3; Get-Process HWiNFO* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $ini = Get-ChildItem (Split-Path $got.hwinfo) -Filter 'HWiNFO*.INI' | Select-Object -First 1
        if (-not ($ini -and ((Get-Content $ini.FullName -Raw) -match 'SensorsOnly=1'))) { $fails += 'HWiNFO not set to open the Sensors window' }
    }
    if ($got.prime95) {
        $r = & $run 'stress-cpu'
        Get-Process prime95 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not ($r.Status -in 'ok', 'warn' -and $r.HeadEn -match 'no errors')) { $fails += "stress test: $($r.HeadEn)" }
    }
    Assert (-not $fails.Count) ($fails -join '; ')
    Assert ($got.Count -ge 4) "only $($got.Count) tools could be downloaded"
}

Test-Case 'USB virus check: finds and quarantines what malware typically does' {
    $u = Join-Path $env:TEMP ('sjv-int-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    foreach ($d in 'Sanjeevani', 'Tools\Hardware\CPU-Z', 'ISO', 'Photos', 'Reports\PC1') { New-Item -ItemType Directory (Join-Path $u $d) -Force | Out-Null }
    $blob = { param($rel, $n, $seed) $b = New-Object byte[] $n; (New-Object Random $seed).NextBytes($b); [IO.File]::WriteAllBytes((Join-Path $u $rel), $b) }
    & $blob 'Tools\Hardware\CPU-Z\cpuz_x64.exe' 300000 1
    & $blob 'Tools\Hardware\CPU-Z\cpuz.dll' 200000 2
    Set-Content (Join-Path $u 'Tools\Hardware\CPU-Z\cpuz.ini') 'a=1'
    Set-Content (Join-Path $u 'START-Sanjeevani.cmd') '@echo off'
    Set-Content (Join-Path $u 'Photos\family.jpg') 'jpg'
    $tools = Get-Item (Join-Path $u 'Tools') -Force; $tools.Attributes = 'Directory, Hidden'
    $n = New-SJManifest -Root $u
    Assert ($n -eq 3) "recorded $n files"
    $c = Test-SJIntegrity -Root $u -Full
    Assert ((Get-SJIssueCount $c) -eq 0) ('clean USB reported issues: ' + ((Format-SJResult $c 'en') -join ' | '))
    # --- what malware does
    [IO.File]::AppendAllText((Join-Path $u 'Tools\Hardware\CPU-Z\cpuz_x64.exe'), 'VIRUS')           # file infector (size changes)
    $b = [IO.File]::ReadAllBytes((Join-Path $u 'Tools\Hardware\CPU-Z\cpuz.dll')); $b[100] = $b[100] -bxor 0xFF
    [IO.File]::WriteAllBytes((Join-Path $u 'Tools\Hardware\CPU-Z\cpuz.dll'), $b)                      # same size, different content
    Set-Content (Join-Path $u 'Tools\Hardware\CPU-Z\svchost.exe') 'MZ evil'
    Set-Content (Join-Path $u 'autorun.inf') "[autorun]`r`nopen=svchost.exe"
    (Get-Item (Join-Path $u 'Photos') -Force).Attributes = 'Directory, Hidden, System'                # shortcut virus
    Set-Content (Join-Path $u 'Photos.lnk') 'lnk'
    Set-Content (Join-Path $u 'Tools\Hardware\CPU-Z\cpuz.ini') 'a=2'                                  # normal settings change
    Set-Content (Join-Path $u 'Reports\PC1\evil-from-customer.exe') 'x'                              # customer data: not judged
    New-Item -ItemType Directory (Join-Path $u 'MyTools\AnyDesk') -Force | Out-Null
    Set-Content (Join-Path $u 'MyTools\AnyDesk\AnyDesk.exe') 'MZ mine'                                # the user's own app
    $c = Test-SJIntegrity -Root $u
    Assert ($c.Changed -contains 'Tools\Hardware\CPU-Z\cpuz_x64.exe') 'size change not found'
    Assert ($c.Changed -notcontains 'Tools\Hardware\CPU-Z\cpuz.dll') 'quick check must not hash'
    Assert ($c.NewExec -contains 'Tools\Hardware\CPU-Z\svchost.exe') 'new program not found'
    Assert ($c.Autorun) 'autorun.inf not found'
    Assert ($c.HiddenFolders -contains 'Photos' -and $c.HiddenFolders -notcontains 'Tools') "hidden folders: $($c.HiddenFolders -join ',')"
    Assert ($c.RootLinks -contains 'Photos.lnk') 'root shortcut not found'
    Assert (-not ($c.NewExec -match 'Reports')) 'customer data must not be judged'
    Assert ($c.NewMyTools -contains 'MyTools\AnyDesk\AnyDesk.exe' -and -not ($c.NewExec -match 'MyTools')) 'own app in MyTools must be asked about, not treated as a virus'
    $c = Test-SJIntegrity -Root $u -Full
    Assert ($c.Changed -contains 'Tools\Hardware\CPU-Z\cpuz.dll') 'full check missed a same-size change'
    $fix = Repair-SJIntegrity $c
    Assert (Test-Path (Join-Path $u 'MyTools\AnyDesk\AnyDesk.exe')) 'own app quarantined without asking'
    Assert ((Add-SJTrusted -Root $u -Rel @($c.NewMyTools)) -eq 1) 'own app not recorded'
    Assert (Test-Path (Join-Path $u '_to_delete\quarantine\Tools\Hardware\CPU-Z\svchost.exe.quarantine')) 'not quarantined'
    Assert (-not (Test-Path (Join-Path $u 'Tools\Hardware\CPU-Z\cpuz_x64.exe'))) 'infected program still in place'
    Assert ((Get-Item (Join-Path $u 'autorun.inf') -Force).PSIsContainer) 'autorun.inf not blocked by a folder'
    Assert (-not ((Get-Item (Join-Path $u 'Photos') -Force).Attributes -band [IO.FileAttributes]::Hidden)) 'folder still hidden'
    Assert (((Get-Item (Join-Path $u 'Tools') -Force).Attributes -band [IO.FileAttributes]::Hidden)) 'Sanjeevani''s own hidden Tools folder must stay hidden'
    Assert ($fix.Redownload -contains 'Tools\Hardware\CPU-Z\cpuz_x64.exe') 'changed tool not listed for re-download'
    $c = Test-SJIntegrity -Root $u -Full
    Assert ((Get-SJIssueCount $c) -eq 0) ('after repair: ' + ((Format-SJResult $c 'en') -join ' | '))
    Assert ((Update-SJManifest -Root $u) -eq 2) 'quarantined files not dropped from the record'
    # --- write-protected USB
    & icacls.exe $u /deny "$($env:USERNAME):(OI)(CI)(WD,AD,WEA,WA)" | Out-Null
    try {
        Assert (-not (Test-SJWritable $u)) 'locked USB reported as writable'
        $c = Test-SJIntegrity -Root $u
        Assert ($c.Locked) 'lock not detected'
        Assert ((Repair-SJIntegrity $c).Error -eq 'locked') 'repair must not try on a locked USB'
    } finally { & icacls.exe $u /remove:d $env:USERNAME /T | Out-Null }
    Remove-Item $u -Recurse -Force
    $true
}

Test-Case 'Tools guide lists the user''s own apps from MyTools' {
    $u = Join-Path $env:TEMP ('sjv-my-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    foreach ($d in 'MyTools\AnyDesk', 'MyTools\Empty Folder') { New-Item -ItemType Directory (Join-Path $u $d) -Force | Out-Null }
    Set-Content (Join-Path $u 'MyTools\AnyDesk\AnyDesk.exe') 'MZ'
    Set-Content (Join-Path $u 'MyTools\AnyDesk\uninstall.exe') 'MZ'
    Set-Content (Join-Path $u 'MyTools\ChromeSetup.exe') 'MZ'
    Set-Content (Join-Path $u 'MyTools\README.txt') 'readme'
    Set-Content (Join-Path $u 'MyTools\AnyDesk.txt') "Remote support app`r`nGive the 9-digit ID only to people you know." -Encoding UTF8
    $m = @(Get-TGMyTools $u)
    Assert ($m.Count -eq 2) "entries: $(($m | ForEach-Object { $_.Name }) -join ', ')"
    $a = $m | Where-Object { $_.Name -eq 'AnyDesk' }
    Assert ($a.Path -like '*\AnyDesk\AnyDesk.exe' -and -not $a.Installer) 'folder app: wrong program picked'
    Assert ($a.Info -eq 'Remote support app' -and $a.Notes.Count -eq 1) 'description .txt not used'
    Assert (($m | Where-Object { $_.Name -eq 'ChromeSetup' }).Installer) 'installer not recognised'
    # a zip: listed until it is unpacked, then its program is listed instead
    $z = Join-Path $env:TEMP ('sjv-zipsrc-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory (Join-Path $z 'TreeSize') -Force | Out-Null
    Set-Content (Join-Path $z 'TreeSize\TreeSize.exe') 'MZ'
    Compress-Archive -Path (Join-Path $z 'TreeSize') -DestinationPath (Join-Path $u 'MyTools\TreeSize.zip')
    Remove-Item $z -Recurse -Force
    $m = @(Get-TGMyTools $u)
    Assert (($m | Where-Object { $_.Name -eq 'TreeSize' }).Archive) 'zip not listed'
    $d = Expand-TGMyArchive -UsbRoot $u -Archive (Join-Path $u 'MyTools\TreeSize.zip')
    Assert (Test-Path (Join-Path $d 'TreeSize.exe')) "zip with one folder inside not unpacked flat: $d"
    $t2 = @(@(Get-TGMyTools $u) | Where-Object { $_.Name -eq 'TreeSize' })
    Assert ($t2.Count -eq 1 -and -not $t2[0].Archive -and $t2[0].Path -like '*\TreeSize\TreeSize.exe') 'unpacked program not listed'
    Remove-Item $u -Recurse -Force
    $true
}

Test-Case 'Locked USB: tools that write settings run from a temp copy' {
    $d = Join-Path $env:TEMP ('sjv-ro-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '\FakeTool')
    New-Item -ItemType Directory $d -Force | Out-Null
    Set-Content (Join-Path $d 'fake.exe') 'MZ'; Set-Content (Join-Path $d 'fake.dll') 'x'
    & icacls.exe $d /deny "$($env:USERNAME):(OI)(CI)(WD,AD,WEA,WA)" | Out-Null      # like a locked USB: readable, not writable
    try {
        $probe = $false; try { [IO.File]::WriteAllText((Join-Path $d 'probe.txt'), 'x'); $probe = $true } catch { }
        Assert (-not $probe) 'test setup: folder is still writable'
        Assert ((Get-Content (Join-Path $d 'fake.dll')) -eq 'x') 'test setup: a locked USB must stay readable'
        $run = Get-TGRunPath (Join-Path $d 'fake.exe')
        Assert ($run -ne (Join-Path $d 'fake.exe')) 'tool would run from the locked USB'
        Assert ((Test-Path $run) -and (Test-Path (Join-Path (Split-Path $run) 'fake.dll'))) "temp copy incomplete: $run"
        Initialize-TGToolConfig 'hwinfo' $run
    } finally { & icacls.exe $d /remove:d $env:USERNAME /T | Out-Null }
    Remove-Item (Split-Path $d) -Recurse -Force
    $true
}

Test-Case 'Junk is measured per category; blue-screen dumps are kept' {
    $d = Join-Path $env:TEMP ('sjv-junk-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory $d -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $d 'big.tmp'), (New-Object byte[] (6MB)))
    $cats = @(Get-PDJunkCategories)
    $ut = $cats | Where-Object { $_.Id -eq 'usertemp' }
    Assert ($ut -and (Get-PDPathBytes $ut.Paths $ut.Filter) -ge 6MB) 'user temp not measured'
    Assert (@($cats | Where-Object { $_.Id -eq 'browser' }).Count -eq 1) 'browser cache category missing'
    $src = Get-Content (Join-Path $fakeUsb 'Sanjeevani\PCDoctor\lib\Speed.psm1') -Raw
    Assert ($src -notmatch "'System error minidump files'") 'Disk Cleanup must keep minidumps (needed to find blue-screen drivers)'
    Remove-Item $d -Recurse -Force
    $true
}

Test-Case 'Registry check finds virus-style and broken entries, fixes them and Undo restores them' {
    $keep = $global:PDCtx
    $tmpRoot = Join-Path $env:TEMP ('sjv-reg-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory $tmpRoot -Force | Out-Null
    $null = Initialize-PDContext -UsbRoot $tmpRoot          # fresh undo journal
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $pol = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $un = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SanjeevaniTestOrphan'
    try {
        if (-not (Test-Path $run)) { New-Item $run -Force | Out-Null }
        New-ItemProperty -Path $run -Name 'SanjeevaniTestMissing' -Value '"C:\NoSuchFolder\gone.exe" /min' -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $run -Name 'SanjeevaniTestOk' -Value "`"$env:WINDIR\System32\notepad.exe`"" -PropertyType String -Force | Out-Null
        if (-not (Test-Path $pol)) { New-Item $pol -Force | Out-Null }
        New-ItemProperty -Path $pol -Name 'DisableRegistryTools' -Value 1 -PropertyType DWord -Force | Out-Null
        New-Item $un -Force | Out-Null
        New-ItemProperty -Path $un -Name 'DisplayName' -Value 'Sanjeevani Test Orphan' -Force | Out-Null
        New-ItemProperty -Path $un -Name 'UninstallString' -Value '"C:\NoSuchFolder\unins000.exe"' -Force | Out-Null
        Assert ((Get-PDCommandTarget 'rundll32.exe "C:\NoSuch\x.dll",Run') -eq 'C:\NoSuch\x.dll') 'rundll32 target'
        Assert ((Get-PDCommandTarget '%windir%\system32\SecurityHealthSystray.exe') -like '*\SecurityHealthSystray.exe') 'env var target'
        $all = @(Get-PDRegistryIssues)
        Write-Host ("      found {0} issue(s) on this PC: {1}" -f $all.Count, (($all | ForEach-Object { $_.Title }) -join ' | ')) -ForegroundColor DarkGray
        $foreign = @($all | Where-Object { $_.Name -notlike 'SanjeevaniTest*' -and $_.Key -notlike '*SanjeevaniTestOrphan' -and $_.Name -ne 'DisableRegistryTools' -and $_.Kind -eq 'malware' -and $_.Severity -eq 'Critical' })
        Assert (-not $foreign.Count) ('clean Windows reported as infected: ' + (($foreign | ForEach-Object { "$($_.Title) [$($_.Detail)]" }) -join ' | '))
        $mine = @($all | Where-Object { ($_.Name -in 'SanjeevaniTestMissing', 'SanjeevaniTestOk', 'DisableRegistryTools' -and $_.Key -like 'HKCU:*') -or $_.Key -like '*SanjeevaniTestOrphan' })
        Assert ($mine.Name -contains 'SanjeevaniTestMissing') 'startup entry with a missing program not found'
        Assert ($mine.Name -notcontains 'SanjeevaniTestOk') 'working startup entry reported'
        Assert ($mine.Name -contains 'DisableRegistryTools') 'blocked Registry Editor not found'
        Assert (@($mine | Where-Object { $_.Action -eq 'removekey' }).Count -eq 1) 'orphan uninstall entry not found'
        $r = Repair-PDRegistryIssues -Issues $mine -NoRestorePoint
        if ($r.Failed) { Get-Content $global:PDCtx.LogFile -Tail 12 | ForEach-Object { Write-Host "      log| $_" -ForegroundColor DarkGray } }
        Assert ($r.Fixed -eq 3 -and $r.Failed -eq 0) "fixed $($r.Fixed), failed $($r.Failed)"
        Assert ($null -eq (Get-ItemProperty $run -Name 'SanjeevaniTestMissing' -ErrorAction SilentlyContinue)) 'startup entry not removed'
        Assert (-not (Test-Path $un)) 'orphan entry not removed'
        Assert ($null -eq (Get-ItemProperty $pol -Name 'DisableRegistryTools' -ErrorAction SilentlyContinue)) 'policy not removed'
        Undo-PDChanges
        Assert ((Get-ItemProperty $run -Name 'SanjeevaniTestMissing' -ErrorAction SilentlyContinue)) 'Undo did not restore the startup entry'
        Assert (Test-Path $un) 'Undo did not restore the uninstall entry'
        Assert ((Get-ItemProperty $pol -Name 'DisableRegistryTools' -ErrorAction SilentlyContinue).DisableRegistryTools -eq 1) 'Undo did not restore the policy value'
    } finally {
        Remove-ItemProperty -Path $run -Name 'SanjeevaniTestMissing', 'SanjeevaniTestOk' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $pol -Name 'DisableRegistryTools' -ErrorAction SilentlyContinue
        Remove-Item $un -Recurse -Force -ErrorAction SilentlyContinue
        $global:PDCtx = $keep
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $true
}

Test-Case 'Problem finder: Marathi / English / Roman Marathi sentences find the right problem' {
    $probs = Get-PDProblems $DataDir
    $cases = [ordered]@{
        'net chalat nahi' = 'no-internet'; 'इंटरनेट चालत नाही' = 'no-internet'; 'माझ्या laptop मध्ये wifi दिसत नाही' = 'wifi'
        'लॅपटॉप खूप गरम होतो आणि fan जोरात फिरतो' = 'overheat'; 'printer print देत नाही' = 'printer'; 'आवाज येत नाही' = 'sound'
        'pc khup halu chalto' = 'slow-pc'; 'C drive full zala' = 'disk-full'; 'blue screen yeto' = 'bsod'; 'PC अचानक बंद पडतो' = 'shutdown'
        'battery lavkar sampte' = 'battery'; 'windows update atakla' = 'windows-update'; 'password visarlo' = 'password'
        'वेळ चुकीची दाखवतो' = 'time'; 'taskbar kaam karat nahi' = 'taskbar'; 'pendrive detect hot nahi' = 'usb'
        'virus aala ani popup yetat' = 'virus'; 'chukun photo delete zale' = 'data-recovery'; 'internet is very slow' = 'slow-internet'
        'My laptop does not start, stuck on logo' = 'no-boot'; 'touchpad not working' = 'keyboard'; 'screen flicker karto' = 'display'
        'bluetooth earbuds connect hot nahi' = 'bluetooth'; 'task manager disabled by administrator' = 'task-manager'
        'hotspot connect hot nahi' = 'wifi'; 'mic चालत नाही' = 'sound'; 'camera chalat nahi zoom madhe' = 'camera'
    }
    $bad = @()
    foreach ($k in $cases.Keys) {
        $m = @(Find-PDProblem -Text $k -Problems $probs)
        $got = if ($m.Count) { $m[0].Problem.id } else { '(none)' }
        if ($got -ne $cases[$k]) { $bad += "'$k' -> $got (expected $($cases[$k]))" }
    }
    Assert (-not $bad.Count) ($bad -join '; ')
    Assert (-not @(Find-PDProblem -Text 'hello how are you' -Problems $probs).Count) 'unrelated text matched a problem'
}

Test-Case 'Problem catalog: every button leads to a real PC Doctor action' {
    $probs = Get-PDProblems $DataDir
    $gui = Get-Content (Join-Path $fakeUsb 'Sanjeevani\PCDoctor\PCDoctor.ps1') -Raw
    $ask = Get-Content (Join-Path $fakeUsb 'Sanjeevani\PCDoctor\lib\Ask.psm1') -Raw
    $guide = Get-Content (Join-Path $DataDir 'toolguide.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $repairs = [regex]::Matches($gui, "'repair:([a-z0-9-]+)'") | ForEach-Object { $_.Groups[1].Value }
    $quick = [regex]::Matches($ask, "(?m)^\s+'([a-z]+)' \{") | ForEach-Object { $_.Groups[1].Value }
    $bad = @()
    foreach ($p in $probs) {
        foreach ($l in 'mr', 'en') { if (-not $p.$l.title -or -not @($p.$l.steps).Count) { $bad += "$($p.id): $l text" } }
        if (-not @($p.actions).Count) { $bad += "$($p.id): no actions" }
        foreach ($a in $p.actions) {
            $ok = switch ($a.t) {
                'scan' { $true } 'optimize' { $true }
                'repair' { $a.id -in $repairs }
                'quick' { $a.id -in $quick }
                'tg' { $guide.tools.($a.id) -and $guide.tools.($a.id).auto -and $guide.tools.($a.id).auto -notlike 'pd:*' }
                'tool' { [bool]$guide.tools.($a.id) }
                'page' { $a.id -in 'speed', 'storage', 'advisor', 'repair', 'toolbox' }
                'fix' { $a.id -in 'registry', 'storage', 'advisor' }
                'settings' { $a.id -like 'ms-settings:*' }
                default { $false }
            }
            if (-not $ok) { $bad += "$($p.id): $($a.t):$($a.id)" }
        }
    }
    Assert (-not $bad.Count) ($bad -join '; ')
}

Test-Case 'AI answer: request is built correctly and only known problems are accepted (Gemini + Claude, mocked)' {
    $probs = Get-PDProblems $DataDir
    $script:sent = @()
    $gem = {
        param($u, $h, $b, $m)
        $script:sent += [pscustomobject]@{ Url = $u; Headers = $h; Body = $b }
        if ($m -eq 'GET') { return '{"models":[{"name":"models/gemini-3.5-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-3.8-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-3.8-flash-lite","supportedGenerationMethods":["generateContent"]}]}' }
        $inner = '{"understood_mr":"WiFi जोडले जात नाही","understood_en":"WiFi will not connect","problem_ids":["wifi","made-up-id","no-internet"],"steps_mr":["Airplane mode बंद करा"],"steps_en":["Turn off airplane mode"],"hardware_likely":false,"note_mr":"","note_en":""}'
        return (ConvertTo-Json -Depth 8 -Compress @{ candidates = @(@{ content = @{ parts = @(@{ text = $inner }) } }) })
    }
    $r = Invoke-PDAiAsk -Text 'wifi connect होत नाही' -Config ([pscustomobject]@{ provider = 'gemini'; key = 'k1'; model = '' }) -Problems $probs -PcInfo 'HP 15; Windows 11' -Transport $gem
    Assert ($r.Model -eq 'gemini-3.8-flash') "newest flash model not picked: $($r.Model)"
    Assert (($r.ProblemIds -join ',') -eq 'wifi,no-internet') "unknown ids must be dropped: $($r.ProblemIds -join ',')"
    Assert ($r.UnderstoodMr -eq 'WiFi जोडले जात नाही') 'Marathi text damaged'
    $req = $script:sent[-1]
    Assert ($req.Url -like '*/models/gemini-3.8-flash:generateContent' -and $req.Headers['x-goog-api-key'] -eq 'k1') 'wrong Gemini request'
    $body = $req.Body | ConvertFrom-Json
    Assert ($body.contents[0].parts[0].text -match 'wifi connect होत नाही' -and $body.contents[0].parts[0].text -match 'HP 15') 'problem / PC info not sent'
    Assert ($body.systemInstruction.parts[0].text -match '- wifi: ') 'catalog not in the prompt'
    $cl = {
        param($u, $h, $b, $m)
        $script:sent += [pscustomobject]@{ Url = $u; Headers = $h; Body = $b }
        return '{"content":[{"type":"text","text":"```json\n{\"understood_mr\":\"printer\",\"problem_ids\":[\"printer\"],\"steps_mr\":[\"a\"],\"steps_en\":[\"a\"]}\n```"}]}'
    }
    $r = Invoke-PDAiAsk -Text 'printer' -Config ([pscustomobject]@{ provider = 'anthropic'; key = 'k2'; model = '' }) -Problems $probs -Transport $cl
    Assert (($r.ProblemIds -join ',') -eq 'printer') 'Claude answer (in a code fence) not parsed'
    Assert ($script:sent[-1].Headers['x-api-key'] -eq 'k2' -and $script:sent[-1].Url -eq 'https://api.anthropic.com/v1/messages') 'wrong Claude request'
}

Test-Case 'AI: a wrong key gives a clear message (real Gemini server)' {
    $msg = ''
    try { [void](Invoke-PDAiAsk -Text 'net chalat nahi' -Config ([pscustomobject]@{ provider = 'gemini'; key = 'not-a-real-key'; model = '' }) -Problems (Get-PDProblems $DataDir)) } catch { $msg = $_.Exception.Message }
    Write-Host "      message: $msg" -ForegroundColor DarkGray
    Assert ($msg -match 'API key|internet|connection|पोहोचता') "unexpected: $msg"
}

Test-Case 'Quick fixes run (DNS, printer queue, USB rescan, time, search)' {
    foreach ($id in 'dns', 'printer', 'usb', 'time', 'search') {
        $r = Invoke-PDQuickFix -Id $id
        Assert ($r -and $r.Mr -and $r.En) "$id gave no result"
        Write-Host ("      {0,-8} ok={1} {2}" -f $id, $r.Ok, $r.En) -ForegroundColor DarkGray
    }
    Assert ((Get-Service Spooler).Status -eq 'Running') 'print service not running after the printer fix'
}

Test-Case 'Assistant: every problem can be checked automatically (or is advice-only on purpose)' {
    $guideOnly = 'password', 'data-recovery', 'reinstall', 'old-pc', 'remote', 'no-boot'
    $have = Get-PDTroubleshootable
    $miss = @((Get-PDProblems $DataDir) | Where-Object { $_.id -notin $have -and $_.id -notin $guideOnly } | ForEach-Object { $_.id })
    Assert (-not $miss.Count) ('no automatic check for: ' + ($miss -join ', '))
}

Test-Case 'Assistant: each check runs on a real Windows and reports in English / Marathi / Hindi' {
    $null = Initialize-PDContext -UsbRoot $fakeUsb
    $global:PDState = [hashtable]::Synchronized(@{ Progress = -1; Status = ''; Cancel = $false })
    $probs = Get-PDProblems $DataDir
    $skip = 'corrupt-windows', 'apps-install', 'slow-pc', 'slow-boot', 'disk-100'     # long (SFC / full scan) - exercised elsewhere
    $bad = @()
    foreach ($id in (Get-PDTroubleshootable | Sort-Object)) {
        if ($id -in $skip) { continue }
        $t0 = Get-Date
        try {
            $r = Invoke-PDTroubleshoot -Ids @('__none__') -Problems $probs     # warm-up: unknown id is advice-only
            $d = & (Get-Module Troubleshoot) { param($i) $script:D[$i] } $id
            $c = & $d.Check
            if ($c.Found -notin $true, $false, $null) { $bad += "${id}: Found=$($c.Found)" }
            foreach ($l in 'en', 'mr', 'hi') { if (-not $c.Text.$l) { $bad += "${id}: no $l text" } }
            Write-Host ("      {0,-16} found={1,-5} {2}s  {3}" -f $id, $c.Found, [math]::Round(((Get-Date) - $t0).TotalSeconds, 1), $c.Text.en) -ForegroundColor DarkGray
        } catch { $bad += "${id}: $($_.Exception.Message)" }
    }
    Assert (-not $bad.Count) ($bad -join '; ')
}

Test-Case 'Assistant: finds a real fault, fixes it, confirms it, and skips candidates that are fine' {
    $null = Initialize-PDContext -UsbRoot $fakeUsb
    $probs = Get-PDProblems $DataDir
    # 1. Windows Search stopped -> 'search' is fixed; 'disk-full' (fine on CI) is checked first and skipped
    Set-Service WSearch -StartupType Manual -ErrorAction SilentlyContinue
    Stop-Service WSearch -Force -ErrorAction SilentlyContinue
    $r = Invoke-PDTroubleshoot -Ids @('disk-full', 'search') -Problems $probs
    (Format-PDTroubleshoot $r 'en') | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    Assert ($r.Issue.id -eq 'search' -and $r.Resolved) "search not fixed: $(Format-PDTroubleshoot $r 'en')"
    Assert ((Get-Service WSearch).Status -eq 'Running') 'Search service not running after the fix'
    Assert (@($r.Checked | Where-Object { $_.Id -eq 'disk-full' -and $_.Check.Found -eq $false }).Count -eq 1) 'fine candidate was not checked and skipped'
    # 2. print service stopped
    Stop-Service Spooler -Force
    $r = Invoke-PDTroubleshoot -Ids @('printer') -Problems $probs
    Assert ($r.Resolved -and (Get-Service Spooler).Status -eq 'Running') "printer not fixed: $(Format-PDTroubleshoot $r 'en')"
    # 3. malware-style block of Task Manager
    $pol = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    if (-not (Test-Path $pol)) { New-Item $pol -Force | Out-Null }
    New-ItemProperty -Path $pol -Name DisableTaskMgr -Value 1 -PropertyType DWord -Force | Out-Null
    try {
        $r = Invoke-PDTroubleshoot -Ids @('task-manager') -Problems $probs
        Assert ($r.Resolved -and $null -eq (Get-ItemProperty $pol -Name DisableTaskMgr -ErrorAction SilentlyContinue)) "Task Manager block not removed: $(Format-PDTroubleshoot $r 'en')"
        foreach ($l in 'en', 'mr', 'hi') { Assert (@(Format-PDTroubleshoot $r $l).Count -ge 3) "summary missing in $l" }
    } finally { Remove-ItemProperty -Path $pol -Name DisableTaskMgr -ErrorAction SilentlyContinue }
    # 4. nothing wrong -> clear answer, no changes
    $r = Invoke-PDTroubleshoot -Ids @('disk-full') -Problems $probs
    Assert (-not $r.Issue) 'a healthy PC was "fixed"'
    Assert ((Format-PDTroubleshoot $r 'mr')[0] -match 'सापडली नाही') 'no-problem message missing'
}

Test-Case 'Assistant: understanding falls back to keywords; offline AI request is well formed (mocked)' {
    $probs = Get-PDProblems $DataDir
    $u = Resolve-PDProblemIds -Text 'printer print देत नाही' -Problems $probs -UsbRoot $fakeUsb -Mode 'basic' -Config ([pscustomobject]@{ key = '' })
    Assert ($u.Source -eq 'basic' -and $u.Ids[0] -eq 'printer') "keyword fallback: $($u.Ids -join ',')"
    $u = Resolve-PDProblemIds -Text 'net chalat nahi' -Problems $probs -UsbRoot $fakeUsb -Mode 'offline' -Config ([pscustomobject]@{ key = '' })
    Assert ($u.Ids[0] -eq 'no-internet' -and ($u.Notes -join ' ') -match 'offline AI') 'missing offline AI must fall back with a note'
    $script:lb = $null
    $mock = { param($body) $script:lb = $body; '{"choices":[{"message":{"content":"{\"problem_ids\":[\"wifi\",\"bogus\"],\"understood_en\":\"wifi missing\"}"}}]}' }
    $r = Invoke-PDLocalAIAsk -Text 'वायफाय दिसत नाही' -Problems $probs -Transport $mock
    Assert (($r.ProblemIds -join ',') -eq 'wifi') "local answer: $($r.ProblemIds -join ',')"
    $b = $script:lb | ConvertFrom-Json
    Assert ($b.response_format.type -eq 'json_object' -and $b.messages[1].content -eq 'वायफाय दिसत नाही' -and $b.messages[0].content -match 'no-internet: ') 'local request malformed'
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
    foreach ($f in $s.Findings) { Write-Host ("      [{0}] -{1} {2,-7} {3}" -f $f.Severity, $f.Points, $f.Kind, $f.Title) }
    # the score must be explainable: 100 minus the points shown next to each finding
    $sum = (@($s.Findings) | Measure-Object Points -Sum).Sum
    Assert ($s.Score -eq [math]::Max(5, 100 - $sum)) "score $($s.Score) is not 100 - $sum"
    Assert (-not (@($s.Findings) | Where-Object { $_.Severity -ne 'OK' -and $_.Kind -notin 'auto', 'button', 'restart', 'you', 'hw', 'none' })) 'finding without a fix kind'
    Assert ($s.Reachable -ge $s.Score) 'reachable score below the current score'
    $true
}

Test-Case 'Disk event counting separates Windows disk from others' {
    $c = Get-PDDiskEventCounts -Since (Get-Date).AddDays(-14)
    Assert ($null -ne $c.System -and $null -ne $c.Other) 'counts missing'
    Write-Host "      windows disk: $($c.System) ; other disks: $($c.Other)"
    $true
}

Test-Case 'Driver checks (problems, age, Windows Update) run' {
    $p = @(Get-PDDriverProblems); $a = @(Get-PDDriverAge)
    foreach ($x in $p) { Assert $x.Meaning "no meaning for code $($x.Code)" }
    Write-Host "      problem devices: $($p.Count) ; third-party drivers checked: $($a.Count) ; old: $(@($a | Where-Object Old).Count) ; unsigned: $(@($a | Where-Object Unsigned).Count)"
    $w = Get-PDWindowsUpdateDrivers
    Write-Host "      Windows Update driver offers: $(if ($null -eq $w) { 'not reachable' } else { @($w).Count })"
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

Test-Case 'Setup finds tools the user downloaded by hand' {
    # load only the function definitions from the setup script
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Setup-Sanjeevani.ps1'), [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($fn.Name -in 'Find-ManualItem', 'Get-UsbRelPath', 'Get-7zr', 'Get-7zFull', 'Resolve-Source', 'Save-Url', 'Get-WebText', 'Ok', 'Say', 'Warn') { . ([scriptblock]::Create($fn.Extent.Text)) }
    }
    $usb = Join-Path $env:TEMP ('sjv-man-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $script:UsbRoot = $usb + '\'
    $UsbRoot = $script:UsbRoot
    foreach ($d in 'ISO', 'Tools\Hardware\GPU-Z', 'Installers') { New-Item -ItemType Directory -Path (Join-Path $usb $d) -Force | Out-Null }
    Set-Content (Join-Path $usb 'Tools\Hardware\GPU-Z\GPU-Z.2.60.0.exe') 'x'
    Set-Content (Join-Path $usb 'Installers\SumatraPDF-3.5.2-64-install.exe') 'x'
    Set-Content (Join-Path $usb 'ISO\hdat2_74_cd.iso') 'x'
    $z = Join-Path $env:TEMP 'occt-src'; New-Item -ItemType Directory $z -Force | Out-Null; Set-Content (Join-Path $z 'OCCT.exe') 'x'
    Compress-Archive -Path (Join-Path $z '*') -DestinationPath (Join-Path $usb 'OCCT_14.zip') -Force   # zip left in USB root, not extracted
    $cat = Get-Content (Join-Path $Kit 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $get = { param($id) @($cat.isos) + @($cat.tools) | Where-Object id -eq $id }
    $r1 = Find-ManualItem (& $get 'gpuz') 'tool'
    $r2 = Find-ManualItem (& $get 'sumatra') 'tool'
    $r3 = Find-ManualItem (& $get 'hdat2') 'iso'
    $r4 = Find-ManualItem (& $get 'occt') 'tool'
    $r5 = Find-ManualItem (& $get 'furmark') 'tool'
    # .rar (WinNTSetup ships as .rar): build one with full 7-Zip and let setup unpack it
    $script:Work = Join-Path $env:TEMP 'sjv-work'; $Work = $script:Work; New-Item -ItemType Directory $Work -Force | Out-Null
    $script:UA = 'Mozilla/5.0'; $UA = $script:UA; $script:haveCurl = $true; $haveCurl = $true
    $BrowserUA = 'Mozilla/5.0'
    $sz = Get-7zFull
    $rs = Join-Path $env:TEMP 'wnt-src'; New-Item -ItemType Directory $rs -Force | Out-Null; Set-Content (Join-Path $rs 'WinNTSetup_x64.exe') 'x'
    $null = & $sz a -tzip (Join-Path $usb 'Tools\Hardware\placeholder.zip') (Join-Path $rs '*')
    Remove-Item (Join-Path $usb 'Tools\Hardware\placeholder.zip')
    Write-Host "      7-Zip ready: $sz"
    $r6 = Find-ManualItem (& $get 'winntsetup') 'tool'
    Assert ($null -eq $r6) 'winntsetup should not be found yet'
    Write-Host "      gpuz=$r1 ; sumatra=$r2 ; hdat2=$r3 ; occt=$r4 ; furmark=$r5"
    Assert ($r1 -eq 'Tools\Hardware\GPU-Z\GPU-Z.2.60.0.exe') "gpuz: $r1"
    Assert ($r2 -eq 'Installers\SumatraPDF-3.5.2-64-install.exe') "sumatra: $r2"
    Assert ($r3 -eq 'ISO\hdat2_74_cd.iso') "hdat2: $r3"
    Assert ($r4 -match '^Tools\\Stress\\OCCT\\OCCT\.exe$') "occt (unzipped): $r4"
    Assert ($null -eq $r5) 'furmark should not be found'
    Remove-Item $usb, $z -Recurse -Force
    $true
}

Test-Case 'New USB can be cloned from a ready one (no personal data copied)' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'Setup-Sanjeevani.ps1'), [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($fn.Name -in 'Copy-SanjeevaniContent', 'Test-SanjeevaniSource', 'Get-SourceSizeGB', 'Say') { . ([scriptblock]::Create($fn.Extent.Text)) }
    }
    $src = Join-Path $env:TEMP ('sjv-src-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $dst = Join-Path $env:TEMP ('sjv-dst-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    foreach ($d in 'ISO', 'Tools\Hardware\HWiNFO', 'Installers', 'Sanjeevani\bin', 'Reports\CUSTOMER-PC', 'Rescue\CUSTOMER-PC') { New-Item -ItemType Directory (Join-Path $src $d) -Force | Out-Null }
    Set-Content (Join-Path $src 'ISO\01-hbcd.iso') 'iso'
    Set-Content (Join-Path $src 'Tools\Hardware\HWiNFO\HWiNFO64.exe') 'exe'
    Set-Content (Join-Path $src 'Sanjeevani\installed.json') '{"hbcd":{"url":"manual","path":"ISO\\01-hbcd.iso"}}'
    Set-Content (Join-Path $src 'Reports\CUSTOMER-PC\report.html') 'private'
    Set-Content (Join-Path $src 'Rescue\CUSTOMER-PC\photo.jpg') 'private'
    Assert (Test-SanjeevaniSource $src) 'source not recognised'
    Copy-SanjeevaniContent -From $src -To $dst
    Assert (Test-Path (Join-Path $dst 'ISO\01-hbcd.iso')) 'ISO not copied'
    Assert (Test-Path (Join-Path $dst 'Tools\Hardware\HWiNFO\HWiNFO64.exe')) 'tool not copied'
    Assert (Test-Path (Join-Path $dst 'Sanjeevani\installed.json')) 'installed.json not copied'
    Assert (-not (Test-Path (Join-Path $dst 'Reports'))) 'customer reports must not be copied'
    Assert (-not (Test-Path (Join-Path $dst 'Rescue'))) 'rescued personal files must not be copied'
    Remove-Item $src, $dst -Recurse -Force
    $true
}

Test-Case 'Cleaner removes duplicate driver packs and leftovers, keeps customer data' {
    $dir = Join-Path $env:TEMP ('sjv-clean-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $letter = [char[]](68..90) | ForEach-Object { "$_" } | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -Last 1
    $sd = 'Tools\Drivers\Snappy Driver Installer Origin'
    foreach ($d in 'ISO', 'Sanjeevani', "$sd\drivers", "$sd\update\SDIO_Update\drivers", "$sd\SDIO_Update\drivers", 'Reports\PC1', 'Tools\Hardware\CPU-Z') { New-Item -ItemType Directory (Join-Path $dir $d) -Force | Out-Null }
    $rnd = New-Object Random 7
    function New-Blob([string]$rel, [int]$mb, [int]$seed) { $b = New-Object byte[] ($mb * 1MB); (New-Object Random $seed).NextBytes($b); [IO.File]::WriteAllBytes((Join-Path $dir $rel), $b) }
    New-Blob "$sd\drivers\DP_Sound_26082.7z" 2 1
    New-Blob "$sd\update\SDIO_Update\drivers\DP_Sound_26082.7z" 2 1
    New-Blob "$sd\SDIO_Update\drivers\DP_Sound_26082.7z" 2 1
    New-Blob "$sd\drivers\DP_Sound_25001.7z" 1 2
    New-Blob "$sd\drivers\DP_Video_nVIDIA_Server_26040.7z" 1 10
    New-Blob "$sd\drivers\DP_Video_nVIDIA-NT_26040.7z" 1 11
    New-Blob "$sd\SDIO_x64_R887.exe" 1 3
    New-Blob "$sd\SDIO_x64_R889.exe" 1 4
    New-Blob 'ISO\01-hbcd.iso' 3 5
    New-Blob 'ISO\HBCD_PE_x64.iso' 3 5
    New-Blob 'Reports\PC1\photo.jpg' 3 5
    New-Blob 'Tools\Hardware\CPU-Z\cpuz.exe' 1 6
    New-Blob 'Tools\Hardware\CPU-Z\cpu-z_3.01-en.zip' 1 8
    New-Blob 'ISO\gparted.iso.part' 1 9
    Set-Content (Join-Path $dir 'Sanjeevani\installed.json') ('{"hbcd":{"url":"x","path":"ISO\\01-hbcd.iso"},"sdio":{"url":"x","path":"' + ($sd -replace '\\', '\\') + '\\SDIO_x64_R889.exe"}}')
    & subst.exe "$($letter):" $dir
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Clean-Sanjeevani.ps1') -Usb "$($letter):" -Yes -SlimDrivers | Out-Host
        $u = "$($letter):\"
        Assert (Test-Path "$u$sd\drivers\DP_Sound_26082.7z") 'main driver pack must stay'
        Assert (-not (Test-Path "$u$sd\update\SDIO_Update")) 'update\SDIO_Update copy not removed'
        Assert (-not (Test-Path "$u$sd\SDIO_Update")) 'SDIO_Update copy not removed'
        Assert (-not (Test-Path "$u$sd\drivers\DP_Sound_25001.7z")) 'older pack version not removed'
        Assert (-not (Test-Path "$u$sd\SDIO_x64_R887.exe")) 'older SDIO exe not removed'
        Assert (Test-Path "$u$sd\SDIO_x64_R889.exe") 'current SDIO exe must stay'
        Assert (-not (Test-Path "$u$sd\drivers\DP_Video_nVIDIA_Server_26040.7z")) 'Server pack not removed with -SlimDrivers'
        Assert (Test-Path "$u$sd\drivers\DP_Video_nVIDIA-NT_26040.7z") 'Windows 7/8 pack must stay without -NoWin7Drivers'
        Assert (Test-Path "$u\ISO\01-hbcd.iso") 'registered ISO must stay'
        Assert (-not (Test-Path "$u\ISO\HBCD_PE_x64.iso")) 'duplicate ISO not removed'
        Assert (Test-Path "$u\Reports\PC1\photo.jpg") 'customer data must never be touched'
        Assert (-not (Test-Path "$u\Tools\Hardware\CPU-Z\cpu-z_3.01-en.zip")) 'unpacked archive not removed'
        Assert (Test-Path "$u\Tools\Hardware\CPU-Z\cpuz.exe") 'tool must stay'
        Assert (-not (Test-Path "$u\ISO\gparted.iso.part")) 'partial download not removed'
        Assert (Test-Path "$u\_to_delete\ISO\HBCD_PE_x64.iso") 'removed files must be recoverable in _to_delete'
    } finally {
        & subst.exe "$($letter):" /D
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
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
