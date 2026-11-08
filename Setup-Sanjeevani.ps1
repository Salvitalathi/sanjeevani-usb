#Requires -Version 5.1
<#
.SYNOPSIS
    Builds / updates the Sanjeevani Rescue USB.
.DESCRIPTION
    1. Installs (or updates) Ventoy on the chosen USB disk.
    2. Copies the Sanjeevani kit (boot theme, PC Doctor, docs).
    3. Downloads the latest versions of all free rescue ISOs and portable tools.
    4. Writes ventoy.json (menu names, icons, tips, theme) for whatever was downloaded.
    Run again any time to update everything - only changed files are downloaded.
.EXAMPLE
    .\Setup-Sanjeevani.ps1                       # interactive
    .\Setup-Sanjeevani.ps1 -UpdateOnly -Usb E:   # just refresh tools on an existing Sanjeevani USB
#>
param(
    [string]$Usb,                 # drive letter of an existing Ventoy data partition, e.g. E:
    [switch]$UpdateOnly,          # skip Ventoy install, just copy kit + download
    [switch]$GPT,                 # install Ventoy with GPT instead of MBR
    [switch]$WithWindows,         # also download the Windows 11 ISO (~7.5 GB)
    [switch]$WithMint,            # also download Linux Mint XFCE (~3 GB)
    [switch]$WithDrivers,         # also download ALL Snappy Driver Installer driver packs (~70 GB, offline drivers)
    [switch]$SkipDownloads,
    [string[]]$Only,              # only these ids, e.g. -Only hbcd,cpuz
    [switch]$ResolveOnly,         # CI / check: only find the latest download link of every item, download nothing
    [string]$CopyFrom             # make a new USB from an existing Sanjeevani USB (e.g. E:) or a folder copy of one - no downloads
)

