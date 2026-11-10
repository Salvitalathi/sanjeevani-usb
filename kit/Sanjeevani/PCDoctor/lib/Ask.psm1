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

# Spelling / accent-tolerant form of a text, so speech-to-text spellings and regional pronunciations still match:
# Devanagari: no nukta, half-nasal -> anusvara, long = short vowels, aspirated = plain consonants, ळ/ण/श/ष -> ल/न/स;
# Roman: doubled letters and common spelling variants folded.
function ConvertTo-PDLoose([string]$Text) {
    if (-not $Text) { return '' }
    $t = $Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC)
    $t = $t -replace '़', '' -replace 'ँ', 'ं'
    $t = $t -replace '[ङञणनम]्(?=[क-ह])', 'ं'
    $map = @{ 'ी' = 'ि'; 'ू' = 'ु'; 'ई' = 'इ'; 'ऊ' = 'उ'; 'ॅ' = 'े'; 'ॉ' = 'ो'; 'ऑ' = 'ओ'; 'ख' = 'क'; 'घ' = 'ग'; 'छ' = 'च'; 'झ' = 'ज'; 'ठ' = 'ट'; 'ढ' = 'ड'
              'थ' = 'त'; 'ध' = 'द'; 'फ' = 'प'; 'भ' = 'ब'; 'ळ' = 'ल'; 'ण' = 'न'; 'श' = 'स'; 'ष' = 'स'; 'ञ' = 'न'; 'ङ' = 'न' }
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) { $s = [string]$ch; if ($map.ContainsKey($s)) { [void]$sb.Append($map[$s]) } else { [void]$sb.Append($s) } }
    $t = $sb.ToString()
    $t = $t -replace 'aa', 'a' -replace 'ee', 'i' -replace 'oo', 'u' -replace '([kgcjtdpb])h', '$1' -replace 'sh', 's' -replace 'w', 'v' -replace 'z', 'j' -replace '([a-z])\1', '$1'
    return $t
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
    $tl = ConvertTo-PDLoose $t
    $res = @()
    foreach ($p in $Problems) {
        $score = 0
        foreach ($k0 in $p.kw) {
            $k = $k0
            if (-not (Test-PDKeyword $t ($k0 -replace '\+.*$', '')) -and $k0 -notmatch '^[a-z0-9 .:%+\-]{1,4}$') { $k = ConvertTo-PDLoose $k0; $t2 = $tl } else { $t2 = $t }
            $parts = $k.Split('+')
            if ($parts.Count -eq 2 -and $parts[0] -and $parts[1] -and $k -notmatch 'c\+\+') {
                if ((Test-PDKeyword $t2 $parts[0]) -and (Test-PDKeyword $t2 $parts[1])) { $score += 2 }
            } elseif (Test-PDKeyword $t2 $k) { $score += ($k.Trim() -split '\s+').Count }
        }
        if ($score -gt 0) { $res += [pscustomobject]@{ Score = $score; Problem = $p } }
    }
    if (-not $res.Count) { return @() }
    $res = @($res | Sort-Object Score -Descending)
    $top = $res[0].Score
    return @($res | Where-Object { $_.Score -ge [math]::Max(1, $top * 0.4) } | Select-Object -First $Max)
}

