# Sanjeevani PC Doctor - "समस्या सांगा": the user describes a problem in Marathi, English or Roman Marathi.
#   * Find-PDProblem    - offline: matches the text against data\problems.json (no internet, instant)
#   * Invoke-PDAiAsk    - optional online AI (Google Gemini free tier, or Anthropic Claude) with the user's own API key.
#                         The AI only understands the text and picks problems from the same catalog: it never runs
#                         anything. Every fix still goes through PC Doctor's own tested, confirmed actions.
#   * Invoke-PDQuickFix - small safe fixes the catalog uses (printer queue, audio, time, Explorer, Search, ...)
Set-StrictMode -Off

# ------------------------------------------------------------------ offline matching
function Get-PDProblems([string]$DataDir) {
    return @((Get-Content -LiteralPath (Join-Path $DataDir 'problems.json') -Raw -Encoding UTF8 | ConvertFrom-Json).problems)
}

function Test-PDKeyword([string]$Text, [string]$Kw) {
    $k = $Kw.ToLower()
    $short = ($k -match '^[a-z0-9 .:%\-]+$') -and $k.Length -lt 5
    $pat = '(?<![\p{L}\p{M}\p{N}])' + [regex]::Escape($k) + $(if ($short) { '(?![\p{L}\p{N}])' } else { '' })
    return [regex]::IsMatch($Text, $pat)
}

# Returns the best matching problems (score, problem). A phrase counts once per word; "a+b" (both words anywhere) counts 2.
function Find-PDProblem {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][object[]]$Problems, [int]$Max = 3)
    $t = $Text.ToLower()
    $res = @()
    foreach ($p in $Problems) {
        $score = 0
        foreach ($k in $p.kw) {
            $parts = $k.Split('+')
            if ($parts.Count -eq 2 -and $parts[0] -and $parts[1] -and $k -notmatch 'c\+\+') {
                if ((Test-PDKeyword $t $parts[0]) -and (Test-PDKeyword $t $parts[1])) { $score += 2 }
            } elseif (Test-PDKeyword $t $k) { $score += ($k.Trim() -split '\s+').Count }
        }
        if ($score -gt 0) { $res += [pscustomobject]@{ Score = $score; Problem = $p } }
    }
    if (-not $res.Count) { return @() }
    $res = @($res | Sort-Object Score -Descending)
    $top = $res[0].Score
    return @($res | Where-Object { $_.Score -ge [math]::Max(1, $top * 0.4) } | Select-Object -First $Max)
}

# ------------------------------------------------------------------ quick fixes
function New-PDFixResult([bool]$Ok, [string]$Mr, [string]$En) { [pscustomobject]@{ Ok = $Ok; Mr = $Mr; En = $En } }

function Restart-PDServiceSafe([string]$Name) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { return $false }
    if ($s.StartType -eq 'Disabled') { Set-Service -Name $Name -StartupType Manual -ErrorAction SilentlyContinue }
    try { if ($s.Status -eq 'Running') { Restart-Service -Name $Name -Force -ErrorAction Stop } else { Start-Service -Name $Name -ErrorAction Stop }; return $true } catch { return $false }
}

