# Sanjeevani PC Doctor - offline AI: llama.cpp's llama-server + a small open model (Gemma 4 E2B, Apache-2.0)
# from the USB. Runs only on 127.0.0.1, needs no internet. Used only to understand the user's problem text and
# rank problem ids from PC Doctor's catalog - it never runs anything itself.
Set-StrictMode -Off

# The server outlives a single background job: its port / process id live in the shared $global:PDState.
$script:Local = @{}
function Get-PDAiState { if ($global:PDState) { return $global:PDState } else { return $script:Local } }

function Find-PDLocalAI([string]$UsbRoot) {
    $server = $null; $model = $null
    $ai = Join-Path $UsbRoot 'Tools\AI'
    if (Test-Path -LiteralPath $ai) {
        $server = Get-ChildItem -LiteralPath $ai -Recurse -File -Filter 'llama-server.exe' -Force -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        $model = Get-ChildItem -LiteralPath $ai -Recurse -File -Filter '*.gguf' -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)mmproj' } | Sort-Object Length -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $server -or -not $model) { return $null }
    return [pscustomobject]@{ Server = $server; Model = $model; ModelGB = [math]::Round((Get-Item -LiteralPath $model).Length / 1GB, 1) }
}

# Can this PC run the model? Needs the model size + ~1.5 GB free RAM and a 64-bit CPU with AVX.
function Test-PDLocalAIFit($Ai) {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $need = [math]::Ceiling($Ai.ModelGB + 1.5)
    if ($totalGB -lt $need + 1) { return [pscustomobject]@{ Ok = $false; Why = "RAM $totalGB GB - offline AI needs about $($need + 1) GB" } }
    if ($freeGB -lt $need) { return [pscustomobject]@{ Ok = $false; Why = "only $freeGB GB RAM free - close programs (needs ~$need GB)" } }
    return [pscustomobject]@{ Ok = $true; Why = "RAM $freeGB GB free" }
}

function Get-PDFreePort {
    $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l.Start(); $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}

function Test-PDLocalAIRunning {
    $st = Get-PDAiState
    if (-not $st.LlamaPid) { return $false }
    $p = Get-Process -Id $st.LlamaPid -ErrorAction SilentlyContinue
    return [bool]($p -and $p.ProcessName -match 'llama')
}

function Start-PDLocalAI {
    param([Parameter(Mandatory)]$Ai, [int]$TimeoutSec = 240)
    $st = Get-PDAiState
    if (Test-PDLocalAIRunning) { return [pscustomobject]@{ Port = $st.LlamaPort; Pid = $st.LlamaPid } }
    $port = Get-PDFreePort
    $threads = [math]::Max(2, [Environment]::ProcessorCount - 1)
    $log = Join-Path $env:TEMP 'sanjeevani-llama.log'
    $argList = @('-m', "`"$($Ai.Model)`"", '-c', '4096', '-t', $threads, '--host', '127.0.0.1', '--port', $port)
    $p = Start-Process -FilePath $Ai.Server -ArgumentList $argList -WorkingDirectory (Split-Path $Ai.Server) -WindowStyle Hidden -PassThru -RedirectStandardError $log
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
        if ($p.HasExited) { throw ("offline AI stopped while loading: " + ((Get-Content $log -Tail 3 -ErrorAction SilentlyContinue) -join ' ')) }
        try { $h = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 3; if ($h.StatusCode -eq 200) { $st.LlamaPid = $p.Id; $st.LlamaPort = $port; return [pscustomobject]@{ Port = $port; Pid = $p.Id } } } catch { }
        Start-Sleep -Milliseconds 800
        if ($global:PDState -and $global:PDState.Cancel) { break }
    }
    try { $p.Kill() } catch { }
    throw 'offline AI did not start in time'
}

function Stop-PDLocalAI {
    $st = Get-PDAiState
    if (Test-PDLocalAIRunning) { Stop-Process -Id $st.LlamaPid -Force -ErrorAction SilentlyContinue }
    $st.LlamaPid = $null; $st.LlamaPort = $null
}

function New-PDLocalPrompt([object[]]$Problems) {
    $list = ($Problems | ForEach-Object { "$($_.id): $($_.en.title)" }) -join "`n"
    return @"
You classify computer problems. The user writes in Marathi, Hindi, English or Roman Marathi/Hindi.
Pick the 1 to 3 ids from this list that best match the user's problem, most likely first.
$list
Answer with JSON only: {"problem_ids":["id1","id2"],"understood_en":"one short English sentence"}
"@
}

function Invoke-PDLocalAIAsk {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][object[]]$Problems, $Ai, [scriptblock]$Transport)
    if (-not $Transport) {
        $port = (Start-PDLocalAI -Ai $Ai).Port
        $Transport = { param($body) Invoke-PDHttpJson -Url "http://127.0.0.1:$port/v1/chat/completions" -Headers @{} -Body $body }.GetNewClosure()
    }
    $body = ConvertTo-Json -Depth 6 -Compress -InputObject @{
        messages = @(@{ role = 'system'; content = (New-PDLocalPrompt $Problems) }, @{ role = 'user'; content = $Text })
        temperature = 0.1; max_tokens = 200; response_format = @{ type = 'json_object' }; cache_prompt = $true
        chat_template_kwargs = @{ enable_thinking = $false }
    }
    $t0 = Get-Date
    $txt = & $Transport $body
    $msg = (ConvertFrom-Json $txt).choices[0].message
    $content = if ($msg.content) { [string]$msg.content } else { [string]$msg.reasoning_content }
    $r = ConvertFrom-PDAiAnswer $content $Problems
    $r | Add-Member -NotePropertyName Model -NotePropertyValue ('offline: ' + [IO.Path]::GetFileNameWithoutExtension([string]$(if ($Ai) { $Ai.Model } else { 'model' }))) -Force
    $r | Add-Member -NotePropertyName Seconds -NotePropertyValue ([math]::Round(((Get-Date) - $t0).TotalSeconds, 1)) -Force
    return $r
}

Export-ModuleMember -Function Find-PDLocalAI, Test-PDLocalAIFit, Start-PDLocalAI, Stop-PDLocalAI, Test-PDLocalAIRunning, Invoke-PDLocalAIAsk, New-PDLocalPrompt