# ------------------------------------------------------------------ quick fixes
function New-PDFixResult([bool]$Ok, [string]$Mr, [string]$En, [string]$Hi) { [pscustomobject]@{ Ok = $Ok; Mr = $Mr; En = $En; Hi = $(if ($Hi) { $Hi } else { $En }) } }

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
            Write-PDLog "Printer: removed $n stuck files, restarted the print service" 'OK'
            return (New-PDFixResult $ok "Print queue मधल्या $n अडकलेल्या files काढल्या आणि print service पुन्हा सुरू केली. आता पुन्हा print करून पाहा." "Removed $n stuck print files and restarted the print service. Try printing again." "Print queue की $n अटकी files हटाईं और print service फिर शुरू की। अब फिर से print करके देखें।")
        }
        'audio' {
            $a = Restart-PDServiceSafe 'AudioEndpointBuilder'; $b = Restart-PDServiceSafe 'Audiosrv'
            Set-Service -Name Audiosrv -StartupType Automatic -ErrorAction SilentlyContinue
            return (New-PDFixResult ($a -and $b) 'Windows audio services पुन्हा सुरू केल्या. Taskbar वरच्या speaker icon वर योग्य device निवडा आणि आवाज तपासा.' 'Restarted the Windows audio services. Pick the right device on the taskbar speaker icon and test the sound.' 'Windows audio services फिर शुरू कीं। Taskbar के speaker icon पर सही device चुनें और आवाज़ जाँचें।')
        }
        'time' {
            Set-Service -Name W32Time -StartupType Automatic -ErrorAction SilentlyContinue
            [void](Restart-PDServiceSafe 'W32Time')
            $null = & w32tm.exe /config /syncfromflags:manual /manualpeerlist:"time.windows.com,0x8 time.google.com,0x8" /update 2>&1
            $out = (& w32tm.exe /resync /force 2>&1) -join ' '
            $ok = $LASTEXITCODE -eq 0
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start -Value 3 -ErrorAction SilentlyContinue
            $now = (Get-Date).ToString('dd-MM-yyyy HH:mm')
            if ($ok) { return (New-PDFixResult $true "Internet वरून वेळ घेतली. आता: $now. PC बंद केल्यावर पुन्हा चुकत असेल तर motherboard ची CMOS battery बदला." "Time synced from the internet. Now: $now. If it is wrong again after a shutdown, replace the CMOS battery." "Internet से समय लिया। अब: $now. PC बंद करने के बाद फिर गलत हो तो motherboard की CMOS battery बदलें।") }
            return (New-PDFixResult $false "वेळ sync झाली नाही (internet नाही?): $out" "Time could not sync (no internet?): $out" "समय sync नहीं हुआ (internet नहीं?): $out")
        }
        'explorer' {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
            for ($w = 0; $w -lt 8 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $w++) { Start-Sleep 1 }
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { $null = & runas.exe /trustlevel:0x20000 explorer.exe 2>&1 }   # start the shell without admin rights
            return (New-PDFixResult $true 'Taskbar / desktop / File Explorer पुन्हा सुरू केले.' 'Restarted the taskbar / desktop / File Explorer.' 'Taskbar / desktop / File Explorer फिर शुरू किए।')
        }
        'search' {
            $ok = Restart-PDServiceSafe 'WSearch'
            return (New-PDFixResult $ok 'Windows Search service पुन्हा सुरू केली. 1-2 मिनिटांनी search करून पाहा.' 'Restarted the Windows Search service. Try searching in 1-2 minutes.' 'Windows Search service फिर शुरू की। 1-2 मिनट बाद search करके देखें।')
        }
        'bluetooth' {
            $ok = Restart-PDServiceSafe 'bthserv'
            [void](Restart-PDServiceSafe 'BTAGService')
            return (New-PDFixResult $ok 'Bluetooth service पुन्हा सुरू केली. Device "Remove" करून पुन्हा pair करा.' 'Restarted the Bluetooth service. Remove the device and pair it again.' 'Bluetooth service फिर शुरू की। Device "Remove" करके फिर से pair करें।')
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
            $msgHi = 'WLAN service शुरू की।' + $(if ($en) { " बंद adapters चालू किए: $($en -join ', ')।" } else { '' })
            if (-not $has) { $msg += ' या PC मध्ये WiFi adapter दिसत नाही - driver नाही: "Drivers तपासा".'; $msgEn += ' No WiFi adapter is visible - no driver: "Check drivers".'; $msgHi += ' इस PC में WiFi adapter नहीं दिखता - driver नहीं: "Drivers जाँचें"।'; $ok = $false }
            else { $msg += ' Airplane mode बंद आहे ना आणि keyboard ची WiFi key पाहा.'; $msgEn += ' Check that Airplane mode is off and the keyboard WiFi key.'; $msgHi += ' Airplane mode बंद है न, और keyboard की WiFi key देखें।' }
            return (New-PDFixResult $ok $msg $msgEn $msgHi)
        }
        'usb' {
            $out = (& pnputil.exe /scan-devices 2>&1) -join ' '
            return (New-PDFixResult ($LASTEXITCODE -eq 0) 'नवीन hardware पुन्हा शोधले. Device अजून दिसत नसेल तर दुसरा port / cable वापरा.' 'Scanned for hardware again. If the device still does not show, try another port / cable.' 'नया hardware फिर से खोजा। Device अब भी न दिखे तो दूसरा port / cable लगाएँ।')
        }
        'store' {
            Start-Process -FilePath "$env:WINDIR\System32\wsreset.exe" -ErrorAction SilentlyContinue
            return (New-PDFixResult $true 'Microsoft Store cache reset सुरू केले - काही सेकंदांनी Store आपोआप उघडेल.' 'Started the Microsoft Store cache reset - the Store opens by itself in a few seconds.' 'Microsoft Store cache reset शुरू किया - कुछ सेकंड में Store अपने आप खुलेगा।')
        }
        'dns' {
            $null = & ipconfig.exe /flushdns 2>&1
            try { Clear-DnsClientCache -ErrorAction Stop } catch { }
            return (New-PDFixResult $true 'DNS cache साफ केला. Website पुन्हा उघडून पाहा.' 'Cleared the DNS cache. Open the website again.' 'DNS cache साफ़ किया। Website फिर से खोलकर देखें।')
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
The user describes a PC / laptop problem in Marathi or Hindi (Devanagari or Roman letters) or English. Often it was SPOKEN and turned into text by speech recognition, by people with regional accents or dialects:
expect wrong spellings, Hindi-looking spellings of Marathi words, missing or wrong words (e.g. "पिस्टी" = PC, "माजा" = माझा, "बन्द बरतो" = बंद पडतो). Work out what the person most likely meant.
1. Understand the problem. 2. Pick up to 3 problem ids from the list below that PC Doctor can check or fix (most likely first).
3. Give short practical steps for a non-expert (max 6), in Marathi (Devanagari) and in English.
Set "sure" to false when the text is too garbled or vague to be confident.
Rules: never give commands to type, registry edits, cracks, activators or downloads from unofficial sites; say when a technician / hardware repair is needed.
Reply with ONLY this JSON (no markdown):
{"understood_mr":"...","understood_en":"...","corrected_text":"the user's sentence as they most likely said it, in their language","sure":true,"problem_ids":["..."],"steps_mr":["..."],"steps_en":["..."],"hardware_likely":false,"note_mr":"","note_en":""}
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
            { $_ -in 400, 401, 403 } { L 'The API key is wrong or not enabled' 'API key चुकीची / चालू नाही' 'API key गलत / चालू नहीं' }
            404 { L 'This AI model was not found' 'हे AI model मिळाले नाही' 'यह AI model नहीं मिला' }
            429 { L 'Free quota used up - try again later' 'मोफत मर्यादा संपली - थोड्या वेळाने प्रयत्न करा' 'मुफ़्त सीमा खत्म - थोड़ी देर बाद कोशिश करें' }
            { $_ -ge 500 } { L 'The AI service is unavailable right now' 'AI service सध्या उपलब्ध नाही' 'AI service अभी उपलब्ध नहीं' }
            default { L 'Could not reach the internet / AI service' 'Internet / AI service ला पोहोचता आले नाही' 'Internet / AI service तक नहीं पहुँच सके' }
        }
        throw "$msg [$code]"
    }
}