$ErrorActionPreference = 'Stop'
# any unexpected error: show it and keep the (elevated) window open instead of closing silently
trap {
    Write-Host ''
    Write-Host ("    [XX]  Setup stopped: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("          at line " + $_.InvocationInfo.ScriptLineNumber + ": " + $_.InvocationInfo.Line.Trim()) -ForegroundColor DarkGray
    Write-Host '          Take a photo / screenshot of this and report it on GitHub (Issues).' -ForegroundColor Yellow
    if (-not $ResolveOnly) { Read-Host 'Press Enter to close' }
    exit 1
}
Set-StrictMode -Off
if ($Only -and $Only.Count -eq 1 -and $Only[0] -match ',') { $Only = $Only[0].Split(',') | ForEach-Object { $_.Trim() } }
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SanjeevaniSetup/1.0'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Step([string]$m) { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host "    [OK]  $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "    [!!]  $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "    [XX]  $m" -ForegroundColor Red }

# ------------------------------------------------------------------ admin
$admin = $ResolveOnly -or ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v) { $argList += "-$k" } } elseif ($v -is [array]) { $argList += "-$k"; $argList += ($v -join ',') } else { $argList += "-$k"; $argList += "`"$v`"" }
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}
$Host.UI.RawUI.WindowTitle = 'Sanjeevani Rescue USB - Setup'

Clear-Host
Say '  ================================================================' Cyan
Say '     SANJEEVANI RESCUE USB  -  Setup / Update' Cyan
Say '     Free & legal PC repair toolkit  (Ventoy based)' DarkCyan
Say '  ================================================================' Cyan

# ------------------------------------------------------------------ where is the kit?
$ScriptDir = $PSScriptRoot
$KitDir = Join-Path $ScriptDir 'kit'
$RunningFromUsb = $false
if (-not (Test-Path (Join-Path $KitDir 'Sanjeevani\tools.json'))) {
    # running from <USB>\Sanjeevani\Setup\ : the USB itself is the kit
    $cand = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
    if (Test-Path (Join-Path $cand 'Sanjeevani\tools.json')) { $KitDir = $cand; $RunningFromUsb = $true }
    else { Fail 'Kit files not found next to this script.'; Read-Host 'Press Enter'; exit 1 }
}
$Work = Join-Path $env:TEMP 'SanjeevaniSetup'
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$haveCurl = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)

# ------------------------------------------------------------------ web helpers
function Get-WebText([string]$Url, [hashtable]$Headers = @{}) {
    $h = @{ 'User-Agent' = $UA } + $Headers
    return (Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $h -TimeoutSec 60).Content
}

$BrowserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

function Save-Url([string]$Url, [string]$Dest, [string]$Referer) {
    $part = "$Dest.part"
    New-Item -ItemType Directory -Path (Split-Path $Dest) -Force | Out-Null
    # SourceForge serves an HTML page to browsers but a direct redirect to download tools
    $agent = if ($Url -match 'sourceforge\.net') { 'Wget/1.21.4' } else { $UA }
    $done = $false
    $last = 0
    if ($haveCurl) {
        # resume after dropped / stalled connections instead of starting over
        # (--speed-limit/--speed-time abort a transfer that is stuck below 1 KB/s for 60 s, then we resume it)
        for ($i = 1; $i -le 8; $i++) {
            & curl.exe -L --fail --connect-timeout 30 --speed-limit 1024 --speed-time 60 -A $agent -C - -o $part $Url
            $last = $LASTEXITCODE
            if ($last -eq 0) { $done = $true; break }
            if ($last -eq 33) { Remove-Item $part -Force -ErrorAction SilentlyContinue; continue }   # server can't resume: start over
            if ($last -eq 22) { break }                                                             # HTTP error (403/404): resuming won't help
            Warn "     connection dropped (curl $last) - resuming from where it stopped ($i/8) ..."
            Start-Sleep -Seconds ([math]::Min(30, 5 * $i))
        }
        if (-not $done -and $last -eq 22) {
            # some sites (e.g. hirensbootcd.org) refuse non-browser downloads (403): retry like a browser
            Warn "     retrying as a browser ..."
            $ref = if ($Referer) { $Referer } else { $Url }
            for ($i = 1; $i -le 4; $i++) {
                & curl.exe -L --fail --connect-timeout 30 --speed-limit 1024 --speed-time 60 -A $BrowserUA -e $ref -H 'Accept: */*' -H 'Accept-Language: en-IN,en;q=0.9' -C - -o $part $Url
                $last = $LASTEXITCODE
                if ($last -eq 0) { $done = $true; break }
                if ($last -eq 22) { break }
                Start-Sleep -Seconds 5
            }
        }
        if (-not $done -and $last -ne 22 -and (Test-Path $part)) {
            # still failing after many resumes: keep the partial file so the next UPDATE.cmd continues it
            throw "connection keeps dropping (curl $last) - run UPDATE.cmd again later, it will continue from $([math]::Round((Get-Item $part).Length / 1MB)) MB"
        }
    }
    if (-not $done) {
        # last resort: Windows' own download service (BITS), different network stack
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        try {
            Warn '     trying Windows BITS download ...'
            Start-BitsTransfer -Source $Url -Destination $part -DisplayName 'Sanjeevani download' -ErrorAction Stop
        } catch {
            try { Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing -UserAgent $BrowserUA -Headers @{ Referer = $(if ($Referer) { $Referer } else { $Url }) } }
            catch { Remove-Item $part -Force -ErrorAction SilentlyContinue; throw ('download refused by the website - download it in a browser from ' + $(if ($Referer) { $Referer } else { $Url })) }
        }
    }
    if ((Get-Item $part).Length -lt 1024) { $t = Get-Content $part -Raw -ErrorAction SilentlyContinue; Remove-Item $part -Force; throw "file too small - not a real download ($t)" }
    $fs = [IO.File]::OpenRead($part); $head = New-Object byte[] 64; [void]$fs.Read($head, 0, 64); $fs.Close()
    $txt = [Text.Encoding]::ASCII.GetString($head).TrimStart()
    if ($txt -match '^(?i)<(!DOCTYPE|html)') { Remove-Item $part -Force; throw 'got a web page instead of the file (site changed?)' }
    Move-Item -LiteralPath $part -Destination $Dest -Force
}

# 7-Zip's tiny console extractor, fetched once, for tools shipped as .7z
function Get-7zr {
    $x = Join-Path $Work '7zr.exe'
    if (-not (Test-Path $x)) {
        $r = Resolve-Source ([pscustomobject]@{ source = [pscustomobject]@{ kind = 'github'; repo = 'ip7z/7zip'; asset = '^7zr\.exe$' } })
        Save-Url $r.Url $x
    }
    return $x
}

# Full 7-Zip (7z.exe + 7z.dll, opens .rar too): unpacked from the official 7-Zip installer with 7zr.exe
function Get-7zFull {
    $dir = Join-Path $Work '7zfull'
    $x = Join-Path $dir '7z.exe'
    foreach ($pf in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") { if (Test-Path $pf) { return $pf } }   # 7-Zip already installed
    if (-not (Test-Path $x)) {
        $inst = Get-ChildItem (Join-Path $UsbRoot 'Installers') -Filter '7z*-x64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($inst) { $instPath = $inst.FullName }
        else {
            $r = Resolve-Source ([pscustomobject]@{ source = [pscustomobject]@{ kind = 'github'; repo = 'ip7z/7zip'; asset = '7z\d+-x64\.exe$' } })
            $instPath = Join-Path $Work $r.Name
            if (-not (Test-Path $instPath)) { Save-Url $r.Url $instPath }
        }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        & (Get-7zr) x $instPath ('-o' + $dir) -y | Out-Null
        if (-not (Test-Path $x)) { throw 'could not prepare 7-Zip for .rar files' }
    }
    return $x
}

function Resolve-Source($e) {
    $s = $e.source
    switch ($s.kind) {
        'url' {
            $leaf = if ($e.file) { $e.file } else { [IO.Path]::GetFileName(([Uri]$s.url).AbsolutePath) }
            return @{ Url = $s.url; Name = $leaf }
        }
        'github' {
            try {
                $j = Get-WebText "https://api.github.com/repos/$($s.repo)/releases/latest" @{ Accept = 'application/vnd.github+json' } | ConvertFrom-Json
                $a = $j.assets | Where-Object { $_.name -match $s.asset } | Select-Object -First 1
                if (-not $a) { throw "no asset matching '$($s.asset)' in $($s.repo) $($j.tag_name)" }
                return @{ Url = $a.browser_download_url; Name = $a.name; Version = $j.tag_name }
            } catch {
                if ($_.Exception.Message -match '^no asset') { throw }
                # GitHub API refused (60 requests/hour per IP, often hit on shared Indian ISP addresses): read the web page instead
                $tag = (& curl.exe -sS -o NUL -w '%{redirect_url}' "https://github.com/$($s.repo)/releases/latest") -replace '.*/tag/', ''
                if (-not $tag) { throw }
                $html = Get-WebText "https://github.com/$($s.repo)/releases/expanded_assets/$tag"
                $names = [regex]::Matches($html, 'href="(/[^"]+/releases/download/[^"]+)"') | ForEach-Object { $_.Groups[1].Value }
                $hit = $names | Where-Object { [Uri]::UnescapeDataString(($_ -split '/')[-1]) -match $s.asset } | Select-Object -First 1
                if (-not $hit) { throw "no asset matching '$($s.asset)' in $($s.repo) $tag" }
                return @{ Url = "https://github.com$hit"; Name = [Uri]::UnescapeDataString(($hit -split '/')[-1]); Version = $tag }
            }
        }
        'sourceforge' {
            $rss = [xml](Get-WebText "https://sourceforge.net/projects/$($s.project)/rss")
            foreach ($it in $rss.rss.channel.item) {
                $link = [string]$it.link                      # .../files/<path>/<name>/download
                $leaf = [Uri]::UnescapeDataString(($link -replace '/download$', '').Split('/')[-1])
                if ($s.pathMatch -and $link -notmatch [regex]::Escape($s.pathMatch)) { continue }   # e.g. stable, not testing
                if ($leaf -match $s.file) { return @{ Url = $link; Name = $leaf } }
            }
            throw "no file matching '$($s.file)' in sourceforge/$($s.project)"
        }
        'scrape' {
            $html = Get-WebText $s.page
            $m = [regex]::Match($html, $s.regex)
            if (-not $m.Success) { throw "link not found on $($s.page)" }
            $href = [Net.WebUtility]::HtmlDecode($m.Value)
            if ($s.template) { $href = $s.template.Replace('{1}', $m.Groups[1].Value) }
            $abs = (New-Object Uri ([Uri]$s.page), $href).AbsoluteUri
            return @{ Url = $abs; Name = [IO.Path]::GetFileName(([Uri]$abs).AbsolutePath) }
        }
        'dirlatest' {
            # try the main listing first, then the official mirrors (some networks cannot reach one of them)
            $html = $null; $base = $null; $why = $null
            foreach ($pg in @($s.page) + @($s.pageMirrors | Where-Object { $_ })) {
                try { $html = Get-WebText $pg; $base = $pg; break } catch { $why = $_ }
            }
            if (-not $base) { throw $why }
            $vers = [regex]::Matches($html, $s.dirRegex) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]($(if ($_ -match '\.') { $_ } else { "$_.0" })) } -Descending
            if (-not $vers) { throw "no versions found on $base" }
            $v = @($vers)[0]
            $f = $s.file.Replace('{v}', $v)
            return @{ Url = ($base.TrimEnd('/') + "/$v/$f"); Name = ($f -split '/')[-1]; Version = $v }
        }
        'fido' {
            $fido = Join-Path $Work 'Fido.ps1'
            Save-Url 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' $fido
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fido -Win $s.win -Rel Latest -Ed Pro -Lang English -Arch x64 -GetUrl 2>&1
            $url = @($out | ForEach-Object { "$_" } | Where-Object { $_ -match '^https://' })[-1]
            if (-not $url) {
                $msg = ($out | Select-Object -Last 2) -join ' '
                if ($msg -match 'Sentinel|rejected|banned|715-123130') {
                    throw ('Microsoft is temporarily refusing downloads from this internet connection (too many requests). ' +
                           'Run SETUP again tomorrow, or download the ISO in a browser from https://www.microsoft.com/software-download/windows11 ' +
                           'and copy it into the ISO folder of the USB - Setup will pick it up.')
                }
                throw ("Microsoft did not give a link: " + $msg)
            }
            return @{ Url = $url; Name = "Win$($s.win).iso" }
        }
        default { return $null }
    }
}

# ------------------------------------------------------------------ link check (CI)
if ($ResolveOnly) {
    $cat = Get-Content (Join-Path $KitDir 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $res = @()
    foreach ($e in @($cat.isos) + @($cat.tools)) {
        if ($Only -and $Only -notcontains $e.id) { continue }
        $row = [ordered]@{ id = $e.id; kind = $e.source.kind; status = ''; url = ''; detail = '' }
        if ($e.source.kind -eq 'manual') { $row.status = $(if ($e.optional) { 'optional' } else { 'manual' }) }
        else {
            try {
                $r = Resolve-Source $e
                $row.url = $r.Url
                # fetch the first KB to prove the link really serves a file
                $probe = Join-Path $Work ('probe_' + $e.id)
                $agent = if ($r.Url -match 'sourceforge\.net') { 'Wget/1.21.4' } else { $UA }
                # -s without -S: no stderr text (in Windows PowerShell 5.1 any stderr line would abort here with ErrorAction Stop)
                & curl.exe -s -L --fail --max-time 60 -A $agent -r 0-1023 -o $probe $r.Url | Out-Null
                $code0 = $LASTEXITCODE
                if ($code0 -ne 0) {
                    foreach ($m in @($e.source.mirrors)) {
                        if (-not $m) { continue }
                        & curl.exe -s -L --fail --max-time 60 -A $UA -r 0-1023 -o $probe $m | Out-Null
                        if ($LASTEXITCODE -eq 0) { $code0 = 0; $r.Name = "$($r.Name) (via mirror $(([Uri]$m).Host))"; break }
                    }
                }
                if ($code0 -ne 0) { throw "curl $code0" }
                $head = [IO.File]::ReadAllBytes($probe); Remove-Item $probe -Force
                $txt = [Text.Encoding]::ASCII.GetString($head, 0, [math]::Min(64, $head.Length)).TrimStart()
                if ($txt -match '^(?i)<(!DOCTYPE|html)') { throw 'web page instead of file' }
                $row.status = 'ok'; $row.detail = $r.Name
                # report dead mirrors too, so a broken fallback is noticed before it is needed
                $dead = @()
                foreach ($m in @($e.source.mirrors | Where-Object { $_ })) {
                    & curl.exe -s -L --fail --max-time 60 -A $UA -r 0-1023 -o NUL $m | Out-Null
                    if ($LASTEXITCODE -ne 0) { $dead += ([Uri]$m).Host }
                }
                foreach ($m in @($e.source.pageMirrors | Where-Object { $_ })) {
                    & curl.exe -s -L --fail --max-time 60 -A $UA -o NUL $m | Out-Null
                    if ($LASTEXITCODE -ne 0) { $dead += ([Uri]$m).Host }
                }
                if ($dead) { $row.detail += "  [mirror not reachable: $($dead -join ', ')]" }
            } catch {
                $row.status = 'FAIL'; $row.detail = $_.Exception.Message
                # Kaspersky refuses US addresses (GitHub runners); it works from India
                if ($row.url -match 'kaspersky' -and $row.detail -match '403|curl 22') { $row.status = 'geo'; $row.detail = 'blocked in the US only (CI runner) - fine in India' }
            }
        }
        $res += [pscustomobject]$row
        Write-Host ("{0,-6} {1,-16} {2}" -f $row.status, $row.id, $(if ($row.status -eq 'ok') { $row.detail } else { $row.detail }))
    }
    $res | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Work 'link-report.json') -Encoding UTF8
    $bad = @($res | Where-Object { $_.status -eq 'FAIL' })
    Write-Host ("`n{0} ok, {1} failed, {2} manual. Report: {3}" -f @($res | Where-Object status -eq 'ok').Count, $bad.Count, @($res | Where-Object status -eq 'manual').Count, (Join-Path $Work 'link-report.json'))
    exit $bad.Count
}

