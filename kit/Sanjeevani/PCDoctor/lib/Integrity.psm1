# Sanjeevani - USB integrity: notices when a PC's malware changed the Sanjeevani USB, and cleans it.
#
#  * New-SJManifest   (Setup, on your own clean PC)  records size + SHA-256 of every program / script
#                      and the size of every big data file (ISOs, driver packs) in Sanjeevani\integrity.json
#  * Test-SJIntegrity (PC Doctor start, CLEAN, Setup)  finds:
#        changed programs (size; with -Full also SHA-256)  - file-infector viruses
#        new programs / scripts / shortcuts that Setup did not put there
#        autorun.inf, folders hidden by the "shortcut virus" (Hidden+System) and the .lnk files that replace them
#  * Repair-SJIntegrity  moves every suspicious file to <USB>\_to_delete\quarantine (renamed *.quarantine so it
#                      cannot run), un-hides the folders, blocks autorun.inf, and lists the tools Setup must re-download.
# A hardware write-protect switch is the real protection; this catches what gets through when the USB is unlocked.
Set-StrictMode -Off

$script:ExecExt = '\.(exe|dll|sys|scr|com|cpl|ocx|msi|ps1|psm1|cmd|bat|vbs|vbe|js|jse|wsf|wsh|hta|lnk|pif|jar)$'
$script:BigExt = '\.(iso|img|wim|esd|vhd|vhdx|7z|zip|rar)$'
# never scanned: customer data, the quarantine, Windows' own folders, SDIO's download area
$script:Skip = '^(Reports|Rescue|_to_delete|System Volume Information|\$RECYCLE\.BIN)(\\|$)|\\update\\SDIO_Update(\\|$)'
# folders Sanjeevani hides on purpose (Hidden only, never System)
$script:OwnHidden = @('Tools', 'Installers', 'autorun.inf')

function Get-SJRoot([string]$Root) {
    # long path form (C:\Users\RUNNER~1 -> C:\Users\runneradmin) so relative paths are cut correctly
    try { $Root = (Get-Item -LiteralPath $Root -Force -ErrorAction Stop).FullName } catch { }
    return ($Root.TrimEnd('\') + '\')
}

function Test-SJWritable([string]$Root) {
    $Root = Get-SJRoot $Root
    $f = Join-Path $Root ('Sanjeevani\.write-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    try {
        New-Item -ItemType Directory -Path (Split-Path $f) -Force -ErrorAction Stop | Out-Null
        [IO.File]::WriteAllText($f, 'x'); Remove-Item -LiteralPath $f -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-SJFiles([string]$Root) {
    $Root = Get-SJRoot $Root
    $n = $Root.Length
    @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($n)
            if ($rel -imatch $script:Skip) { return }
            if ($rel -imatch '\.part$|\.write-test-') { return }
            [pscustomobject]@{ Rel = $rel; Item = $_ }
        })
}

function Get-SJHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function New-SJManifest {
    param([Parameter(Mandatory)][string]$Root)
    $Root = Get-SJRoot $Root
    $files = [ordered]@{}
    foreach ($f in (Get-SJFiles $Root | Sort-Object Rel)) {
        if ($f.Rel -imatch $script:ExecExt) { $files[$f.Rel] = @{ s = $f.Item.Length; h = (Get-SJHash $f.Item.FullName) } }
        elseif ($f.Rel -imatch $script:BigExt -and $f.Item.Length -ge 50MB) { $files[$f.Rel] = @{ s = $f.Item.Length } }
    }
    $doc = [ordered]@{ created = (Get-Date).ToString('s'); computer = $env:COMPUTERNAME; files = $files }
    $out = Join-Path $Root 'Sanjeevani\integrity.json'
    New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
    ($doc | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath $out -Encoding UTF8
    return $files.Count
}

function Test-SJIntegrity {
    param([Parameter(Mandatory)][string]$Root, [switch]$Full)
    $Root = Get-SJRoot $Root
    $res = [pscustomobject]@{
        Root = $Root; Locked = -not (Test-SJWritable $Root); HasManifest = $false; ManifestDate = $null
        Changed = @(); Missing = @(); NewExec = @(); NewMyTools = @(); Autorun = $false; HiddenFolders = @(); RootLinks = @(); Checked = 0
    }
    $mf = Join-Path $Root 'Sanjeevani\integrity.json'
    $known = @{}
    if (Test-Path -LiteralPath $mf) {
        try {
            $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $m.files.PSObject.Properties) { $known[$p.Name.ToLower()] = $p.Value }
            $res.HasManifest = $true; $res.ManifestDate = $m.created
        } catch { }
    }
    $seen = @{}
    foreach ($f in (Get-SJFiles $Root)) {
        $k = $f.Rel.ToLower(); $seen[$k] = $true
        $isExec = $f.Rel -imatch $script:ExecExt
        if ($known.ContainsKey($k)) {
            $e = $known[$k]; $res.Checked++
            if ([int64]$e.s -ne $f.Item.Length) { $res.Changed += $f.Rel; continue }
            if ($Full -and $e.h -and (Get-SJHash $f.Item.FullName) -ne $e.h) { $res.Changed += $f.Rel }
        } elseif ($isExec) {
            if ($f.Rel -notmatch '\\') { if ($f.Rel -imatch '\.lnk$') { $res.RootLinks += $f.Rel; continue } }
            if (-not $res.HasManifest) {
                # without a record only the classic USB-worm files can be judged
                if ($f.Rel -notmatch '\\' -and $f.Rel -imatch '\.(exe|scr|vbs|vbe|js|jse|wsf|pif|com)$') { $res.NewExec += $f.Rel }
                continue
            }
            # Snappy Driver Installer may update itself (SDIO_x64_R890.exe next to R889)
            if ($f.Rel -imatch '\\Snappy Driver Installer Origin\\SDIO[^\\]*_R\d+\.exe$') { continue }
            # MyTools is where the user adds own apps: ask, do not quarantine silently
            if ($f.Rel -imatch '^MyTools\\') { $res.NewMyTools += $f.Rel; continue }
            $res.NewExec += $f.Rel
        }
    }
    foreach ($k in $known.Keys) { if (-not $seen.ContainsKey($k)) { $res.Missing += $k } }
    $ar = Join-Path $Root 'autorun.inf'
    if (Test-Path -LiteralPath $ar -PathType Leaf) { $res.Autorun = $true }
    foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name -in 'System Volume Information', '$RECYCLE.BIN') { continue }
        $a = $d.Attributes
        $sys = ($a -band [IO.FileAttributes]::System) -and ($a -band [IO.FileAttributes]::Hidden)
        if ($sys -and $d.Name -notin $script:OwnHidden) { $res.HiddenFolders += $d.Name }
    }
    return $res
}