function Invoke-PDQuickFix {
    param([Parameter(Mandatory)][string]$Id)
    switch ($Id) {
        'printer' {
            $q = Join-Path $env:WINDIR 'System32\spool\PRINTERS'
            Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
            $n = @(Get-ChildItem -LiteralPath $q -File -ErrorAction SilentlyContinue).Count
            Get-ChildItem -LiteralPath $q -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            $ok = Restart-PDServiceSafe 'Spooler'
            Write-PDLog "Printer: $n अडकलेल्या files काढल्या, print service restart" 'OK'
            return (New-PDFixResult $ok "Print queue मधल्या $n अडकलेल्या files काढल्या आणि print service पुन्हा सुरू केली. आता पुन्हा print करून पाहा." "Removed $n stuck print files and restarted the print service. Try printing again.")
        }
        'audio' {
            $a = Restart-PDServiceSafe 'AudioEndpointBuilder'; $b = Restart-PDServiceSafe 'Audiosrv'
            Set-Service -Name Audiosrv -StartupType Automatic -ErrorAction SilentlyContinue
            return (New-PDFixResult ($a -and $b) 'Windows audio services पुन्हा सुरू केल्या. Taskbar वरच्या speaker icon वर योग्य device निवडा आणि आवाज तपासा.' 'Restarted the Windows audio services. Pick the right device on the taskbar speaker icon and test the sound.')
        }
        'time' {
            Set-Service -Name W32Time -StartupType Automatic -ErrorAction SilentlyContinue
            [void](Restart-PDServiceSafe 'W32Time')
            $null = & w32tm.exe /config /syncfromflags:manual /manualpeerlist:"time.windows.com,0x8 time.google.com,0x8" /update 2>&1
            $out = (& w32tm.exe /resync /force 2>&1) -join ' '
            $ok = $LASTEXITCODE -eq 0
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start -Value 3 -ErrorAction SilentlyContinue
            $now = (Get-Date).ToString('dd-MM-yyyy HH:mm')
            if ($ok) { return (New-PDFixResult $true "Internet वरून वेळ घेतली. आता: $now. PC बंद केल्यावर पुन्हा चुकत असेल तर motherboard ची CMOS battery बदला." "Time synced from the internet. Now: $now. If it is wrong again after a shutdown, replace the CMOS battery.") }
            return (New-PDFixResult $false "वेळ sync झाली नाही (internet नाही?): $out" "Time could not sync (no internet?): $out")
        }
        'explorer' {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
            for ($w = 0; $w -lt 8 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $w++) { Start-Sleep 1 }
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { $null = & runas.exe /trustlevel:0x20000 explorer.exe 2>&1 }   # start the shell without admin rights
            return (New-PDFixResult $true 'Taskbar / desktop / File Explorer पुन्हा सुरू केले.' 'Restarted the taskbar / desktop / File Explorer.')
        }
        'search' {
            $ok = Restart-PDServiceSafe 'WSearch'
            return (New-PDFixResult $ok 'Windows Search service पुन्हा सुरू केली. 1-2 मिनिटांनी search करून पाहा.' 'Restarted the Windows Search service. Try searching in 1-2 minutes.')
        }
        'bluetooth' {
            $ok = Restart-PDServiceSafe 'bthserv'
            [void](Restart-PDServiceSafe 'BTAGService')
            return (New-PDFixResult $ok 'Bluetooth service पुन्हा सुरू केली. Device "Remove" करून पुन्हा pair करा.' 'Restarted the Bluetooth service. Remove the device and pair it again.')
        }
        'wifi' {
            Set-Service -Name WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue
            $ok = Restart-PDServiceSafe 'WlanSvc'
            $en = @()
            foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Disabled' -and ($_.InterfaceDescription -match '(?i)wi-?fi|wireless|wlan|802\.11' -or $_.Name -match '(?i)wi-?fi|wireless|wlan') })) {
                try { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop; $en += $a.Name } catch { }
            }
            $has = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match '(?i)wi-?fi|wireless|wlan|802\.11' }).Count
            $msg = 'WLAN service सुरू केली.' + $(if ($en) { " बंद असलेले adapters चालू केले: $($en -join ', ')." } else { '' })
            $msgEn = 'Started the WLAN service.' + $(if ($en) { " Enabled adapters: $($en -join ', ')." } else { '' })
            if (-not $has) { $msg += ' या PC मध्ये WiFi adapter दिसत नाही - driver नाही: "Drivers तपासा".'; $msgEn += ' No WiFi adapter is visible - no driver: "Check drivers".'; $ok = $false }
            else { $msg += ' Airplane mode बंद आहे ना आणि keyboard ची WiFi key पाहा.'; $msgEn += ' Check that Airplane mode is off and the keyboard WiFi key.' }
            return (New-PDFixResult $ok $msg $msgEn)
        }
        'usb' {
            $out = (& pnputil.exe /scan-devices 2>&1) -join ' '
            return (New-PDFixResult ($LASTEXITCODE -eq 0) 'नवीन hardware पुन्हा शोधले. Device अजून दिसत नसेल तर दुसरा port / cable वापरा.' 'Scanned for hardware again. If the device still does not show, try another port / cable.')
        }
        'store' {
            Start-Process -FilePath "$env:WINDIR\System32\wsreset.exe" -ErrorAction SilentlyContinue
            return (New-PDFixResult $true 'Microsoft Store cache reset सुरू केले - काही सेकंदांनी Store आपोआप उघडेल.' 'Started the Microsoft Store cache reset - the Store opens by itself in a few seconds.')
        }
        'dns' {
            $null = & ipconfig.exe /flushdns 2>&1
            try { Clear-DnsClientCache -ErrorAction Stop } catch { }
            return (New-PDFixResult $true 'DNS cache साफ केला. Website पुन्हा उघडून पाहा.' 'Cleared the DNS cache. Open the website again.')
        }
        default { throw "unknown quick fix: $Id" }
    }
}