# A ready Sanjeevani USB (or a folder copy of one) can be cloned instead of downloading everything again.
# Personal data folders (Reports, Rescue) are never copied.
function Test-SanjeevaniSource([string]$Path) {
    return ($Path -and (Test-Path -LiteralPath (Join-Path $Path 'Sanjeevani\installed.json')) -and (Test-Path -LiteralPath (Join-Path $Path 'ISO')))
}

function Get-SourceSizeGB([string]$From) {
    $sum = 0
    foreach ($d in 'ISO', 'Tools', 'Installers') { $p = Join-Path $From $d; if (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum += $_.Length } } }
    return [math]::Round($sum / 1GB, 1)
}

function Copy-SanjeevaniContent([string]$From, [string]$To) {
    $From = $From.TrimEnd('\'); $To = $To.TrimEnd('\')
    foreach ($d in 'ISO', 'Tools', 'Installers', 'Sanjeevani\bin') {
        $src = Join-Path $From $d
        if (-not (Test-Path -LiteralPath $src)) { continue }
        Say "    copying $d ..." DarkGray
        & robocopy.exe $src (Join-Path $To $d) /E /R:1 /W:1 /MT:8 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "copy of $d failed (robocopy $LASTEXITCODE)" }
    }
    $inst = Join-Path $From 'Sanjeevani\installed.json'
    if (Test-Path -LiteralPath $inst) {
        New-Item -ItemType Directory -Path (Join-Path $To 'Sanjeevani') -Force | Out-Null
        Copy-Item -LiteralPath $inst (Join-Path $To 'Sanjeevani\installed.json') -Force
    }
}

# ------------------------------------------------------------------ choose USB
function Get-VentoyVolume([int]$DiskNumber) {
    Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | ForEach-Object {
        $v = $_ | Get-Volume -ErrorAction SilentlyContinue
        if ($v -and $v.FileSystemLabel -eq 'Ventoy') { [pscustomobject]@{ Partition = $_; Volume = $v } }
    } | Select-Object -First 1
}