function Get-SJIssueCount($R) {
    return (@($R.Changed).Count + @($R.NewExec).Count + @($R.HiddenFolders).Count + @($R.RootLinks).Count + [int][bool]$R.Autorun)
}

# Records programs the user added to MyTools (after they confirmed them) so they are not reported again.
function Add-SJTrusted {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string[]]$Rel)
    $Root = Get-SJRoot $Root
    $mf = Join-Path $Root 'Sanjeevani\integrity.json'
    if (-not (Test-Path -LiteralPath $mf)) { return 0 }
    $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
    $files = [ordered]@{}
    foreach ($p in $m.files.PSObject.Properties) { $files[$p.Name] = $p.Value }
    $n = 0
    foreach ($r in $Rel) {
        $full = Join-Path $Root $r
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $files[$r] = @{ s = (Get-Item -LiteralPath $full -Force).Length; h = (Get-SJHash $full) }; $n++
    }
    $doc = [ordered]@{ created = $m.created; computer = $m.computer; files = $files }
    ($doc | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath $mf -Encoding UTF8
    return $n
}

# Plain-language summary lines (Marathi / English)
function Format-SJResult($R, [string]$Lang = 'mr') {
    $mr = $Lang -ne 'en'
    $out = @()
    if ($R.Locked) { $out += $(if ($mr) { '🔒 Pendrive locked आहे - virus त्यावर काहीही लिहू शकत नाही.' } else { '🔒 The USB is write-protected - malware cannot write to it.' }) }
    else { $out += $(if ($mr) { '🔓 Pendrive unlocked आहे. Virus असलेल्या PC वर lock switch लावूनच वापरा.' } else { '🔓 The USB is not write-protected. Lock it before using it on a PC that may have malware.' }) }
    if (-not $R.HasManifest) { $out += $(if ($mr) { 'नोंद (integrity.json) नाही - तुमच्या PC वर UPDATE.cmd चालवा म्हणजे पूर्ण तपासणी होईल.' } else { 'No record (integrity.json) - run UPDATE.cmd on your own PC to enable the full check.' }) }
    foreach ($x in $R.Changed) { $out += $(if ($mr) { "✖ बदललेला program (virus ची शक्यता): $x" } else { "✖ Program changed (possible virus): $x" }) }
    foreach ($x in $R.NewExec) { $out += $(if ($mr) { "✖ अनोळखी नवीन program / script: $x" } else { "✖ Unknown new program / script: $x" }) }
    if ($R.Autorun) { $out += $(if ($mr) { '✖ autorun.inf - USB virus पसरवण्याची फाईल' } else { '✖ autorun.inf - a file USB worms use to spread' }) }
    foreach ($x in $R.HiddenFolders) { $out += $(if ($mr) { "✖ Virus ने लपवलेला folder: $x" } else { "✖ Folder hidden by a virus: $x" }) }
    foreach ($x in $R.NewMyTools) { $out += $(if ($mr) { "• MyTools मध्ये नवीन program: $x - तुम्ही स्वतः टाकला असल्यास नोंदवा, ओळखत नसाल तर quarantine करा." } else { "• New program in MyTools: $x - record it if you added it yourself, quarantine it if you do not know it." }) }
    foreach ($x in $R.RootLinks) { $out += $(if ($mr) { "✖ संशयास्पद shortcut (shortcut virus): $x" } else { "✖ Suspicious shortcut (shortcut virus): $x" }) }
    if (@($R.Missing).Count) { $out += $(if ($mr) { "• $(@($R.Missing).Count) फाईली नाहीत (delete / CLEAN केल्या असतील) - UPDATE.cmd ने परत येतील." } else { "• $(@($R.Missing).Count) files are missing (deleted / cleaned?) - UPDATE.cmd brings them back." }) }
    if (-not (Get-SJIssueCount $R) -and -not @($R.NewMyTools).Count) { $out += $(if ($mr) { "✔ Pendrive स्वच्छ आहे ($($R.Checked) फाईली तपासल्या)." } else { "✔ The USB is clean ($($R.Checked) files checked)." }) }
    return $out
}