# ------------------------------------------------------------------ online AI (optional)
function Get-PDAiConfig([string]$UsbRoot) {
    $f = Join-Path $UsbRoot 'Sanjeevani\ai.json'
    $c = [pscustomobject]@{ provider = 'gemini'; key = ''; model = ''; sendPcInfo = $true }
    if (Test-Path -LiteralPath $f) {
        try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $c | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } } catch { }
    }
    return $c
}
function Save-PDAiConfig([string]$UsbRoot, $Config) {
    $f = Join-Path $UsbRoot 'Sanjeevani\ai.json'
    ConvertTo-Json -InputObject $Config | Set-Content -LiteralPath $f -Encoding UTF8
}

function New-PDAiPrompt {
    param([Parameter(Mandatory)][object[]]$Problems, [string]$PcInfo)
    $list = ($Problems | ForEach-Object { "- $($_.id): $($_.en.title)" }) -join "`n"
    $sys = @"
You are the assistant inside "Sanjeevani PC Doctor", a free Windows repair tool used by computer technicians and ordinary users in Maharashtra, India.
The user describes a PC / laptop problem in Marathi (Devanagari), English or Roman Marathi.
1. Understand the problem. 2. Pick up to 3 problem ids from the list below that PC Doctor can check or fix (most likely first).
3. Give short practical steps for a non-expert (max 6), in Marathi (Devanagari) and in English.
Rules: never give commands to type, registry edits, cracks, activators or downloads from unofficial sites; say when a technician / hardware repair is needed.
Reply with ONLY this JSON (no markdown):
{"understood_mr":"...","understood_en":"...","problem_ids":["..."],"steps_mr":["..."],"steps_en":["..."],"hardware_likely":false,"note_mr":"","note_en":""}
Problem ids PC Doctor knows:
$list
"@
    $user = $(if ($PcInfo) { "PC: $PcInfo`n`n" } else { '' })
    return [pscustomobject]@{ System = $sys; UserPrefix = $user }
}

function Invoke-PDHttpJson {
    param([string]$Url, [hashtable]$Headers, [string]$Body, [string]$Method = 'POST')
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $p = @{ Uri = $Url; Method = $Method; Headers = $Headers; UseBasicParsing = $true; TimeoutSec = 60 }
    if ($Body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($Body); $p.ContentType = 'application/json; charset=utf-8' }
    try {
        $r = Invoke-WebRequest @p
        $ms = New-Object IO.MemoryStream; $r.RawContentStream.Position = 0; $r.RawContentStream.CopyTo($ms)
        return [Text.Encoding]::UTF8.GetString($ms.ToArray())
    } catch {
        $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        $msg = switch ($code) {
            { $_ -in 400, 401, 403 } { 'API key चुकीची / चालू नाही (API key invalid or not enabled)' }
            404 { 'हे AI model मिळाले नाही (model not found)' }
            429 { 'मोफत मर्यादा संपली - थोड्या वेळाने प्रयत्न करा (free quota used up - try later)' }
            { $_ -ge 500 } { 'AI service सध्या उपलब्ध नाही (service unavailable)' }
            default { 'Internet / AI service ला पोहोचता आले नाही (no connection)' }
        }
        throw "$msg [$code]"
    }
}

