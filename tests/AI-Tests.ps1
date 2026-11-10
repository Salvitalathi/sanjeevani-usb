# Offline AI accuracy check: runs the real llama.cpp server + Gemma model on Windows and asks
# Marathi / Hindi / English / Roman sentences. Used by .github/workflows/ai.yml.
param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Model)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot
$lib = Join-Path $Root 'kit\Sanjeevani\PCDoctor\lib'
foreach ($m in 'Common', 'ToolGuide', 'Ask', 'LocalAI') { Import-Module (Join-Path $lib "$m.psm1") -Force -DisableNameChecking }
$global:PDState = [hashtable]::Synchronized(@{ Progress = -1; Status = ''; Cancel = $false })
$probs = Get-PDProblems (Join-Path $Root 'kit\Sanjeevani\PCDoctor\data')
$ai = [pscustomobject]@{ Server = $Server; Model = $Model; ModelGB = [math]::Round((Get-Item $Model).Length / 1GB, 1) }
Write-Host "Model: $Model ($($ai.ModelGB) GB) - fit: $((Test-PDLocalAIFit $ai).Why)"
$t0 = Get-Date
[void](Start-PDLocalAI -Ai $ai -TimeoutSec 600)
Write-Host ("Server ready in {0:N0} s" -f ((Get-Date) - $t0).TotalSeconds)
$cases = @(
    @('net chalat nahi', 'no-internet'), @('माझ्या laptop मध्ये wifi दिसत नाही', 'wifi'), @('लॅपटॉप खूप गरम होतो', 'overheat'),
    @('printer print नहीं कर रहा', 'printer'), @('मेरे कंप्यूटर में आवाज़ नहीं आ रही', 'sound'), @('computer bahut slow chal raha hai', 'slow-pc'),
    @('C drive भरला आहे, जागा नाही', 'disk-full'), @('नीली स्क्रीन आती है और कंप्यूटर restart हो जाता है', 'bsod'), @('My laptop battery drains very fast', 'battery'),
    @('Windows update atak gaya hai', 'windows-update'), @('taskbar गायब झाला आहे', 'taskbar'), @('pendrive detect nahi ho raha', 'usb'),
    @('popup ads yetat ani browser madhe virus aahe', 'virus|browser'), @('घड्याळात वेळ चुकीची दाखवते', 'time'), @('screen ka resolution kharab hai, sab bada dikhta hai', 'display')
)
$okAi = 0; $okKw = 0; $times = @()
foreach ($c in $cases) {
    $r = Invoke-PDLocalAIAsk -Text $c[0] -Problems $probs -Ai $ai
    $kw = @(Find-PDProblem -Text $c[0] -Problems $probs | ForEach-Object { $_.Problem.id })
    $hitAi = @($r.ProblemIds | Select-Object -First 2) -match "^($($c[1]))$"
    $hitKw = @($kw | Select-Object -First 2) -match "^($($c[1]))$"
    if ($hitAi) { $okAi++ }; if ($hitKw) { $okKw++ }; $times += $r.Seconds
    Write-Host ("{0} AI[{1}] {2,5}s  kw[{3}]  '{4}' -> expected {5} | {6}" -f $(if ($hitAi) { 'OK' } else { 'XX' }), ($r.ProblemIds -join ','), $r.Seconds, ($kw -join ','), $c[0], $c[1], $r.UnderstoodEn)
}
Stop-PDLocalAI
Write-Host ("Offline AI: {0}/{1} correct (top-2), average {2:N1} s per question. Keyword matcher: {3}/{1}." -f $okAi, $cases.Count, (($times | Measure-Object -Average).Average), $okKw)
if ($okAi -lt [math]::Ceiling($cases.Count * 0.7)) { throw "offline AI accuracy too low: $okAi/$($cases.Count)" }