function Resolve-PDGeminiModel($Config, [scriptblock]$Transport) {
    if ($Config.model) { return $Config.model }
    # remembered for this PC Doctor session (every runspace), so each question does not first list the models
    $memo = [string][AppDomain]::CurrentDomain.GetData('SJGeminiModel')
    if ($memo -and $memo.StartsWith($Config.key + '|')) { return $memo.Substring($Config.key.Length + 1) }
    $txt = & $Transport "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200" @{ 'x-goog-api-key' = $Config.key } $null 'GET'
    $models = @((ConvertFrom-Json $txt).models | Where-Object { $_.supportedGenerationMethods -contains 'generateContent' } | ForEach-Object { $_.name -replace '^models/', '' })
    # newest stable "gemini-<version>-flash" (not lite / preview / image)
    $best = $models | Where-Object { $_ -match '^gemini-(\d+(?:\.\d+)?)-flash$' } | Sort-Object { [double]($_ -replace '^gemini-(\d+(?:\.\d+)?)-flash$', '$1') } -Descending | Select-Object -First 1
    if (-not $best) { $best = $models | Where-Object { $_ -match '^gemini-flash-latest$|flash' -and $_ -notmatch 'lite|image|tts|audio|live' } | Select-Object -First 1 }
    if (-not $best) { throw (L 'No Gemini Flash model is available for this key' 'या key ला कोणतेही Gemini Flash model उपलब्ध नाही' 'इस key के लिए कोई Gemini Flash model उपलब्ध नहीं') }
    [AppDomain]::CurrentDomain.SetData('SJGeminiModel', $Config.key + '|' + $best)
    return $best
}
# Gemini generateContent, fast: "thinking" off (these are short classification / transcription jobs). Models that do not
# accept that setting are asked again without it, and remembered.
function Invoke-PDGemini($Config, [string]$Model, [hashtable]$Body, [scriptblock]$Transport) {
    $url = "https://generativelanguage.googleapis.com/v1beta/models/$($Model):generateContent"
    $h = @{ 'x-goog-api-key' = $Config.key }
    if (-not [AppDomain]::CurrentDomain.GetData('SJNoThinkCfg')) {
        $b2 = @{}; foreach ($k in $Body.Keys) { $b2[$k] = $Body[$k] }
        $gc = @{}; if ($Body.generationConfig) { foreach ($k in $Body.generationConfig.Keys) { $gc[$k] = $Body.generationConfig[$k] } }
        $gc.thinkingConfig = @{ thinkingBudget = 0 }; $b2.generationConfig = $gc
        try { return (& $Transport $url $h (ConvertTo-Json -Depth 10 -Compress -InputObject $b2) 'POST') }
        catch { if ("$($_.Exception.Message)" -notmatch '\[400\]') { throw }; [AppDomain]::CurrentDomain.SetData('SJNoThinkCfg', $true) }
    }
    return (& $Transport $url $h (ConvertTo-Json -Depth 10 -Compress -InputObject $Body) 'POST')
}