function Resolve-PDGeminiModel($Config, [scriptblock]$Transport) {
    if ($Config.model) { return $Config.model }
    $txt = & $Transport "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200" @{ 'x-goog-api-key' = $Config.key } $null 'GET'
    $models = @((ConvertFrom-Json $txt).models | Where-Object { $_.supportedGenerationMethods -contains 'generateContent' } | ForEach-Object { $_.name -replace '^models/', '' })
    # newest stable "gemini-<version>-flash" (not lite / preview / image)
    $best = $models | Where-Object { $_ -match '^gemini-(\d+(?:\.\d+)?)-flash$' } | Sort-Object { [double]($_ -replace '^gemini-(\d+(?:\.\d+)?)-flash$', '$1') } -Descending | Select-Object -First 1
    if (-not $best) { $best = $models | Where-Object { $_ -match '^gemini-flash-latest$|flash' -and $_ -notmatch 'lite|image|tts|audio|live' } | Select-Object -First 1 }
    if (-not $best) { throw 'या key ला कोणतेही Gemini Flash model उपलब्ध नाही' }
    return $best
}

function ConvertFrom-PDAiAnswer([string]$Text, [object[]]$Problems) {
    $t = $Text.Trim()
    $t = $t -replace '^```(?:json)?\s*', '' -replace '\s*```$', ''
    $s = $t.IndexOf('{'); $e = $t.LastIndexOf('}')
    if ($s -lt 0 -or $e -le $s) { throw 'AI चे उत्तर समजले नाही' }
    $j = $t.Substring($s, $e - $s + 1) | ConvertFrom-Json
    $known = @($Problems | ForEach-Object { $_.id })
    [pscustomobject]@{
        UnderstoodMr = [string]$j.understood_mr; UnderstoodEn = [string]$j.understood_en
        ProblemIds = @(@($j.problem_ids) | Where-Object { $_ -in $known } | Select-Object -First 3)    # only ids PC Doctor knows
        StepsMr = @($j.steps_mr | Where-Object { $_ } | Select-Object -First 8); StepsEn = @($j.steps_en | Where-Object { $_ } | Select-Object -First 8)
        Hardware = [bool]$j.hardware_likely; NoteMr = [string]$j.note_mr; NoteEn = [string]$j.note_en
    }
}

function Invoke-PDAiAsk {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)]$Config, [Parameter(Mandatory)][object[]]$Problems,
        [string]$PcInfo, [scriptblock]$Transport)
    if (-not $Config.key) { throw 'AI ची API key सेट केलेली नाही (AI सेटिंग्ज)' }
    if (-not $Transport) { $Transport = { param($u, $h, $b, $m) Invoke-PDHttpJson -Url $u -Headers $h -Body $b -Method $(if ($m) { $m } else { 'POST' }) } }
    $pr = New-PDAiPrompt -Problems $Problems -PcInfo $PcInfo
    $userText = $pr.UserPrefix + "Problem: " + $Text
    if ($Config.provider -eq 'anthropic') {
        $model = if ($Config.model) { $Config.model } else { 'claude-haiku-5-5' }
        $body = ConvertTo-Json -Depth 6 -Compress -InputObject @{ model = $model; max_tokens = 1500; system = $pr.System; messages = @(@{ role = 'user'; content = $userText }) }
        $txt = & $Transport 'https://api.anthropic.com/v1/messages' @{ 'x-api-key' = $Config.key; 'anthropic-version' = '2023-06-01' } $body 'POST'
        $ans = ((ConvertFrom-Json $txt).content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ''
    } else {
        $model = Resolve-PDGeminiModel $Config $Transport
        $body = ConvertTo-Json -Depth 8 -Compress -InputObject @{
            systemInstruction = @{ parts = @(@{ text = $pr.System }) }
            contents = @(@{ role = 'user'; parts = @(@{ text = $userText }) })
            generationConfig = @{ temperature = 0.2; responseMimeType = 'application/json' }
        }
        $txt = & $Transport "https://generativelanguage.googleapis.com/v1beta/models/$($model):generateContent" @{ 'x-goog-api-key' = $Config.key } $body 'POST'
        $ans = ((ConvertFrom-Json $txt).candidates[0].content.parts | ForEach-Object { $_.text }) -join ''
    }
    $r = ConvertFrom-PDAiAnswer $ans $Problems
    $r | Add-Member -NotePropertyName Model -NotePropertyValue $model -Force
    return $r
}