function Install-Ventoy([int]$DiskNumber, [bool]$Update) {
    Step 'Downloading latest Ventoy'
    $r = Resolve-Source ([pscustomobject]@{ source = [pscustomobject]@{ kind = 'github'; repo = 'ventoy/Ventoy'; asset = 'windows\.zip$' } })
    $zip = Join-Path $Work $r.Name
    if (-not (Test-Path $zip)) { Save-Url $r.Url $zip }
    $dir = Join-Path $Work 'ventoy'
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem $dir -Recurse -Filter 'Ventoy2Disk.exe' | Where-Object { $_.Directory.Name -notmatch 'altexe' } | Select-Object -First 1
    if (-not $exe) { throw 'Ventoy2Disk.exe not found in the Ventoy package' }
    Ok "Ventoy $($r.Version)"
    $cwd = $exe.DirectoryName
    Remove-Item (Join-Path $cwd 'cli_*.txt') -Force -ErrorAction SilentlyContinue
    $cmd = if ($Update) { '/U' } else { '/I' }
    $args2 = "VTOYCLI $cmd /PhyDrive:$DiskNumber"
    if (-not $Update -and $GPT) { $args2 += ' /GPT' }
    Step ("{0} Ventoy on disk {1} ..." -f $(if ($Update) { 'Updating' } else { 'Installing' }), $DiskNumber)
    Start-Process -FilePath $exe.FullName -ArgumentList $args2 -WorkingDirectory $cwd -Wait
    $done = Join-Path $cwd 'cli_done.txt'
    for ($i = 0; $i -lt 60 -and -not (Test-Path $done); $i++) { Start-Sleep 1 }
    $res = if (Test-Path $done) { (Get-Content $done -Raw).Trim() } else { '?' }
    if ($res -ne '0') {
        Fail 'Ventoy reported an error. Log:'
        Get-Content (Join-Path $cwd 'cli_log.txt') -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Say "      $_" DarkGray }
        throw 'Ventoy install/update failed'
    }
    Ok 'Ventoy done'
}