function ConvertFrom-PDAiAnswer([string]$Text, [object[]]$Problems) {
    $t = $Text.Trim()
    $t = $t -replace '^```(?:json)?\s*', '' -replace '\s*```$', ''
    $s = $t.IndexOf('{'); $e = $t.LastIndexOf('}')
    if ($s -lt 0 -or $e -le $s) { throw (L 'The AI answer could not be understood' 'AI चे उत्तर समजले नाही' 'AI का जवाब समझ नहीं आया') }
    $j = $t.Substring($s, $e - $s + 1) | ConvertFrom-Json
    $known = @($Problems | ForEach-Object { $_.id })
    [pscustomobject]@{
        UnderstoodMr = [string]$j.understood_mr; UnderstoodEn = [string]$j.understood_en; Corrected = [string]$j.corrected_text
        Sure = $(if ($null -eq $j.sure) { $true } else { [bool]$j.sure })
        ProblemIds = @(@($j.problem_ids) | Where-Object { $_ -in $known } | Select-Object -First 3)    # only ids PC Doctor knows
        StepsMr = @($j.steps_mr | Where-Object { $_ } | Select-Object -First 8); StepsEn = @($j.steps_en | Where-Object { $_ } | Select-Object -First 8)
        Hardware = [bool]$j.hardware_likely; NoteMr = [string]$j.note_mr; NoteEn = [string]$j.note_en
    }
}