function Repair-SJIntegrity {
    param([Parameter(Mandatory)]$R, [switch]$IncludeMyTools)
    $Root = $R.Root
    $done = [pscustomobject]@{ Quarantined = @(); Unhidden = @(); AutorunBlocked = $false; Redownload = @(); Error = $null }
    if ($R.Locked) { $done.Error = 'locked'; return $done }
    $q = Join-Path $Root '_to_delete\quarantine'
    $move = {
        param($rel)
        $src = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $src)) { return }
        $dst = Join-Path $q ($rel + '.quarantine')
        New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
        if (Test-Path -LiteralPath $dst) { $dst = $dst + '.' + (Get-Date -Format 'HHmmss') }
        try { [IO.File]::SetAttributes($src, [IO.FileAttributes]::Normal) } catch { }
        Move-Item -LiteralPath $src -Destination $dst -Force
        $done.Quarantined += $rel
    }
    $list = @($R.Changed) + @($R.NewExec) + @($R.RootLinks)
    if ($IncludeMyTools) { $list += @($R.NewMyTools) }
    foreach ($x in $list) { try { & $move $x } catch { } }
    $done.Redownload = @($R.Changed)
    # autorun.inf: quarantine the file, then a protected folder of that name so no file can be created again
    $ar = Join-Path $Root 'autorun.inf'
    try {
        if (Test-Path -LiteralPath $ar -PathType Leaf) { & $move 'autorun.inf' }
        if (-not (Test-Path -LiteralPath $ar)) {
            $d = New-Item -ItemType Directory -Path $ar -Force
            New-Item -ItemType Directory -Path (Join-Path $ar 'Sanjeevani-protect') -Force | Out-Null
            $d.Attributes = [IO.FileAttributes]'Directory, Hidden, ReadOnly'
        }
        $done.AutorunBlocked = $true
    } catch { }
    foreach ($n in $R.HiddenFolders) {
        try { $d = Get-Item -LiteralPath (Join-Path $Root $n) -Force; $d.Attributes = [IO.FileAttributes]::Directory; $done.Unhidden += $n } catch { }
    }
    return $done
}

# After files were removed on purpose (CLEAN), drop them from the record - never re-records changed files.
function Update-SJManifest {
    param([Parameter(Mandatory)][string]$Root)
    $Root = Get-SJRoot $Root
    $mf = Join-Path $Root 'Sanjeevani\integrity.json'
    if (-not (Test-Path -LiteralPath $mf)) { return 0 }
    $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
    $keep = [ordered]@{}; $dropped = 0
    foreach ($p in $m.files.PSObject.Properties) {
        if (Test-Path -LiteralPath (Join-Path $Root $p.Name)) { $keep[$p.Name] = $p.Value } else { $dropped++ }
    }
    $doc = [ordered]@{ created = $m.created; computer = $m.computer; files = $keep }
    ($doc | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath $mf -Encoding UTF8
    return $dropped
}

Export-ModuleMember -Function Test-SJWritable, New-SJManifest, Update-SJManifest, Add-SJTrusted, Test-SJIntegrity, Repair-SJIntegrity, Format-SJResult, Get-SJIssueCount