$UsbRoot = $null
if ($Usb) {
    $UsbRoot = $Usb.TrimEnd('\').TrimEnd(':') + ':\'
    if (-not (Test-Path $UsbRoot)) { Fail "$Usb not found"; exit 1 }
    $UpdateOnly = $true
} elseif ($RunningFromUsb) {
    $UsbRoot = $KitDir.TrimEnd('\') + '\'
    $UpdateOnly = $true
    Ok "Updating this Sanjeevani USB: $UsbRoot"
} else {
    Step 'USB disks connected to this PC'
    $disks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' } | Sort-Object Number)
    if (-not $disks.Count) { Fail 'No USB disk found. Insert the pendrive and run again.'; Read-Host 'Press Enter'; exit 1 }
    foreach ($d in $disks) {
        $vt = Get-VentoyVolume $d.Number
        $tag = if ($vt) { "  [Ventoy already installed - $($vt.Volume.DriveLetter):]" } else { '' }
        Say ("    Disk {0}:  {1,-34} {2,8:N1} GB{3}" -f $d.Number, $d.FriendlyName, ($d.Size / 1GB), $tag) White
    }
    $n = Read-Host "`n    Type the Disk number of your pendrive"
    $disk = $disks | Where-Object { [string]$_.Number -eq $n.Trim() }
    if (-not $disk) { Fail 'Invalid disk number.'; Read-Host 'Press Enter'; exit 1 }
    if ($disk.Size -lt 30GB) { Warn 'This pendrive is smaller than 32 GB - not everything will fit. 64-128 GB recommended.' }
    # another Sanjeevani USB plugged in? offer to copy from it instead of downloading
    if (-not $CopyFrom) {
        foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) {
            $root = "$($v.DriveLetter):\"
            if (-not (Test-SanjeevaniSource $root)) { continue }
            $dn = $null; try { $dn = (Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop).DiskNumber } catch { }
            if ($dn -eq $disk.Number) { continue }
            $c = Read-Host ("    {0} is a ready Sanjeevani USB ({1} GB of tools). Copy everything from it instead of downloading? Y/N" -f $root, (Get-SourceSizeGB $root))
            if ($c -match '^[Yy]') { $CopyFrom = $root }
            break
        }
    }
    if ($CopyFrom) {
        if (-not (Test-SanjeevaniSource $CopyFrom)) { Fail "$CopyFrom is not a Sanjeevani USB / copy (Sanjeevani\installed.json missing)."; exit 1 }
        $srcDisk = $null; try { $srcDisk = (Get-Partition -DriveLetter $CopyFrom.Substring(0, 1) -ErrorAction Stop).DiskNumber } catch { }
        if ($srcDisk -eq $disk.Number) { Fail 'The source and the new pendrive are the same disk. Choose the NEW pendrive.'; exit 1 }
        $needGB = Get-SourceSizeGB $CopyFrom
        if ($disk.Size / 1GB -lt $needGB + 2) { Fail ("The new pendrive is too small: {0} GB of tools to copy." -f $needGB); exit 1 }
    }
    $vt = Get-VentoyVolume $disk.Number
    $doInstall = $true; $isUpdate = $false
    if ($vt) {
        $c = Read-Host "    Ventoy is already on this disk. [U]pdate (keeps files) or [R]einstall (ERASES everything)?  U/R"
        if ($c -match '^[Uu]') { $isUpdate = $true }
    }
    if (-not $isUpdate) {
        Say ''
        Say "    !!! ALL DATA on  Disk $($disk.Number) - $($disk.FriendlyName) ($([math]::Round($disk.Size/1GB,1)) GB)  WILL BE ERASED !!!" Red
        $c = Read-Host '    Type ERASE to continue'
        if ($c -cne 'ERASE') { Say 'Cancelled.'; exit 0 }
    }
    # the disk number can change if something is plugged/unplugged meanwhile: verify identity again
    $now = Get-Disk -Number $disk.Number -ErrorAction SilentlyContinue
    if (-not $now -or $now.UniqueId -ne $disk.UniqueId -or $now.SerialNumber -ne $disk.SerialNumber -or $now.Size -ne $disk.Size -or
        [string]$now.BusType -ne 'USB' -or $now.IsBoot -or $now.IsSystem) {
        Fail 'The selected disk changed or is not a removable USB disk. Nothing was erased. Run setup again.'
        Read-Host 'Press Enter'; exit 1
    }
    if ($doInstall) { Install-Ventoy -DiskNumber $disk.Number -Update $isUpdate }
    Step 'Waiting for the Ventoy partition'
    for ($i = 0; $i -lt 30; $i++) {
        Update-HostStorageCache -ErrorAction SilentlyContinue
        $vt = Get-VentoyVolume $disk.Number
        if ($vt -and $vt.Volume.DriveLetter) { break }
        if ($vt -and -not $vt.Volume.DriveLetter) { $vt.Partition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue }
        Start-Sleep 2
    }
    if (-not $vt -or -not $vt.Volume.DriveLetter) { Fail 'Ventoy partition did not appear. Re-plug the pendrive and run with -Usb X:'; exit 1 }
    $UsbRoot = "$($vt.Volume.DriveLetter):\"
    Ok "USB data partition: $UsbRoot"
}

# ------------------------------------------------------------------ copy kit
if (-not $RunningFromUsb) {
    Step 'Copying Sanjeevani kit (theme, PC Doctor, docs)'
    & robocopy.exe $KitDir.TrimEnd('\') $UsbRoot.TrimEnd('\') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copy failed (robocopy $LASTEXITCODE)" }
    $setupDir = Join-Path $UsbRoot 'Sanjeevani\Setup'
    New-Item -ItemType Directory -Path $setupDir -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $setupDir -Force
    $cmd = Join-Path $ScriptDir 'SETUP.cmd'
    if (Test-Path $cmd) { Copy-Item $cmd (Join-Path $setupDir 'UPDATE.cmd') -Force }
    Ok 'Kit copied'
}
# generic Ventoy icons hid the per-tool icons (GRUB uses the first class that has an icon); remove them from older USBs
foreach ($ic in 'vtoyiso', 'vtoyimg', 'vtoyefi', 'vtoywim', 'vtoyvhd') {
    Remove-Item -LiteralPath (Join-Path $UsbRoot "ventoy\theme\sanjeevani\icons\$ic.png") -Force -ErrorAction SilentlyContinue
}
foreach ($d in 'ISO', 'Tools', 'Installers', 'Reports') { New-Item -ItemType Directory -Path (Join-Path $UsbRoot $d) -Force | Out-Null }

if ($CopyFrom) {
    Step ("Copying all tools from {0} ({1} GB) - no internet needed" -f $CopyFrom, (Get-SourceSizeGB $CopyFrom))
    Copy-SanjeevaniContent -From $CopyFrom -To $UsbRoot
    Ok 'Tools copied'
    if (-not $SkipDownloads -and -not $Only) {
        $c = Read-Host '    Also check the internet now for newer versions of the tools? Y/N  (N = finished in a few minutes)'
        if ($c -notmatch '^[Yy]') { $SkipDownloads = $true }
    }
}

# ------------------------------------------------------------------ downloads
$catalog = Get-Content (Join-Path $UsbRoot 'Sanjeevani\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$instFile = Join-Path $UsbRoot 'Sanjeevani\installed.json'
$installed = @{}
if (Test-Path $instFile) { (Get-Content $instFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $installed[$_.Name] = $_.Value } }
$manual = New-Object System.Collections.ArrayList
$optionalList = New-Object System.Collections.ArrayList
$failed = New-Object System.Collections.ArrayList

if (-not $SkipDownloads -and -not $Only) {
    if (-not $WithWindows -and -not ($installed['win11'])) {
        $c = Read-Host "`n    Also download the official Windows 11 ISO from Microsoft (~7.5 GB)? Y/N"
        $WithWindows = $c -match '^[Yy]'
    }
    if (-not $WithMint -and -not ($installed['mint-xfce'])) {
        $c = Read-Host '    Also download Linux Mint XFCE for old PCs (~3 GB)? Y/N'
        $WithMint = $c -match '^[Yy]'
    }
    $sdioDrv = Join-Path $UsbRoot 'Tools\Drivers\Snappy Driver Installer Origin\drivers'
    if (-not $WithDrivers -and -not (Test-Path $sdioDrv)) {
        $c = Read-Host '    Also download ALL offline driver packs for any PC (~70 GB; needs ~145 GB free while downloading, so a 256 GB pendrive; takes hours)? Y/N'
        $WithDrivers = $c -match '^[Yy]'
    }
}

function Test-Wanted($e) {
    if ($Only) { return ($Only -contains $e.id) }
    if ($e.id -eq 'win11') { return ($WithWindows -or [bool]$installed['win11']) }
    if ($e.id -eq 'mint-xfce') { return ($WithMint -or [bool]$installed['mint-xfce']) }
    return $true
}

function Test-UpToDate($e, $resolvedUrl, $target) {
    $old = $installed[$e.id]
    if (-not $old) { return $false }
    $p = Join-Path $UsbRoot $old.path
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    if ($e.refreshDays) {
        $age = ((Get-Date) - [datetime]$old.date).TotalDays
        if ($age -ge [double]$e.refreshDays) { return $false }
    }
    return ($old.url -eq $resolvedUrl)
}

function Get-FreeGB { return [math]::Round((Get-PSDrive ($UsbRoot.Substring(0, 1))).Free / 1GB, 1) }

# path of a file relative to the USB root (robust against 8.3 short names like RUNNER~1)
function Get-UsbRelPath([string]$Full) {
    $root = (Get-Item -LiteralPath $UsbRoot).FullName.TrimEnd('\') + '\'
    $full2 = (Get-Item -LiteralPath $Full).FullName
    if ($full2.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $full2.Substring($root.Length) }
    return $full2
}

# A tool the user downloaded by hand (from manual-downloads.html): find it on the USB by its
# file name, unpack it if it is still a zip/7z, and register it so it is not listed again.
function Find-ManualItem($e, [string]$Kind) {
    if (-not $e.fileMatch) { return $null }
    $rx = $e.fileMatch
    if ($Kind -eq 'iso') {
        $f = Get-ChildItem (Join-Path $UsbRoot 'ISO') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.iso', '.img' -and $_.BaseName -match $rx } | Select-Object -First 1
        if ($f) { return "ISO\$($f.Name)" }
        return $null
    }
    $folderRel = "Tools\$($e.category)\$($e.name -replace '[^\w\-\. ]', '')"
    $folder = Join-Path $UsbRoot $folderRel
    $files = @(Get-ChildItem (Join-Path $UsbRoot 'Tools'), (Join-Path $UsbRoot 'Installers') -Recurse -File -ErrorAction SilentlyContinue) +
             @(Get-ChildItem $UsbRoot -File -ErrorAction SilentlyContinue)
    $cand = @($files | Where-Object { $_.Extension -in '.exe', '.msi', '.zip', '.7z', '.rar' -and $_.Name -match $rx })
    if (-not $cand.Count) { return $null }
    $pick = { param($list) $list | Where-Object { $_.Extension -eq '.exe' -and (-not $e.exe -or $_.Name -match $e.exe) } | Sort-Object { $_.FullName.Length } | Select-Object -First 1 }
    $exe = & $pick $cand
    if (-not $exe) { $exe = $cand | Where-Object { $_.Extension -in '.exe', '.msi' } | Select-Object -First 1 }
    if (-not $exe) {
        $arc = $cand | Where-Object { $_.Extension -in '.zip', '.7z', '.rar' } | Select-Object -First 1
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        if ($arc.Extension -eq '.zip') { Expand-Archive -LiteralPath $arc.FullName -DestinationPath $folder -Force }
        elseif ($arc.Extension -eq '.7z') { & (Get-7zr) x $arc.FullName ('-o' + $folder) -y | Out-Null }
        else { & (Get-7zFull) x $arc.FullName ('-o' + $folder) -y | Out-Null; if ($LASTEXITCODE -ne 0) { throw "could not unpack $($arc.Name) (7z $LASTEXITCODE)" } }
        Ok "unpacked $($arc.Name) -> $folderRel"
        $inside = @(Get-ChildItem $folder -Recurse -File -ErrorAction SilentlyContinue)
        $exe = & $pick $inside
        if (-not $exe) { $exe = $inside | Where-Object { $_.Extension -eq '.exe' } | Sort-Object { $_.FullName.Length } | Select-Object -First 1 }
        if (-not $exe) { return $folderRel }
    }
    return (Get-UsbRelPath $exe.FullName)
}

# Give a hand-copied ISO the catalog name (e.g. 01-hbcd.iso) so it sorts in the right place in the boot menu
function Set-IsoOrderName([string]$RelPath, $e) {
    $full = Join-Path $UsbRoot $RelPath
    $ext = [IO.Path]::GetExtension($full)
    $newName = "$($e.order)-$($e.id)$ext"
    if ([IO.Path]::GetFileName($full) -eq $newName) { return $RelPath }
    if (Test-Path -LiteralPath (Join-Path (Split-Path $full) $newName)) { return $RelPath }
    try { Rename-Item -LiteralPath $full -NewName $newName -ErrorAction Stop; Ok "renamed to $newName (boot menu order)"; return "ISO\$newName" }
    catch { return $RelPath }
}

function Install-Item($e, [string]$Kind) {
    if (-not (Test-Wanted $e)) { return }
    $label = if ($e.alias) { $e.alias } else { $e.name }
    Say ''
    Say "  -- $label" White
    if ($e.source.kind -eq 'manual') {
        $found = $null
        try { $found = Find-ManualItem $e $Kind } catch { Warn ("could not check hand-copied file: " + $_.Exception.Message) }
        if ($found -and $Kind -eq 'iso') { $found = Set-IsoOrderName $found $e }
        if ($found) {
            $installed[$e.id] = [pscustomobject]@{ url = 'manual'; path = $found; date = (Get-Date).ToString('s'); name = (Split-Path $found -Leaf) }
            Ok "found on USB (added by hand): $found"; return
        }
        if ($e.optional) { [void]$optionalList.Add($e); Say "     optional - not needed: $($e.alt)" DarkGray; return }
        [void]$manual.Add($e); Warn 'manual download (link in Docs\manual-downloads.html)'; return
    }
    if ($Kind -eq 'iso') {
        if ($installed[$e.id] -and $installed[$e.id].url -eq 'manual' -and (Test-Path -LiteralPath (Join-Path $UsbRoot $installed[$e.id].path))) {
            $p0 = Set-IsoOrderName $installed[$e.id].path $e
            $installed[$e.id].path = $p0; $installed[$e.id].name = (Split-Path $p0 -Leaf)
            Ok "on USB (added by hand): $p0"; return
        }
        # an ISO the user copied in by hand (any name containing the id, e.g. HBCD_PE_x64.iso) counts as installed
        $own = Get-ChildItem (Join-Path $UsbRoot 'ISO') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match [regex]::Escape($e.id) -and $_.Name -notmatch ('^\d+-' + [regex]::Escape($e.id) + '\.') } | Select-Object -First 1
        if ($own -and -not ($installed[$e.id] -and $installed[$e.id].url -ne 'manual')) {
            Ok "found on USB (copied by hand): $($own.Name)"
            $rp = Set-IsoOrderName "ISO\$($own.Name)" $e
            $installed[$e.id] = [pscustomobject]@{ url = 'manual'; path = $rp; date = (Get-Date).ToString('s'); name = (Split-Path $rp -Leaf) }
            return
        }
    }
    if ($e.source.kind -eq 'fido' -and $installed[$e.id] -and (Test-Path -LiteralPath (Join-Path $UsbRoot $installed[$e.id].path))) { Ok 'already on USB (delete the ISO to download a newer one)'; return }
    try { $r = Resolve-Source $e } catch { Warn ("could not find latest version: " + $_.Exception.Message); [void]$failed.Add($e); return }
    if (Test-UpToDate $e $r.Url $null) { Ok 'up to date'; return }
    if ($e.sizeMB -and (Get-FreeGB) -lt ([double]$e.sizeMB / 1024 * 1.1)) { Warn "not enough space on USB ($(Get-FreeGB) GB free)"; [void]$failed.Add($e); return }
    $tmp = Join-Path $Work ($e.id + '_' + $r.Name)
    try {
        Say "     $($r.Url)" DarkGray
        $urls = @($r.Url) + @($e.source.mirrors | Where-Object { $_ })
        $got = $false; $lastErr = $null
        foreach ($u in $urls) {
            try {
                if ($u -ne $r.Url) { Warn "     trying official mirror: $(([Uri]$u).Host)" }
                Save-Url $u $tmp $e.page; $got = $true; break
            } catch { $lastErr = $_ }
        }
        if (-not $got) { throw $lastErr }
        $rel = $null
        if ($Kind -eq 'iso') {
            $ext = if ($e.ext) { $e.ext } else { '.iso' }
            $rel = "ISO\$($e.order)-$($e.id)$ext"
            $dest = Join-Path $UsbRoot $rel
            if ($e.extract) {
                $x = Join-Path $Work ($e.id + '_x')
                Remove-Item $x -Recurse -Force -ErrorAction SilentlyContinue
                $zipTmp = $tmp; if ($zipTmp -notmatch '\.zip$') { Rename-Item $tmp ($tmp + '.zip'); $zipTmp = $tmp + '.zip' }
                Expand-Archive -LiteralPath $zipTmp -DestinationPath $x -Force
                $inner = Get-ChildItem $x -Recurse -File | Where-Object { $_.Name -match $e.extract } | Select-Object -First 1
                if (-not $inner) { throw "nothing matching '$($e.extract)' inside the zip" }
                Move-Item -LiteralPath $inner.FullName -Destination $dest -Force
                Remove-Item $zipTmp, $x -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Move-Item -LiteralPath $tmp -Destination $dest -Force
            }
        } elseif ($e.installer) {
            $rel = "Installers\$($r.Name)"
            Move-Item -LiteralPath $tmp -Destination (Join-Path $UsbRoot $rel) -Force
        } else {
            $folderRel = "Tools\$($e.category)\$($e.name -replace '[^\w\-\. ]', '')"
            $folder = Join-Path $UsbRoot $folderRel
            # extract over the old version (never wipe: SDIO keeps its ~40 GB driver packs here)
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $isZip = $false; $is7z = $false
            $fs = [IO.File]::OpenRead($tmp); $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte(); $fs.Close()
            if ($b1 -eq 0x50 -and $b2 -eq 0x4B) { $isZip = $true }
            if ($b1 -eq 0x37 -and $b2 -eq 0x7A) { $is7z = $true }   # '7z'
            if ($is7z) {
                $sz = Get-7zr
                & $sz x $tmp ("-o" + $folder) -y | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "7z extract failed ($LASTEXITCODE)" }
                Remove-Item $tmp -Force
            } elseif ($isZip) {
                $zipTmp = $tmp; if ($zipTmp -notmatch '\.zip$') { Rename-Item $tmp ($tmp + '.zip'); $zipTmp = $tmp + '.zip' }
                Expand-Archive -LiteralPath $zipTmp -DestinationPath $folder -Force
                Remove-Item $zipTmp -Force
            } else {
                $name = if ($e.file) { $e.file } else { $r.Name }
                Move-Item -LiteralPath $tmp -Destination (Join-Path $folder $name) -Force
            }
            $exe = Get-ChildItem $folder -Recurse -File | Where-Object { $_.Name -match $e.exe } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
            $rel = if ($exe) { Get-UsbRelPath $exe.FullName } else { $folderRel }
        }
        $installed[$e.id] = [pscustomobject]@{ url = $r.Url; path = $rel; date = (Get-Date).ToString('s'); name = $r.Name }
        Ok "saved: $rel"
    } catch {
        Fail $_.Exception.Message
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        [void]$failed.Add($e)
    }
}

if (-not $SkipDownloads) {
    Step "Downloading rescue ISOs  (USB free: $(Get-FreeGB) GB)"
    foreach ($e in $catalog.isos) { Install-Item $e 'iso' }
    Step 'Downloading portable tools'
    foreach ($e in $catalog.tools) { Install-Item $e 'tool' }
    $installed | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $instFile -Encoding UTF8
}

# ------------------------------------------------------------------ 7-Zip for the boot-time rescue tool
# PC Doctor Rescue (in Hiren's PE) opens the Windows ISO with 7-Zip to repair Windows offline.
$binDir = Join-Path $UsbRoot 'Sanjeevani\bin'
if (-not (Test-Path (Join-Path $binDir '7z.exe')) -and -not $ResolveOnly) {
    try {
        $sz = Get-7zFull
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Copy-Item (Join-Path (Split-Path $sz) '7z.exe'), (Join-Path (Split-Path $sz) '7z.dll') $binDir -Force
        Ok '7-Zip copied to Sanjeevani\bin (for PC Doctor Rescue)'
    } catch { Warn ('could not prepare 7-Zip for the rescue tool: ' + $_.Exception.Message) }
}

# SDIO keeps its torrent copy in update\SDIO_Update after placing the packs in drivers, and a pack set
# downloaded with a torrent program often lands in SDIO_Update next to it - each is another ~70 GB.
# Remove a pack from those copies only when drivers already holds the same file with the same size.
function Remove-SdioDuplicates([string]$SdioDir) {
    $keepDir = Join-Path $SdioDir 'drivers'
    if (-not (Test-Path $keepDir)) { return }
    $keep = @{}; Get-ChildItem $keepDir -File -ErrorAction SilentlyContinue | ForEach-Object { $keep[$_.Name.ToLower()] = $_.Length }
    $freed = 0.0
    foreach ($root in (Join-Path $SdioDir 'update\SDIO_Update'), (Join-Path $SdioDir 'SDIO_Update')) {
        $copy = Join-Path $root 'drivers'
        if (-not (Test-Path $copy)) { continue }
        foreach ($f in @(Get-ChildItem $copy -File -ErrorAction SilentlyContinue)) {
            if ($keep.ContainsKey($f.Name.ToLower()) -and $keep[$f.Name.ToLower()] -eq $f.Length) {
                $freed += $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        # drop the leftover torrent folder once no driver pack is left in it
        if (-not @(Get-ChildItem $copy -File -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if ($freed -gt 0) { Ok ("Removed duplicate driver pack copies: {0:N1} GB freed" -f ($freed / 1GB)) }
}

# ------------------------------------------------------------------ offline driver packs (SDIO)
if ($WithDrivers -and $installed['sdio']) {
    Step 'Offline driver packs (Snappy Driver Installer Origin)'
    $sdioExe = Join-Path $UsbRoot $installed['sdio'].path
    if (-not (Test-Path -LiteralPath $sdioExe)) { Warn 'SDIO not found on the USB - skipped' }
    # SDIO downloads into update\ and then copies into drivers\, so it briefly needs twice the space
    elseif ((Get-FreeGB) -lt 145) { Warn "Only $(Get-FreeGB) GB free - downloading the driver packs needs ~145 GB free (~70 GB after it finishes). Skipped." }
    else {
        $sdioDir = Split-Path $sdioExe
        $drv = Join-Path $sdioDir 'drivers'
        $have = 0; if (Test-Path $drv) { $have = (Get-ChildItem $drv -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        if ($have -gt 5GB) { Ok ("Driver packs already on USB: {0:N1} GB (SDIO -> Updates to refresh them)" -f ($have / 1GB)); Remove-SdioDuplicates $sdioDir }
        else {
            # 1) fully automatic: SDIO's own scripting engine downloads every driver pack with its built-in
            #    torrent engine - no torrent program and no clicking needed
            $scriptDir = Join-Path $sdioDir 'scripts'
            New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
            $sdScript = Join-Path $scriptDir 'sanjeevani-get-all-driverpacks.txt'
            Set-Content -LiteralPath $sdScript -Encoding ASCII -Value @(
                '# Sanjeevani: download all driver packs (used by Setup-Sanjeevani.ps1)',
                'echo Sanjeevani - downloading all driver packs. This takes hours; keep this window open.',
                'init', 'checkupdates', 'onerror goto :fail', 'get driverpacks all', 'echo Driver packs downloaded.', 'end',
                ':fail', 'echo Could not reach the driver pack server.', 'end')
            Say ''
            Say '    Downloading all driver packs automatically (~70 GB, several hours).' Yellow
            Say '    Allow Snappy Driver Installer in the Windows Firewall if asked. Keep this window open.' Yellow
            $sp = Start-Process -FilePath $sdioExe -ArgumentList ('-script:scripts\sanjeevani-get-all-driverpacks.txt') -WorkingDirectory $sdioDir -PassThru
            # SDIO's script window shows no progress, so show it here: size, speed, time left.
            # If nothing arrives for 15 minutes, stop it and fall back to the Welcome window.
            $sizeOf = { $t = 0; foreach ($d in (Join-Path $sdioDir 'update'), (Join-Path $sdioDir 'indexes')) { if (Test-Path $d) { $t += [double](Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } }; $t }
            $total = 70GB; $prev = & $sizeOf; $lastGrow = Get-Date; $t0 = Get-Date; $start = $prev
            while (-not $sp.WaitForExit(30000)) {
                $now = & $sizeOf
                if ($now -gt $prev) { $lastGrow = Get-Date }
                $avg = ($now - $start) / [math]::Max(1, ((Get-Date) - $t0).TotalSeconds)
                $left = if ($avg -gt 0) { '{0:N1} h' -f ([math]::Max(0, $total - $now) / $avg / 3600) } else { '?' }
                Write-Host ("`r    Driver packs: {0,6:N2} GB of ~70 GB   {1,6:N2} MB/s   time left ~{2}      " -f ($now / 1GB), ((($now - $prev) / 30) / 1MB), $left) -NoNewline
                $prev = $now
                if (((Get-Date) - $lastGrow).TotalMinutes -ge 15) {
                    Write-Host ''
                    Warn 'No download progress for 15 minutes - stopping the automatic download.'
                    try { $sp.Kill() } catch { }
                    break
                }
            }
            Write-Host ''
            $have = 0; if (Test-Path $drv) { $have = (Get-ChildItem $drv -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
            if ($have -gt 5GB) { Ok ("Driver packs on USB: {0:N1} GB" -f ($have / 1GB)); Remove-SdioDuplicates $sdioDir }
            else {
                # 2) fallback: SDIO's Welcome window (appears only while it has no settings file)
                Warn 'Automatic download did not complete. Opening Snappy Driver Installer - click "Download all driver packs".'
                Get-ChildItem $sdioDir -Filter '*.cfg' -File -ErrorAction SilentlyContinue | ForEach-Object { Rename-Item $_.FullName ($_.Name + '.old') -Force -ErrorAction SilentlyContinue }
                Start-Process -FilePath $sdioExe -WorkingDirectory $sdioDir
            }
        }
    }
}

# ------------------------------------------------------------------ ventoy.json
Step 'Writing boot menu configuration (ventoy.json)'
$themeDir = '/ventoy/theme/sanjeevani'
$fonts = @(Get-Content (Join-Path $UsbRoot 'ventoy\theme\sanjeevani\fonts.list') | Where-Object { $_ } | ForEach-Object { "$themeDir/$_" })
$alias = @(); $class = @(); $tips = @()
$isoFiles = @(Get-ChildItem (Join-Path $UsbRoot 'ISO') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.iso', '.img', '.wim', '.vhd', '.vhdx', '.efi' })
foreach ($f in $isoFiles) {
    $p = '/ISO/' + $f.Name
    $e = $catalog.isos | Where-Object { $f.Name -match ('^\d+-' + [regex]::Escape($_.id) + '\.') } | Select-Object -First 1
    if (-not $e) { $e = $catalog.isos | Where-Object { $f.BaseName -match [regex]::Escape($_.id) } | Select-Object -First 1 }
    if ($e) {
        $alias += [ordered]@{ image = $p; alias = $e.alias }
        $class += [ordered]@{ key = $f.Name; class = $e.class }
        $tips += [ordered]@{ image = $p; tip = $e.tip }
    }
}
$cfg = [ordered]@{
    control   = @(
        [ordered]@{ VTOY_DEFAULT_SEARCH_ROOT = '/ISO' },
        [ordered]@{ VTOY_FILT_DOT_UNDERSCORE_FILE = '1' },
        [ordered]@{ VTOY_DEFAULT_MENU_MODE = '0' }
    )
    theme     = [ordered]@{
        file = "$themeDir/theme.txt"; gfxmode = '1920x1080,1600x900,1366x768,1280x1024,1024x768,auto'; display_mode = 'GUI'
        ventoy_left = '4%'; ventoy_top = '95%'; ventoy_color = '#475569'; fonts = $fonts
    }
    menu_alias = $alias
    menu_class = $class
    menu_tip   = [ordered]@{ left = '35%'; top = '85%'; color = '#94a3b8'; tips = $tips }
}
$json = $cfg | ConvertTo-Json -Depth 6
# Windows PowerShell writes & ' < > as \u0026 \u0027 \u003c \u003e; Ventoy shows those literally, so write the characters
$json = $json.Replace('\u0026', '&').Replace('\u0027', "'").Replace('\u003c', '<').Replace('\u003e', '>')
[IO.File]::WriteAllText((Join-Path $UsbRoot 'ventoy\ventoy.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Ok "$($isoFiles.Count) boot entries configured"

# ------------------------------------------------------------------ manual / optional list
function Get-Row($e, [string]$why) {
    $where = if ($e.order) { "ISO\" } elseif ($e.installer) { 'Installers\' } else { "Tools\$($e.category)\$($e.name)\" }
    $nm = if ($e.alias) { $e.alias } else { $e.name }
    "<tr><td>$([Net.WebUtility]::HtmlEncode($nm))</td><td><a href='$($e.page)'>$($e.page)</a></td><td><code>$where</code></td><td>$([Net.WebUtility]::HtmlEncode($why))</td></tr>"
}
$needRows = @(foreach ($e in @($manual) + @($failed)) { Get-Row $e $(if ($failed -contains $e) { 'आपोआप download झाले नाही - UPDATE.cmd नंतर पुन्हा चालवा' } else { 'website वरून हाताने' }) })
$optRows = @(foreach ($e in $optionalList) { Get-Row $e $e.alt })
$needHtml = if ($needRows.Count) { "<h2>हे शिल्लक आहेत</h2><table><tr><th>Tool</th><th>Download page</th><th>USB वर कुठे</th><th>टीप</th></tr>$($needRows -join "`n")</table>" } else { "<h2 style='color:#15803d'>✔ सगळे आवश्यक tools pendrive वर आहेत</h2>" }
$html = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Sanjeevani - tools status</title>
<style>body{font-family:'Nirmala UI','Segoe UI',sans-serif;margin:24px;color:#0f172a}table{border-collapse:collapse;width:100%;margin-bottom:24px}td,th{border-bottom:1px solid #e2e8f0;padding:8px;text-align:left}th{background:#f1f5f9}code{background:#f1f5f9;padding:2px 5px}.muted{color:#64748b}</style></head><body>
$needHtml
<p class="muted">हाताने download केलेली file दिलेल्या folder मध्ये (किंवा USB वर कुठेही) ठेवा, <b>नाव बदलू नका</b>, zip extract करायची गरज नाही. मग <b>Sanjeevani\Setup\UPDATE.cmd</b> चालवा.</p>
<h2>Optional (गरज नाही)</h2>
<p class="muted">हे tools हवे असल्यास घ्या. त्यांचे काम pendrive वरचे दुसरे tools आधीच करतात.</p>
<table><tr><th>Tool</th><th>Download page</th><th>USB वर कुठे</th><th>त्याऐवजी</th></tr>
$($optRows -join "`n")
</table><p class="muted">Last setup: $(Get-Date -Format 'dd-MM-yyyy HH:mm')</p></body></html>
"@
$manualFile = Join-Path $UsbRoot 'Sanjeevani\Docs\manual-downloads.html'
[IO.File]::WriteAllText($manualFile, $html, (New-Object System.Text.UTF8Encoding($true)))

Get-ChildItem (Join-Path $UsbRoot 'Sanjeevani'), (Join-Path $UsbRoot 'Tools'), (Join-Path $UsbRoot 'Installers') -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
Copy-Item (Join-Path $UsbRoot 'Sanjeevani\Docs\guide-mr.html') (Join-Path $UsbRoot 'READ-ME-मार्गदर्शक.html') -Force -ErrorAction SilentlyContinue

Step 'Finished'
Ok "USB: $UsbRoot   (free: $(Get-FreeGB) GB)"
if (-not $failed.Count -and -not $manual.Count) { Ok 'All essential tools are on the USB.' }
if ($failed.Count) { Warn ("{0} item(s) could not be downloaded this time ({1}) - run UPDATE.cmd again later" -f $failed.Count, (($failed | ForEach-Object { $_.id }) -join ', ')) }
if ($manual.Count) { Warn ("{0} item(s) need a manual download - see Docs\manual-downloads.html" -f $manual.Count) }
if ($optionalList.Count) { Say ("    {0} optional extras skipped (their work is covered by other tools) - list in Docs\manual-downloads.html" -f $optionalList.Count) DarkGray }
Say ''
Say '  To boot: plug the USB, press the Boot Menu key (F12/F9/F11/Esc), choose the USB.' DarkCyan
Say ''
if ($manual.Count -or $failed.Count) { Start-Process $manualFile }
Read-Host 'Press Enter to close'