function Invoke-PDAiAsk {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)]$Config, [Parameter(Mandatory)][object[]]$Problems,
        [string]$PcInfo, [scriptblock]$Transport)
    if (-not $Config.key) { throw (L 'No AI API key is set (AI settings)' 'AI ची API key सेट केलेली नाही (AI settings)' 'AI की API key सेट नहीं है (AI settings)') }
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
        $txt = Invoke-PDGemini $Config $model @{
            systemInstruction = @{ parts = @(@{ text = $pr.System }) }
            contents = @(@{ role = 'user'; parts = @(@{ text = $userText }) })
            generationConfig = @{ temperature = 0.2; responseMimeType = 'application/json' }
        } $Transport
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
    $notes = @(); $ids = @(); $source = 'basic'; $model = $null; $und = $null; $sure = $false; $cor = ''

    if (-not $Config) { $Config = Get-PDAiConfig $UsbRoot }
    if ($Mode -in 'auto', 'online' -and $Config.key) {
        try {
            Write-PDLog 'Asking the online AI ...' 'STEP'
            $r = Invoke-PDAiAsk -Text $Text -Config $Config -Problems $Problems -PcInfo $PcInfo
            $ids = @($r.ProblemIds); $source = 'online'; $model = $r.Model; $und = $r.UnderstoodEn; $sure = $r.Sure; $cor = $r.Corrected
        } catch { $notes += "online AI: $($_.Exception.Message)" }
    }
    if (-not $ids.Count -and $Mode -in 'auto', 'offline' -and (Get-Command Find-PDLocalAI -ErrorAction SilentlyContinue)) {
        $ai = Find-PDLocalAI $UsbRoot
        if ($ai) {
            $fit = Test-PDLocalAIFit $ai
            if ($fit.Ok) {
                try {
                    Write-PDLog 'Starting the offline AI (30-90 seconds the first time) ...' 'STEP'
                    Set-PDProgress -1 'Offline AI'
                    $r = Invoke-PDLocalAIAsk -Text $Text -Problems $Problems -Ai $ai
                    $ids = @($r.ProblemIds); $source = 'offline'; $model = $r.Model; $und = $r.UnderstoodEn; $sure = $r.Sure; $cor = $r.Corrected
                } catch { $notes += "offline AI: $($_.Exception.Message)" }
            } else { $notes += "offline AI: $($fit.Why)" }
        } elseif ($Mode -eq 'offline') { $notes += 'offline AI is not on this USB (run UPDATE.cmd and answer Y to "offline AI")' }
    }
    # keyword matches always join in as further candidates
    $kw = @(Find-PDProblem -Text $Text -Problems $Problems -Max 3 | ForEach-Object { $_.Problem.id })
    if (-not $ids.Count -and $kw.Count) { $source = 'basic' }
    $all = @($ids + $kw | Select-Object -Unique | Select-Object -First 4)
    foreach ($n in $notes) { Write-PDLog $n 'WARN' }
    # Sure: an AI understood it with confidence (keyword matches alone are never "sure" - the voice asks "did you mean ...?")
    return [pscustomobject]@{ Ids = $all; Source = $source; Model = $model; UnderstoodEn = $und; Corrected = $cor; Sure = [bool]($ids.Count -and $sure); Notes = $notes }
}

Export-ModuleMember -Function Resolve-PDProblemIds, Get-PDProblems, Test-PDKeyword, ConvertTo-PDLoose, Find-PDProblem, Invoke-PDQuickFix, Get-PDAiConfig, Save-PDAiConfig,
    New-PDAiPrompt, ConvertFrom-PDAiAnswer, Invoke-PDAiAsk, Invoke-PDHttpJson, Resolve-PDGeminiModel, Invoke-PDGemini