# ------------------------------------------------------------------ understanding the problem (AI or keywords)
# Mode: auto | online | offline | basic.  Auto = online AI if a key is set, else offline AI if it is on the USB
# and this PC has the RAM, and always the keyword matcher as the final fallback. Returns ranked problem ids.
function Resolve-PDProblemIds {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][object[]]$Problems, [Parameter(Mandatory)][string]$UsbRoot,
        [string]$Mode = 'auto', [string]$PcInfo, $Config)
    $notes = @(); $ids = @(); $source = 'basic'; $model = $null; $und = $null
    if (-not $Config) { $Config = Get-PDAiConfig $UsbRoot }
    if ($Mode -in 'auto', 'online' -and $Config.key) {
        try {
            Write-PDLog 'Online AI ला समस्या समजावत आहे...' 'STEP'
            $r = Invoke-PDAiAsk -Text $Text -Config $Config -Problems $Problems -PcInfo $PcInfo
            $ids = @($r.ProblemIds); $source = 'online'; $model = $r.Model; $und = $r.UnderstoodEn
        } catch { $notes += "online AI: $($_.Exception.Message)" }
    }
    if (-not $ids.Count -and $Mode -in 'auto', 'offline' -and (Get-Command Find-PDLocalAI -ErrorAction SilentlyContinue)) {
        $ai = Find-PDLocalAI $UsbRoot
        if ($ai) {
            $fit = Test-PDLocalAIFit $ai
            if ($fit.Ok) {
                try {
                    Write-PDLog 'Offline AI सुरू करत आहे (पहिल्यांदा 30-90 सेकंद)...' 'STEP'
                    Set-PDProgress -1 'Offline AI'
                    $r = Invoke-PDLocalAIAsk -Text $Text -Problems $Problems -Ai $ai
                    $ids = @($r.ProblemIds); $source = 'offline'; $model = $r.Model; $und = $r.UnderstoodEn
                } catch { $notes += "offline AI: $($_.Exception.Message)" }
            } else { $notes += "offline AI: $($fit.Why)" }
        } elseif ($Mode -eq 'offline') { $notes += 'offline AI is not on this USB (run UPDATE.cmd and answer Y to "offline AI")' }
    }
    # keyword matches always join in as further candidates
    $kw = @(Find-PDProblem -Text $Text -Problems $Problems -Max 3 | ForEach-Object { $_.Problem.id })
    if (-not $ids.Count -and $kw.Count) { $source = 'basic' }
    $all = @($ids + $kw | Select-Object -Unique | Select-Object -First 4)
    foreach ($n in $notes) { Write-PDLog $n 'WARN' }
    return [pscustomobject]@{ Ids = $all; Source = $source; Model = $model; UnderstoodEn = $und; Notes = $notes }
}

Export-ModuleMember -Function Resolve-PDProblemIds, Get-PDProblems, Test-PDKeyword, Find-PDProblem, Invoke-PDQuickFix, Get-PDAiConfig, Save-PDAiConfig,
    New-PDAiPrompt, ConvertFrom-PDAiAnswer, Invoke-PDAiAsk, Invoke-PDHttpJson
