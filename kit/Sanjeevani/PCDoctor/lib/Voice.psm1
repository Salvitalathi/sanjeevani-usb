# Sanjeevani PC Doctor - the voice of the Assistant ("Sanjeevani").
# Speaking:  Piper (offline neural voices on the USB, female)  ->  Windows' own female voice (OneCore / SAPI).
# Listening: the PC's microphone (winmm, 16 kHz mono, stops by itself after the user stops speaking)
#            -> Gemini (online, when an AI key is set) or whisper.cpp (offline, on the USB).
# Nothing is recorded or kept apart from the one short clip that is turned into text; the clip is deleted afterwards.
Set-StrictMode -Off

# ------------------------------------------------------------------ what Sanjeevani says
$script:Lines = @{
    welcome  = @{ en = 'Welcome to Sanjeevani PC Doctor.'; mr = 'Welcome to Sanjeevani PC Doctor.'; hi = 'Welcome to Sanjeevani PC Doctor.' }
    greet    = @{ en = 'I am Sanjeevani. How can I help you?'; mr = 'मी संजीवनी. आपली काय मदत करू शकते?'; hi = 'मैं संजीवनी हूँ। मैं आपकी क्या मदद कर सकती हूँ?' }
    typeplease = @{ en = 'Please type your problem below and press Enter. I will do my best to solve it.'
                    mr = 'कृपया आपली समस्या खाली type करा आणि Enter दाबा. मी पूर्ण प्रयत्न करून ती सोडवण्याचा प्रयत्न करेन.'
                    hi = 'कृपया अपनी समस्या नीचे type करें और Enter दबाएँ। मैं पूरी कोशिश करके उसे हल करने का प्रयास करूँगी।' }
    nomic    = @{ en = 'Your system has no microphone, so please type your problem. I will do my best to solve it.'
                  mr = 'आपल्या system मध्ये mic सुविधा नसल्याने आपण manually लिहून आपली समस्या सांगा. मी पूर्ण प्रयत्न करून आपली समस्या निराकरण करण्याचा प्रयत्न करेन.'
                  hi = 'आपके system में mic नहीं है, इसलिए अपनी समस्या लिखकर बताइए। मैं पूरी कोशिश करके आपकी समस्या हल करने का प्रयास करूँगी।' }
    ack      = @{ en = 'Okay. I will check what is causing this issue and try to fix it. Please give me a little time.'
                  mr = 'ठीक आहे. मी हा issue कशामुळे आला ते तपासते आणि दूर करण्याचा प्रयत्न करते. मला थोडा वेळ द्या.'
                  hi = 'ठीक है। मैं जाँचती हूँ कि यह issue किस वजह से आया और उसे ठीक करने की कोशिश करती हूँ। मुझे थोड़ा समय दीजिए।' }
    working  = @{ en = 'Please do not switch off the PC while I work.'; mr = 'मी काम करत असताना कृपया PC बंद करू नका.'; hi = 'मैं काम कर रही हूँ, तब तक कृपया PC बंद न करें।' }
    restorept= @{ en = 'First I am creating a restore point, so every change can be undone.'; mr = 'आधी मी restore point बनवते, म्हणजे प्रत्येक बदल परत घेता येईल.'; hi = 'पहले मैं restore point बना रही हूँ, ताकि हर बदलाव वापस लिया जा सके।' }
    checking = @{ en = 'Now checking: {0}.'; mr = 'आता तपासते: {0}.'; hi = 'अब जाँच रही हूँ: {0}.' }
    probing  = @{ en = 'Nothing is visible yet, so I am running a deeper check. This can take a few minutes.'; mr = 'अजून काही दिसले नाही, म्हणून आणखी खोल तपासणी करते. याला काही मिनिटे लागू शकतात.'; hi = 'अभी कुछ नहीं दिखा, इसलिए गहरी जाँच कर रही हूँ। इसमें कुछ मिनट लग सकते हैं।' }
    fixing   = @{ en = 'I found the problem. Fixing it now.'; mr = 'समस्या सापडली. आता दुरुस्त करते.'; hi = 'समस्या मिल गई। अब ठीक कर रही हूँ।' }
    verify   = @{ en = 'Checking again to confirm.'; mr = 'खात्री करण्यासाठी पुन्हा तपासते.'; hi = 'पक्का करने के लिए फिर से जाँच रही हूँ।' }
    refresh  = @{ en = 'Nothing wrong here, I am only refreshing the service as a precaution.'; mr = 'इथे काही चूक नाही, खबरदारी म्हणून फक्त service पुन्हा सुरू करते.'; hi = 'यहाँ कोई गड़बड़ी नहीं, सावधानी के लिए सिर्फ़ service फिर से शुरू कर रही हूँ।' }
    more     = @{ en = 'Do you need any other help?'; mr = 'आपल्याला अजून काही मदत हवी आहे का?'; hi = 'क्या आपको और कोई मदद चाहिए?' }
    bye      = @{ en = 'Thank you! Take care.'; mr = 'धन्यवाद! काळजी घ्या.'; hi = 'धन्यवाद! ध्यान रखिए।' }
    aierr_key   = @{ en = 'There is a problem with the Gemini key, so I could not understand you. Please check the key in AI settings, or type below.'; mr = 'Gemini key मध्ये अडचण आहे, त्यामुळे मला तुमचे बोलणे समजू शकले नाही. कृपया AI settings मध्ये key तपासा, किंवा खाली लिहून सांगा.'; hi = 'Gemini key में दिक्कत है, इसलिए मैं आपकी बात नहीं समझ पाई। कृपया AI settings में key जाँचें, या नीचे लिखकर बताएँ।' }
    aierr_quota = @{ en = 'The free Gemini limit is used up for now. Please speak again in a minute, or type below.'; mr = 'Gemini ची मोफत मर्यादा सध्या संपली आहे. कृपया एका मिनिटाने पुन्हा बोला, किंवा खाली लिहून सांगा.'; hi = 'Gemini की मुफ़्त सीमा अभी खत्म हो गई है। कृपया एक मिनट बाद फिर बोलिए, या नीचे लिखकर बताइए।' }
    aierr_net   = @{ en = 'I cannot reach the internet, so I could not understand your voice. Please check the internet, or type below.'; mr = 'Internet शी जोडणी होत नाही, त्यामुळे मला तुमचा आवाज समजू शकला नाही. कृपया internet तपासा, किंवा खाली लिहून सांगा.'; hi = 'Internet से जुड़ नहीं पा रही, इसलिए आपकी आवाज़ समझ नहीं पाई। कृपया internet जाँचें, या नीचे लिखकर बताइए।' }
    aierr_other = @{ en = 'Gemini did not answer this time. Please say it again.'; mr = 'या वेळी Gemini कडून उत्तर आले नाही. कृपया पुन्हा बोला.'; hi = 'इस बार Gemini से जवाब नहीं आया। कृपया फिर से बोलिए।' }
    nohear   = @{ en = 'I could not hear you. Please say it again.'; mr = 'मला नीट ऐकू आले नाही. कृपया पुन्हा सांगा.'; hi = 'मुझे ठीक से सुनाई नहीं दिया। कृपया फिर से बोलिए।' }
    pressmic = @{ en = 'I did not hear your voice. Please press the mic button and speak.'; mr = 'तुमचा आवाज मला आला नाही. कृपया mic चे button दाबून बोला.'; hi = 'आपकी आवाज़ मुझे नहीं आई। कृपया mic का button दबाकर बोलिए।' }
    thinking = @{ en = 'One moment, let me understand that.'; mr = 'एक क्षण, मी समजून घेते.'; hi = 'एक पल, मैं समझ लेती हूँ।' }
    confirm  = @{ en = 'Did you mean: {0}?'; mr = 'तुम्हाला असे म्हणायचे आहे का: {0}?'; hi = 'क्या आप यह कहना चाहते हैं: {0}?' }
    confirm2 = @{ en = 'Then is it this: {0}?'; mr = 'मग असे आहे का: {0}?'; hi = 'तो क्या यह है: {0}?' }
    sayagain = @{ en = 'Sorry, please tell me the problem once more, in other words.'; mr = 'माफ करा, कृपया समस्या पुन्हा एकदा, दुसऱ्या शब्दांत सांगा.'; hi = 'माफ़ कीजिए, कृपया समस्या एक बार फिर, दूसरे शब्दों में बताइए।' }
    yesno    = @{ en = 'Please say yes or no.'; mr = 'कृपया हो किंवा नाही असे सांगा.'; hi = 'कृपया हाँ या नहीं बोलिए।' }
    checked  = @{ en = 'I checked: {0}.'; mr = 'मी तपासले: {0}.'; hi = 'मैंने जाँचा: {0}.' }
    typeit   = @{ en = 'You can also type your problem below.'; mr = 'आपण खाली समस्या लिहूनही सांगू शकता.'; hi = 'आप नीचे अपनी समस्या लिखकर भी बता सकते हैं।' }
    unclear  = @{ en = 'I did not understand this problem well. Please tell me which part is not working, for example the internet, printer, sound or screen, and what happens.'
                  mr = 'ही समस्या मला नीट समजली नाही. कोणता भाग चालत नाही ते सांगा, उदाहरणार्थ internet, printer, आवाज किंवा screen, आणि काय होते.'
                  hi = 'यह समस्या मुझे ठीक से समझ नहीं आई। बताइए कौन सा हिस्सा नहीं चल रहा, जैसे internet, printer, आवाज़ या screen, और क्या होता है।' }
    busy     = @{ en = 'Another task is still running. I will help you as soon as it finishes.'; mr = 'एक काम अजून चालू आहे. ते संपताच मी मदत करते.'; hi = 'एक काम अभी चल रहा है। वह खत्म होते ही मैं मदद करूँगी।' }
    langswitch = @{ en = 'Sure, let us continue in English.'; mr = 'ठीक आहे, आपण मराठीत बोलूया.'; hi = 'ठीक है, हम हिंदी में बात करते हैं।' }
    nostt    = @{ en = 'To understand speech I need the voice pack on this USB or an online AI key. For now, please type your problem below.'
                  mr = 'बोललेले समजण्यासाठी या USB वर voice pack किंवा online AI key लागते. सध्या कृपया आपली समस्या खाली लिहा.'
                  hi = 'बोली समझने के लिए इस USB पर voice pack या online AI key चाहिए। अभी कृपया अपनी समस्या नीचे लिखें।' }
    micfixed = @{ en = 'Your microphone was turned off; I switched it on.'; mr = 'आपला mic बंद होता; मी तो चालू केला.'; hi = 'आपका mic बंद था; मैंने उसे चालू कर दिया।' }
}
function Get-PDVoiceLine([string]$Key, [string]$Lang = 'mr', [object[]]$Arg) {
    $e = $script:Lines[$Key]; if (-not $e) { return '' }
    $s = $e[$Lang]; if (-not $s) { $s = $e.en }
    if ($Arg) { $s = $s -f $Arg }
    return $s
}
function Get-PDVoiceKeys { return @($script:Lines.Keys) }

# ------------------------------------------------------------------ which language is the user speaking?
# Devanagari: Marathi and Hindi share the script, so common words decide. Roman text: Hinglish / Roman Marathi words.
function Get-PDTextLang([string]$Text) {
    if (-not $Text -or $Text.Trim().Length -lt 2) { return $null }
    $t = ' ' + $Text.ToLowerInvariant() + ' '
    $deva = ([regex]::Matches($Text, '[ऀ-ॿ]')).Count
    $latin = ([regex]::Matches($Text, '[a-zA-Z]')).Count
    $mrW = 'आहे|नाही|माझ्या|माझा|माझी|मला|झाला|झाली|होत|करत|चालत|येत|आणि|पण|काय|कसा|कशी|का\b|हवी|हवे|नको|उघडत|सुरू|बंद\s+पड|लागत|आमच्या|आपल्या|तुम्ही|केले|दिसत|वाजत|ऐकू'
    $hiW = 'है|हैं|नहीं|मेरा|मेरी|मेरे|मुझे|रहा|रही|रहे|में|और|क्या|कैसे|क्यों|चाहिए|हो\s+गया|हो\s+गई|खुल|चल\s+नहीं|आता|आती|सकते|कीजिए|दीजिए|बहुत|लेकिन|था|थी'
    if ($deva -ge 2 -and $deva -ge $latin / 3) {
        $m = ([regex]::Matches($Text, "(?:$mrW)")).Count
        $h = ([regex]::Matches($Text, "(?:$hiW)")).Count
        if ($m -gt $h) { return 'mr' } elseif ($h -gt $m) { return 'hi' } else { return $null }
    }
    if ($latin -lt 2) { return $null }
    $rmr = '\b(ahe|aahe|nahi\s+(chalat|hot|yet|ahe)|majha|maza|majhya|mazya|mala|zala|jhala|zali|hot\s+nahi|chalat|kay|kasa|kashi|ani|pan|havi|nako|ughadat|band\s+padto|yet\s+nahi|tumhi|aaplya|dhanyavad)\b'
    $rhi = '\b(hai|hain|nahi\s+(chal|ho|aa|khul)|nahin|mera|meri|mere|mujhe|raha|rahi|rahe|mein|aur|kya|kaise|kyun|chahiye|ho\s+gaya|ho\s+gayi|khul|bahut|lekin|tha|thi|kijiye|shukriya)\b'
    $ren = '\b(the|is|my|not|working|does|doesn''t|isn''t|please|my|slow|cannot|can''t|won''t|it|this|what|how|thank|thanks|help|computer|laptop)\b'
    $m = ([regex]::Matches($t, $rmr)).Count; $h = ([regex]::Matches($t, $rhi)).Count; $e = ([regex]::Matches($t, $ren)).Count
    $best = [math]::Max([math]::Max([double]$m, [double]$h), [double]$e)
    if ($best -eq 0) { return $null }
    if ($e -eq $best -and $e -gt $m -and $e -gt $h) { return 'en' }
    if ($m -gt $h) { return 'mr' } elseif ($h -gt $m) { return 'hi' } elseif ($e -eq $best) { return 'en' }
    return $null
}

# "no / no thanks / that's all / thank you" ends the conversation; a real new problem does not
function Test-PDGoodbye([string]$Text) {
    if (-not $Text) { return $false }
    $t = ($Text.ToLowerInvariant() -replace '[\.,!?।]', ' ' -replace '\s+', ' ').Trim()
    if ($t.Length -gt 60) { return $false }
    $bye = '^(no|nope|nothing|no thanks?|no thank you|thanks?|thank you|thank you so much|that''s all|that is all|bye|ok bye|okay bye|done|all good|' +
           'नाही|नको|नाही नको|काही नको|काही नाही|नाही धन्यवाद|धन्यवाद|आभार|बस|बस झाले|ठीक आहे धन्यवाद|nahi|nako|kahi nako|kahi nahi|dhanyavad|dhanyawad|bas|' +
           'नहीं|नहीं चाहिए|कुछ नहीं|कुछ नहीं चाहिए|नहीं धन्यवाद|शुक्रिया|बस|बस इतना ही|ठीक है धन्यवाद|nahin|nahi chahiye|kuch nahi|kuchh nahi|shukriya|bas itna hi)( .{0,20})?$'
    if ($t -notmatch $bye) { return $false }
    # "no internet" / "नाही चालत" are problems, not a goodbye
    return ($t -notmatch '(internet|net|wifi|printer|sound|screen|display|चालत|चालू|उघडत|येत|होत|चल|खुल|आ रहा|हो रहा|काम|start|open|work|chalat|chal|khul|ughad|\bhot\b|\byet\b|kaam)')
}

# answers to "did you mean ...?"
function Test-PDYes([string]$Text) {
    $t = ($Text.ToLowerInvariant() -replace '[\.,!?।]', ' ' -replace '\s+', ' ').Trim()
    return ($t -match '^(हो|होय|हो ना|हो हो|हो बरोबर|हा|हां|हाँ|हाँ जी|जी|जी हाँ|हो की|बरोबर|बरोबर आहे|अगदी बरोबर|असेच|हेच|तेच|ठीक|ठीक आहे|ठीक है|चालेल|सही|सही है|बिल्कुल|yes|yeah|yep|yup|ya|haa|ha|haan|ho|hoy|barobar|correct|right|exactly|ok|okay|sure)( .{0,25})?$') -and $t -notmatch '(नाही|नको|नहीं|\bno\b|\bnot\b|nahi)'
}
function Test-PDNo([string]$Text) {
    $t = ($Text.ToLowerInvariant() -replace '[\.,!?।]', ' ' -replace '\s+', ' ').Trim()
    if ($t.Length -gt 40) { return $false }
    return ($t -match '^(नाही|नाय|नको|नहीं|ना|नही|चूक|चुकीचे|गलत|असे नाही|तसे नाही|ऐसा नहीं|no|nope|nah|not that|wrong|nahi|nako|naay)( .{0,25})?$')
}

# ------------------------------------------------------------------ files on the USB
function Get-PDVoiceDirs([string]$UsbRoot) { @((Join-Path $UsbRoot 'Tools\Voice'), (Join-Path $env:LOCALAPPDATA 'Sanjeevani\Voice')) }
function Get-PDVoiceAssets([string]$UsbRoot) {
    $r = [pscustomobject]@{ Piper = $null; Voices = @{}; Whisper = $null; WhisperModel = $null }
    $files = @(foreach ($base in (Get-PDVoiceDirs $UsbRoot)) { if (Test-Path -LiteralPath $base) { Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue } })
    if (-not $files.Count) { return $r }
    $r.Piper = ($files | Where-Object Name -eq 'piper.exe' | Select-Object -First 1).FullName
    foreach ($l in 'en', 'mr', 'hi') {
        $v = $files | Where-Object { $_.Name -match "^$l(_[A-Z]{2})?-.*\.onnx$" -and (Test-Path -LiteralPath ($_.FullName + '.json')) } | Select-Object -First 1
        if ($v) { $r.Voices[$l] = $v.FullName }
    }
    $r.Whisper = ($files | Where-Object { $_.Name -in 'whisper-cli.exe', 'main.exe' } | Sort-Object { $_.Name -ne 'whisper-cli.exe' } | Select-Object -First 1).FullName
    $r.WhisperModel = ($files | Where-Object { $_.Name -match '^ggml-.*\.bin$' } | Sort-Object Length -Descending | Select-Object -First 1).FullName
    return $r
}

# ------------------------------------------------------------------ native helpers (microphone, mute)
$script:NativeSrc = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
namespace SJVoice {
public static class Mic {
    [StructLayout(LayoutKind.Sequential)] struct WAVEFORMATEX { public ushort wFormatTag; public ushort nChannels; public uint nSamplesPerSec; public uint nAvgBytesPerSec; public ushort nBlockAlign; public ushort wBitsPerSample; public ushort cbSize; }
    [StructLayout(LayoutKind.Sequential)] struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength; public uint dwBytesRecorded; public IntPtr dwUser; public uint dwFlags; public uint dwLoops; public IntPtr lpNext; public IntPtr reserved; }
    [DllImport("winmm.dll")] static extern uint waveInGetNumDevs();
    [DllImport("winmm.dll")] static extern uint waveInOpen(out IntPtr h, uint dev, ref WAVEFORMATEX f, IntPtr cb, IntPtr inst, uint flags);
    [DllImport("winmm.dll")] static extern uint waveInPrepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern uint waveInUnprepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern uint waveInAddBuffer(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern uint waveInStart(IntPtr h);
    [DllImport("winmm.dll")] static extern uint waveInReset(IntPtr h);
    [DllImport("winmm.dll")] static extern uint waveInClose(IntPtr h);
    public static volatile float Level;      // 0..1 for the orb animation
    public static volatile bool StopNow;     // the user pressed stop / closed the screen
    public static volatile bool Speaking;    // speech detected in the current recording
    public static int LastPeak, LastMs;      // loudest level and length of the last recording (for the activity log)
    public static int Devices { get { try { return (int)waveInGetNumDevs(); } catch { return 0; } } }

    // Records 16 kHz mono 16-bit into a .wav until the user stops talking.
    // returns "ok", "nospeech", "stopped" or "error:<code>"
    public static string Record(string path, int maxMs, int silenceMs, int noSpeechMs) {
        Level = 0; StopNow = false; Speaking = false; LastPeak = 0; LastMs = 0;
        const int SR = 16000, BUFMS = 100, NBUF = 8;
        int bufBytes = SR * 2 * BUFMS / 1000;
        WAVEFORMATEX f = new WAVEFORMATEX();
        f.wFormatTag = 1; f.nChannels = 1; f.nSamplesPerSec = SR; f.wBitsPerSample = 16; f.nBlockAlign = 2; f.nAvgBytesPerSec = SR * 2; f.cbSize = 0;
        IntPtr h;
        uint rc = waveInOpen(out h, 0xFFFFFFFF, ref f, IntPtr.Zero, IntPtr.Zero, 0);
        if (rc != 0) return "error:" + rc;
        int hsz = Marshal.SizeOf(typeof(WAVEHDR));
        IntPtr[] hdr = new IntPtr[NBUF]; IntPtr[] dat = new IntPtr[NBUF];
        MemoryStream pcm = new MemoryStream();
        string result = "ok";
        try {
            for (int i = 0; i < NBUF; i++) {
                dat[i] = Marshal.AllocHGlobal(bufBytes);
                hdr[i] = Marshal.AllocHGlobal(hsz);
                WAVEHDR w = new WAVEHDR(); w.lpData = dat[i]; w.dwBufferLength = (uint)bufBytes;
                Marshal.StructureToPtr(w, hdr[i], false);
                waveInPrepareHeader(h, hdr[i], (uint)hsz);
                waveInAddBuffer(h, hdr[i], (uint)hsz);
            }
            waveInStart(h);
            int elapsed = 0, silent = 0, voiced = 0, idx = 0; double floor = -1, peak = 0;
            byte[] tmp = new byte[bufBytes];
            while (true) {
                WAVEHDR w = (WAVEHDR)Marshal.PtrToStructure(hdr[idx], typeof(WAVEHDR));
                if ((w.dwFlags & 1) == 0) {   // WHDR_DONE not yet
                    Thread.Sleep(10);
                    if (StopNow) { result = "stopped"; break; }
                    continue;
                }
                int n = (int)w.dwBytesRecorded;
                Marshal.Copy(dat[idx], tmp, 0, n);
                pcm.Write(tmp, 0, n);
                double sum = 0; int cnt = n / 2;
                for (int k = 0; k + 1 < n; k += 2) { short s = (short)(tmp[k] | (tmp[k + 1] << 8)); sum += (double)s * s; }
                double rms = cnt > 0 ? Math.Sqrt(sum / cnt) : 0;
                elapsed += BUFMS;
                // background level: drops fast, rises slowly (so steady room noise is learned, speech is not)
                if (floor < 0) floor = rms;
                else if (rms < floor) floor = floor * 0.6 + rms * 0.4;
                else if (!Speaking || rms < floor * 2) floor = floor * 0.985 + rms * 0.015;
                double thr = Math.Max(380, floor * 2.4);
                if (rms > peak) peak = rms;
                LastPeak = (int)peak; LastMs = elapsed;
                Level = (float)Math.Min(1.0, rms / (thr * 3));
                if (elapsed > 300) {
                    // end of speech: back near the room level, or far below the loudest part of what was said
                    double endThr = Math.Max(thr * 0.8, Speaking ? peak * 0.12 : 0);
                    if (rms > thr) { voiced++; silent = 0; if (voiced >= 2) Speaking = true; }
                    else if (Speaking && rms < endThr) { silent += BUFMS; }
                    else if (!Speaking) { voiced = 0; }
                    else { silent += BUFMS / 2; }
                }
                // re-queue the buffer
                w.dwFlags = 0; w.dwBytesRecorded = 0;
                waveInUnprepareHeader(h, hdr[idx], (uint)hsz);
                Marshal.StructureToPtr(w, hdr[idx], false);
                waveInPrepareHeader(h, hdr[idx], (uint)hsz);
                waveInAddBuffer(h, hdr[idx], (uint)hsz);
                idx = (idx + 1) % NBUF;
                if (StopNow) { result = Speaking ? "ok" : "stopped"; break; }
                if (Speaking && silent >= silenceMs) break;
                if (!Speaking && elapsed >= noSpeechMs) { result = "nospeech"; break; }
                if (elapsed >= maxMs) { if (!Speaking) result = "nospeech"; break; }
            }
        } finally {
            waveInReset(h);
            for (int i = 0; i < NBUF; i++) { if (hdr[i] != IntPtr.Zero) { waveInUnprepareHeader(h, hdr[i], (uint)hsz); Marshal.FreeHGlobal(hdr[i]); } if (dat[i] != IntPtr.Zero) Marshal.FreeHGlobal(dat[i]); }
            waveInClose(h);
            Level = 0;
        }
        if (result == "ok") WriteWav(path, pcm.ToArray(), SR);
        return result;
    }
    static void WriteWav(string path, byte[] data, int sr) {
        using (BinaryWriter b = new BinaryWriter(File.Create(path))) {
            b.Write(new char[] { 'R', 'I', 'F', 'F' }); b.Write(36 + data.Length); b.Write(new char[] { 'W', 'A', 'V', 'E' });
            b.Write(new char[] { 'f', 'm', 't', ' ' }); b.Write(16); b.Write((short)1); b.Write((short)1); b.Write(sr); b.Write(sr * 2); b.Write((short)2); b.Write((short)16);
            b.Write(new char[] { 'd', 'a', 't', 'a' }); b.Write(data.Length); b.Write(data);
        }
    }
}

// default microphone: is there one, is it muted, unmute it (Windows Core Audio)
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IntPtr col); [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    [PreserveSig] int RegisterControlChangeNotify(IntPtr p); [PreserveSig] int UnregisterControlChangeNotify(IntPtr p); [PreserveSig] int GetChannelCount(out uint c);
    [PreserveSig] int SetMasterVolumeLevel(float l, ref Guid ctx); [PreserveSig] int SetMasterVolumeLevelScalar(float l, ref Guid ctx);
    [PreserveSig] int GetMasterVolumeLevel(out float l); [PreserveSig] int GetMasterVolumeLevelScalar(out float l);
    [PreserveSig] int SetChannelVolumeLevel(uint ch, float l, ref Guid ctx); [PreserveSig] int SetChannelVolumeLevelScalar(uint ch, float l, ref Guid ctx);
    [PreserveSig] int GetChannelVolumeLevel(uint ch, out float l); [PreserveSig] int GetChannelVolumeLevelScalar(uint ch, out float l);
    [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx); [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}
public static class Endpoint {
    static IAudioEndpointVolume Get(int flow) {
        IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCo());
        IMMDevice dev; if (en.GetDefaultAudioEndpoint(flow, 0, out dev) != 0 || dev == null) return null;
        Guid iid = typeof(IAudioEndpointVolume).GUID; object o;
        if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return null;
        return (IAudioEndpointVolume)o;
    }
    public static bool HasDefault(int flow) { try { return Get(flow) != null; } catch { return false; } }
    // flow: 0 = speakers, 1 = microphone. Returns "none", "ok", or "fixed" (was muted / almost silent)
    public static string Ensure(int flow, float minLevel) {
        try {
            IAudioEndpointVolume v = Get(flow); if (v == null) return "none";
            Guid g = Guid.Empty; bool mute; float lvl; string r = "ok";
            if (v.GetMute(out mute) == 0 && mute) { v.SetMute(false, ref g); r = "fixed"; }
            if (v.GetMasterVolumeLevelScalar(out lvl) == 0 && lvl < minLevel) { v.SetMasterVolumeLevelScalar(minLevel, ref g); r = "fixed"; }
            return r;
        } catch { return "none"; }
    }
}
}
'@
function Initialize-PDVoiceNative {
    if ('SJVoice.Mic' -as [type]) { return $true }
    try { Add-Type -TypeDefinition $script:NativeSrc -Language CSharp -ErrorAction Stop; return $true } catch { Write-PDLog "voice: native helper failed: $($_.Exception.Message)" 'WARN'; return $false }
}

# Is there a microphone that can be used? Turns it on when it is muted / blocked in the privacy settings.
# Returns @{ Has = bool; Fixed = bool }
function Enable-PDMicrophone {
    $res = [pscustomobject]@{ Has = $false; Fixed = $false }
    if (-not (Initialize-PDVoiceNative)) { return $res }
    # privacy: "let desktop apps use the microphone"
    $i = 0
    foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone',
                   'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged',
                   'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone') {
        try {
            if ((Get-ItemProperty -Path $k -Name Value -ErrorAction SilentlyContinue).Value -eq 'Deny') {
                $i++; $bak = Save-PDRegTree -Key $k -Name "mic-privacy-$i"
                Add-PDUndo @{ Type = 'RegTree'; File = $bak; Label = 'Microphone privacy' }
                Set-ItemProperty -Path $k -Name Value -Value 'Allow' -ErrorAction Stop
                $res.Fixed = $true
                Write-PDLog "voice: microphone was blocked in privacy settings ($k) - allowed" 'OK'
            }
        } catch { }
    }
    if ([SJVoice.Mic]::Devices -lt 1 -or -not [SJVoice.Endpoint]::HasDefault(1)) { return $res }
    $res.Has = $true
    if ([SJVoice.Endpoint]::Ensure(1, [single]0.6) -eq 'fixed') { $res.Fixed = $true; Write-PDLog 'voice: microphone was muted / too low - turned on' 'OK' }
    [void][SJVoice.Endpoint]::Ensure(0, [single]0.35)      # speakers: so the user hears Sanjeevani
    return $res
}

function Invoke-PDRecord([string]$Path, [int]$MaxMs = 15000, [int]$SilenceMs = 1300, [int]$NoSpeechMs = 7000) {
    if (-not (Initialize-PDVoiceNative)) { return 'error:native' }
    return [SJVoice.Mic]::Record($Path, $MaxMs, $SilenceMs, $NoSpeechMs)
}

# ------------------------------------------------------------------ speaking
function ConvertTo-PDSpeakable([string]$Text) {
    $t = $Text -replace '[✔✓↻⚠•ℹ►▶]', '' -replace '\s*->\s*', ', ' -replace '\(\s*\)', ''
    $t = $t -replace '\b([A-Z]):(?=\s+drive)', '$1' -replace '\b([A-Z]):(?=\s|$|[,.;])', '$1 drive' -replace '(\d+)\s*%', '$1 percent' -replace '\s{2,}', ' '
    return $t.Trim()
}
# Devanagari -> Roman letters, so an English (India) voice can still say Marathi / Hindi when no Indian-language voice exists
$script:RomV = @{ 'अ' = 'a'; 'आ' = 'aa'; 'इ' = 'i'; 'ई' = 'ee'; 'उ' = 'u'; 'ऊ' = 'oo'; 'ऋ' = 'ru'; 'ए' = 'e'; 'ऐ' = 'ai'; 'ओ' = 'o'; 'औ' = 'au'; 'ऑ' = 'o'; 'ॲ' = 'ae' }
$script:RomM = @{ 'ा' = 'aa'; 'ि' = 'i'; 'ी' = 'ee'; 'ु' = 'u'; 'ू' = 'oo'; 'ृ' = 'ru'; 'े' = 'e'; 'ै' = 'ai'; 'ो' = 'o'; 'ौ' = 'au'; 'ॉ' = 'o'; 'ॅ' = 'ae' }
$script:RomC = @{ 'क' = 'k'; 'ख' = 'kh'; 'ग' = 'g'; 'घ' = 'gh'; 'ङ' = 'ng'; 'च' = 'ch'; 'छ' = 'chh'; 'ज' = 'j'; 'झ' = 'jh'; 'ञ' = 'ny'; 'ट' = 't'; 'ठ' = 'th'; 'ड' = 'd'; 'ढ' = 'dh'; 'ण' = 'n'
    'त' = 't'; 'थ' = 'th'; 'द' = 'd'; 'ध' = 'dh'; 'न' = 'n'; 'प' = 'p'; 'फ' = 'ph'; 'ब' = 'b'; 'भ' = 'bh'; 'म' = 'm'; 'य' = 'y'; 'र' = 'r'; 'ल' = 'l'; 'ळ' = 'l'; 'व' = 'v'; 'श' = 'sh'; 'ष' = 'sh'; 'स' = 's'; 'ह' = 'h' }
function ConvertTo-PDRoman([string]$Text) {
    $sb = New-Object Text.StringBuilder
    foreach ($word in ($Text -split '(\s+)')) {
        if ($word -notmatch '[\u0900-\u097F]') { [void]$sb.Append($word); continue }
        $w = New-Object Text.StringBuilder
        $ch = $word.ToCharArray()
        for ($i = 0; $i -lt $ch.Length; $i++) {
            $c = [string]$ch[$i]; $n = if ($i + 1 -lt $ch.Length) { [string]$ch[$i + 1] } else { '' }
            $before = $w.ToString()
            if ($n -eq '़') { $c = @{ 'क' = 'q'; 'ख' = 'kh'; 'ग' = 'g'; 'ज' = 'z'; 'फ' = 'f'; 'ड' = 'r'; 'ढ' = 'rh' }[$c]; $i++; $n = if ($i + 1 -lt $ch.Length) { [string]$ch[$i + 1] } else { '' }; [void]$w.Append($c) }
            elseif ($script:RomC.ContainsKey($c)) { [void]$w.Append($script:RomC[$c]) }
            elseif ($script:RomV.ContainsKey($c)) { [void]$w.Append($script:RomV[$c]); continue }
            elseif ($c -eq 'ं' -or $c -eq 'ँ') { [void]$w.Append('n'); continue }
            elseif ($c -eq 'ः') { [void]$w.Append('h'); continue }
            elseif ($c -eq '्' -or $script:RomM.ContainsKey($c)) { if ($script:RomM.ContainsKey($c)) { [void]$w.Append($script:RomM[$c]) }; continue }
            elseif ($c -eq '।') { [void]$w.Append('.'); continue }
            else { [void]$w.Append($c); continue }
            # a consonant: its own vowel comes from the next sign; none = inherent "a" (dropped at the end of a word)
            if ($n -eq '्') { $i++; continue }
            if ($script:RomM.ContainsKey($n)) { continue }
            $last = ($i + 1 -ge $ch.Length) -or ($n -notmatch '[\u0900-\u097F]')
            if ($last) { if ($w.Length -le 2) { [void]$w.Append('a') }; continue }
            # "C a C V" in the middle of a word: the "a" is not spoken (आपली = aaplee, करतो = karto)
            $n2 = if ($i + 2 -lt $ch.Length) { [string]$ch[$i + 2] } else { '' }
            $drop = $before.Length -gt 0 -and $before -match '[aeiou]$' -and $script:RomC.ContainsKey($n) -and $script:RomM.ContainsKey($n2)
            if (-not $drop) { [void]$w.Append('a') }
        }
        [void]$sb.Append($w.ToString())
    }
    return $sb.ToString()
}

# Gemini's own text-to-speech (the same natural voices as Google's assistants) - only with the user's key.
function New-PDSpeechGemini([string]$Text, [string]$Out, $Cfg) {
    $off = [AppDomain]::CurrentDomain.GetData('SJTtsOff')
    if ($off -and ([datetime]$off) -gt (Get-Date)) { return $false }
    try {
        $tr = { param($u, $h, $b, $m) Invoke-PDHttpJson -Url $u -Headers $h -Body $b -Method $m }
        $model = [AppDomain]::CurrentDomain.GetData('SJTtsModel')
        if (-not $model) {
            $model = 'gemini-2.5-flash-preview-tts'
            try {
                $lst = & $tr 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=200' @{ 'x-goog-api-key' = $Cfg.key } $null 'GET'
                $names = @((ConvertFrom-Json $lst).models | ForEach-Object { $_.name -replace '^models/', '' } | Where-Object { $_ -match 'tts' -and $_ -match 'flash' })
                if ($names.Count) { $model = $names | Sort-Object { [double](([regex]::Match($_, '\d+(\.\d+)?')).Value) } -Descending | Select-Object -First 1 }
            } catch { }
            [AppDomain]::CurrentDomain.SetData('SJTtsModel', $model)
        }
        $body = ConvertTo-Json -Depth 10 -Compress -InputObject @{
            contents = @(@{ parts = @(@{ text = $Text }) })
            generationConfig = @{ responseModalities = @('AUDIO'); speechConfig = @{ voiceConfig = @{ prebuiltVoiceConfig = @{ voiceName = 'Kore' } } } }
        }
        $txt = & $tr "https://generativelanguage.googleapis.com/v1beta/models/$($model):generateContent" @{ 'x-goog-api-key' = $Cfg.key } $body 'POST'
        $j = ConvertFrom-Json $txt
        $part = @(@($j.candidates)[0].content.parts | Where-Object { $_.inlineData })[0]
        if (-not $part) { return $false }
        $pcm = [Convert]::FromBase64String($part.inlineData.data)
        $rate = 24000; if ($part.inlineData.mimeType -match 'rate=(\d+)') { $rate = [int]$Matches[1] }
        $fs = [IO.File]::Create($Out); $bw = New-Object IO.BinaryWriter $fs
        $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $pcm.Length)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
        $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$rate); $bw.Write([int]($rate * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
        $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$pcm.Length); $bw.Write($pcm); $bw.Close()
        return ((Get-Item -LiteralPath $Out).Length -gt 2000)
    } catch {
        $msg = "$($_.Exception.Message)"
        Write-PDLog "voice: online voice not available: $msg" 'WARN'
        # free keys allow only a few voice requests (per minute and per day): when used up, the offline voice speaks for the rest of the session instead of switching back and forth
        [AppDomain]::CurrentDomain.SetData('SJTtsOff', (Get-Date).AddSeconds($(if ($msg -match '\[429\]') { 1200 } else { 300 })))
        return $false
    }
}

# English words inside Marathi / Hindi sentences, written the way an Indian speaker says them
$script:SpokenWords = [ordered]@{
    'restore point' = 'रिस्टोअर पॉइंट'; 'one-click optimize' = 'वन क्लिक ऑप्टिमाइझ'; 'sanjeevani' = 'संजीवनी'; 'pc doctor' = 'पीसी डॉक्टर'; 'doctor' = 'डॉक्टर'
    'laptop' = 'लॅपटॉप'; 'computer' = 'कॉम्प्युटर'; 'pc' = 'पीसी'; 'internet' = 'इंटरनेट'; 'wifi' = 'वायफाय'; 'wi-fi' = 'वायफाय'; 'printer' = 'प्रिंटर'; 'print' = 'प्रिंट'
    'screen' = 'स्क्रीन'; 'display' = 'डिस्प्ले'; 'battery' = 'बॅटरी'; 'charger' = 'चार्जर'; 'virus' = 'व्हायरस'; 'antivirus' = 'अँटीव्हायरस'; 'defender' = 'डिफेंडर'
    'restart' = 'रिस्टार्ट'; 'mic' = 'माइक'; 'button' = 'बटण'; 'enter' = 'एंटर'; 'type' = 'टाइप'; 'windows' = 'विंडोज'; 'update' = 'अपडेट'; 'updates' = 'अपडेट्स'
    'driver' = 'ड्रायव्हर'; 'drivers' = 'ड्रायव्हर्स'; 'service' = 'सर्व्हिस'; 'services' = 'सर्व्हिसेस'; 'issue' = 'इश्यू'; 'gemini' = 'जेमिनी'; 'key' = 'की'
    'settings' = 'सेटिंग्ज'; 'online' = 'ऑनलाइन'; 'offline' = 'ऑफलाइन'; 'ai' = 'एआय'; 'disk' = 'डिस्क'; 'drive' = 'ड्राइव्ह'; 'ram' = 'रॅम'; 'cpu' = 'सीपीयू'
    'ssd' = 'एसएसडी'; 'hdd' = 'एचडीडी'; 'file' = 'फाइल'; 'files' = 'फाइल्स'; 'folder' = 'फोल्डर'; 'usb' = 'यूएसबी'; 'pendrive' = 'पेनड्राइव्ह'; 'scan' = 'स्कॅन'
    'quick scan' = 'क्विक स्कॅन'; 'power plan' = 'पॉवर प्लॅन'; 'power' = 'पॉवर'; 'plan' = 'प्लॅन'; 'junk' = 'जंक'; 'startup' = 'स्टार्टअप'; 'programs' = 'प्रोग्राम्स'
    'program' = 'प्रोग्राम'; 'app' = 'ॲप'; 'apps' = 'ॲप्स'; 'software' = 'सॉफ्टवेअर'; 'hardware' = 'हार्डवेअर'; 'system' = 'सिस्टम'; 'blue screen' = 'ब्लू स्क्रीन'
    'bluetooth' = 'ब्लूटूथ'; 'camera' = 'कॅमेरा'; 'keyboard' = 'कीबोर्ड'; 'mouse' = 'माउस'; 'touchpad' = 'टचपॅड'; 'fan' = 'फॅन'; 'cache' = 'कॅशे'; 'proxy' = 'प्रॉक्सी'
    'network' = 'नेटवर्क'; 'router' = 'राउटर'; 'cable' = 'केबल'; 'speed' = 'स्पीड'; 'slow' = 'स्लो'; 'ok' = 'ओके'; 'okay' = 'ओके'; 'manually' = 'मॅन्युअली'
    'dns' = 'डीएनएस'; 'ip' = 'आयपी'; 'sfc' = 'एसएफसी'; 'dism' = 'डिझम'; 'gb' = 'जीबी'; 'mb' = 'एमबी'; 'percent' = 'टक्के'; 'thermal paste' = 'थर्मल पेस्ट'
    'heatsink' = 'हीटसिंक'; 'registry' = 'रजिस्ट्री'; 'task manager' = 'टास्क मॅनेजर'; 'welcome' = 'वेलकम'; 'to' = 'टू'; 'sorry' = 'सॉरी'; 'please' = 'प्लीज'
}
function ConvertTo-PDIndianSpeech([string]$Text) {
    $t = $Text
    foreach ($k in @($script:SpokenWords.Keys | Sort-Object Length -Descending)) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z])' + [regex]::Escape($k) + '(?![A-Za-z])', $script:SpokenWords[$k]) }
    return $t
}

# Writes the sentence as a .wav. Returns the engine used, or $null. Good recordings are cached on this PC, so a sentence
# said once with the online voice is said the same way later, even offline.
# Sentences said once with the online (Gemini) voice are kept on the pendrive (else on this PC), so they are said in
# the same natural voice later - on any PC, even offline, without using the key's small free limit again.
function Get-PDVoiceCachePath([string]$UsbRoot, [string]$Lang, [string]$Text) {
    $sha = [Security.Cryptography.SHA1]::Create()
    $key = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("v4|$Lang|$Text")) | ForEach-Object { $_.ToString('x2') })
    foreach ($d in @((Join-Path $UsbRoot 'Sanjeevani\voice-cache'), (Join-Path $env:LOCALAPPDATA 'Sanjeevani\voice-cache'))) {
        if (Test-Path -LiteralPath (Join-Path $d "$key.wav")) { return (Join-Path $d "$key.wav") }
    }
    $d = Join-Path $UsbRoot 'Sanjeevani\voice-cache'
    try { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null; $t = Join-Path $d '.w'; [IO.File]::WriteAllText($t, 'x'); Remove-Item -LiteralPath $t -Force } catch { $d = Join-Path $env:LOCALAPPDATA 'Sanjeevani\voice-cache' }
    return (Join-Path $d "$key.wav")
}
# The Piper engine for Windows (2023) reads only one-letter sounds; newer voice files also list combined sounds
# ("aɪ"). Those entries are dropped (a backup of the original is kept) - the engine then uses the single letters.
function Repair-PDPiperConfig([string]$Json) {
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $ser.MaxJsonLength = 64MB
        $raw = [IO.File]::ReadAllText($Json, [Text.Encoding]::UTF8)
        $cfg = $ser.DeserializeObject($raw)
        $map = $cfg['phoneme_id_map']
        if (-not $map) { return $false }
        $drop = @($map.Keys | Where-Object { ($_.ToCharArray() | Where-Object { -not [char]::IsLowSurrogate($_) }).Count -ne 1 })
        if (-not $drop.Count) { return $false }
        foreach ($k in $drop) { [void]$map.Remove($k) }
        if (-not (Test-Path -LiteralPath ($Json + '.orig'))) { Copy-Item -LiteralPath $Json -Destination ($Json + '.orig') -Force }
        [IO.File]::WriteAllText($Json, $ser.Serialize($cfg), (New-Object Text.UTF8Encoding $false))
        Write-PDLog ("voice: made " + (Split-Path $Json -Leaf) + " compatible (" + $drop.Count + " combined sounds)") 'INFO'
        return $true
    } catch { Write-PDLog "voice: could not adapt the voice file: $($_.Exception.Message)" 'WARN'; return $false }
}
function New-PDSpeech {
    param([string]$Text, [string]$Lang = 'mr', [string]$Out, [string]$UsbRoot, [string]$Mode = 'auto')
    $Text = ConvertTo-PDSpeakable $Text
    if (-not $Text) { return $null }
    $cached = Get-PDVoiceCachePath $UsbRoot $Lang $Text
    if (Test-Path -LiteralPath $cached) { try { Copy-Item -LiteralPath $cached -Destination $Out -Force; return 'cache' } catch { } }
    $keep = { try { New-Item -ItemType Directory -Path (Split-Path $cached) -Force | Out-Null; Copy-Item -LiteralPath $Out -Destination $cached -Force } catch { } }
    # one voice for the whole conversation: the Indian female Piper voice (Marathi; the Hindi "Priyamvada" voice also reads Marathi)
    $a = Get-PDVoiceAssets $UsbRoot
    $voices = @(@($a.Voices[$Lang]) + @($(if ($Lang -eq 'mr') { $a.Voices['hi'] })) | Where-Object { $_ })
    if ($voices.Count -and $Lang -ne 'en') { $Text = ConvertTo-PDIndianSpeech $Text }
    if ($a.Piper) {
        foreach ($voice in $voices) {
          for ($try = 0; $try -lt 2; $try++) {
            try {
                Remove-Item -LiteralPath $Out -Force -ErrorAction SilentlyContinue
                $psi = New-Object Diagnostics.ProcessStartInfo $a.Piper
                $psi.Arguments = "--model `"$voice`" --output_file `"$Out`" --sentence_silence 0.25"
                $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
                $psi.WorkingDirectory = Split-Path $a.Piper
                $p = [Diagnostics.Process]::Start($psi)
                $b = [Text.Encoding]::UTF8.GetBytes(($Text -replace "`r?`n", ' ') + "`n")
                $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.Close()
                $err = $p.StandardError.ReadToEnd()
                if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch { } }
                if ((Test-Path -LiteralPath $Out) -and (Get-Item -LiteralPath $Out).Length -gt 2000) { & $keep; return 'piper' }
                # newer voices list multi-letter sounds ("aɪ") the Windows Piper engine cannot read: make the voice file compatible once, then retry
                if ($try -eq 0 -and $err -match 'not a single codepoint' -and (Repair-PDPiperConfig ($voice + '.json'))) { continue }
                Write-PDLog ("voice: piper could not use " + (Split-Path $voice -Leaf) + ': ' + $(if ($err.Length -gt 200) { $err.Substring($err.Length - 200) } else { $err })) 'WARN'
            } catch { Write-PDLog "voice: piper failed: $($_.Exception.Message)" 'WARN' }
            break
          }
        }
    }
    $cfg = Get-PDAiConfig $UsbRoot
    if ($Mode -in 'auto', 'online' -and $cfg.key -and $cfg.provider -ne 'claude') {
        if (New-PDSpeechGemini $Text $Out $cfg) { & $keep; return 'online' }
    }
    if (New-PDSpeechWinRT $Text $Lang $Out) { return 'windows' }
    # no Marathi / Hindi voice on this Windows: an English (India) voice reads the sentence in Roman letters
    if ($Text -match '[\u0900-\u097F]') {
        $rom = ConvertTo-PDRoman $Text
        if (New-PDSpeechWinRT $rom 'en' $Out) { return 'windows-roman' }
        if (New-PDSpeechSapi $rom 'en' $Out) { return 'sapi-roman' }
        return $null
    }
    if (New-PDSpeechSapi $Text $Lang $Out) { return 'sapi' }
    return $null
}
# Windows 10/11 voices (e.g. Microsoft Kalpana - Hindi, Heera - English India, Zira); Marathi text is read by a Hindi voice
function New-PDSpeechWinRT([string]$Text, [string]$Lang, [string]$Out) {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
        $all = @([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices)
        $want = switch ($Lang) { 'mr' { 'mr-*', 'hi-*' } 'hi' { 'hi-*' } default { 'en-IN', 'en-*' } }
        $v = $null
        foreach ($w in $want) { $v = $all | Where-Object { $_.Language -like $w -and [string]$_.Gender -eq 'Female' } | Select-Object -First 1; if ($v) { break } }
        if (-not $v) { foreach ($w in $want) { $v = $all | Where-Object { $_.Language -like $w } | Select-Object -First 1; if ($v) { break } } }
        if (-not $v) { return $false }
        $s = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
        $s.Voice = $v
        $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
        $task = $asTask.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null, @($s.SynthesizeTextToStreamAsync($Text)))
        if (-not $task.Wait(30000)) { return $false }
        $ns = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($task.Result)
        $fs = [IO.File]::Create($Out); $ns.CopyTo($fs); $fs.Close(); $ns.Dispose()
        return ((Get-Item -LiteralPath $Out).Length -gt 2000)
    } catch { return $false }
}
function New-PDSpeechSapi([string]$Text, [string]$Lang, [string]$Out) {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $vs = @($s.GetInstalledVoices() | Where-Object Enabled | ForEach-Object VoiceInfo)
        $want = switch ($Lang) { 'mr' { 'mr', 'hi' } 'hi' { 'hi' } default { 'en' } }
        $v = $null
        foreach ($w in $want) { $v = $vs | Where-Object { $_.Culture.TwoLetterISOLanguageName -eq $w } | Sort-Object { [string]$_.Gender -ne 'Female' } | Select-Object -First 1; if ($v) { break } }
        if (-not $v) { if ($Text -match '[ऀ-ॿ]') { $s.Dispose(); return $false }; $v = $vs | Sort-Object { [string]$_.Gender -ne 'Female' } | Select-Object -First 1 }
        if (-not $v) { $s.Dispose(); return $false }
        $s.SelectVoice($v.Name); $s.Rate = 0
        $s.SetOutputToWaveFile($Out); $s.Speak($Text); $s.SetOutputToNull(); $s.Dispose()
        return ((Get-Item -LiteralPath $Out).Length -gt 2000)
    } catch { return $false }
}

# ------------------------------------------------------------------ listening: speech -> text
# Online (Gemini, the user's own key) when allowed; otherwise whisper.cpp on the USB. Returns @{ Text; Source; Error }
function ConvertFrom-PDSpeech {
    param([string]$Wav, [string]$Lang = 'mr', [string]$UsbRoot, [string]$Mode = 'auto', [scriptblock]$Transport, [object[]]$Problems)
    # U: when the problem list is given, the same online call also understands the problem (one round trip instead of two)
    $res = [pscustomobject]@{ Text = ''; Source = ''; Error = ''; U = $null }
    $cfg = Get-PDAiConfig $UsbRoot
    if ($Mode -in 'auto', 'online' -and $cfg.key -and $cfg.provider -ne 'claude') {
        try {
            if (-not $Transport) { $Transport = { param($u, $h, $b, $m) Invoke-PDHttpJson -Url $u -Headers $h -Body $b -Method $m } }
            $model = Resolve-PDGeminiModel $cfg $Transport
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Wav))
            $prompt = 'Transcribe this short recording. A person in India is talking to "Sanjeevani", a PC repair assistant - usually describing a computer / laptop problem, or answering yes / no. ' +
                      'The language is Marathi, Hindi or English, often mixed with English computer words (PC, laptop, internet, WiFi, printer, screen, battery, virus). ' +
                      'The speaker may have a strong rural accent or unclear pronunciation: write what they most likely meant, in correct spelling. ' +
                      'Write Marathi and Hindi in Devanagari, English words in English letters. Reply with only the words that were spoken; reply with nothing if nobody speaks.'
            if ($Problems) {
                $list = ($Problems | ForEach-Object { "$($_.id): $($_.en.title)" }) -join '; '
                $prompt += " Then, if it describes a PC problem, pick up to 3 matching ids from this list, most likely first: $list. " +
                           ' If the person is NOT describing a PC problem (a greeting, "how are you", "who are you", small talk or a general question), leave problem_ids empty and put in "reply" a short, warm spoken answer as Sanjeevani (a friendly female assistant), in the SAME language the person used (Marathi / Hindi in Devanagari), max 2 short sentences, ending by offering help with their computer. Otherwise "reply" is empty. ' +
                           'Answer as JSON: {"text": "<the words>", "language": "mr|hi|en", "clear": true|false, "problem_ids": ["..."], "sure": true|false, "understood_en": "<one short sentence>", "reply": ""} - ' +
                           '"clear" is false when the speech could not be made out; "sure" is false when you are guessing the problem; problem_ids is empty for yes / no / thanks.'
            } else {
                $prompt += ' Answer as JSON: {"text": "<the words>", "language": "mr|hi|en", "clear": true|false} - "clear" is false when the speech could not be made out.'
            }
            $txt = Invoke-PDGemini $cfg $model @{ contents = @(@{ parts = @(@{ text = $prompt }, @{ inline_data = @{ mime_type = 'audio/wav'; data = $b64 } }) }); generationConfig = @{ temperature = 0; responseMimeType = 'application/json' } } $Transport
            $j = ConvertFrom-Json $txt
            $out = (@(@($j.candidates)[0].content.parts | Where-Object { -not $_.thought }) | ForEach-Object { $_.text }) -join ' '
            $said = $out
            $jj = $null
            try { $a2 = $out.Trim() -replace '^```(?:json)?\s*', '' -replace '\s*```$', ''; $jj = ConvertFrom-Json $a2; $said = [string]$jj.text; if ($jj.clear -eq $false -and $said.Length -lt 4) { $said = '' } } catch { }
            if ($Problems -and $jj -and $jj.PSObject.Properties['problem_ids']) {
                $known = @($Problems | ForEach-Object { $_.id })
                $ids = @(@($jj.problem_ids) | Where-Object { $_ -in $known } | Select-Object -First 3)
                $kw = @(Find-PDProblem -Text $said -Problems $Problems -Max 3 | ForEach-Object { $_.Problem.id })
                $res.U = [pscustomobject]@{ Ids = @($ids + $kw | Select-Object -Unique | Select-Object -First 4); Source = $(if ($ids.Count) { 'online' } else { 'basic' }); Model = $model
                    UnderstoodEn = [string]$jj.understood_en; Corrected = $said; Sure = [bool]($ids.Count -and $jj.sure -ne $false -and $jj.clear -ne $false); Notes = @()
                    Reply = $(if ($ids.Count) { '' } else { [string]$jj.reply }) }
            }
            $said = ($said -replace '\s+', ' ').Trim()
            # a usable transcript has letters; "????" / "..." means the words could not be made out (or were broken on the way)
            if (([regex]::Matches($said, '[\p{L}]')).Count -ge 2) { $res.Text = $said; $res.Source = 'online'; return $res }
            Write-PDLog ("voice: online speech recognition gave no words: '" + $(if ($out.Length -gt 120) { $out.Substring(0, 120) } else { $out }) + "' (codes " + ((@($out.ToCharArray()) | Select-Object -First 12 | ForEach-Object { [int]$_ }) -join ' ') + ')') 'WARN'
            $res.Error = 'online speech recognition gave no words'
        } catch { $res.Error = $_.Exception.Message; Write-PDLog "voice: online speech recognition failed: $($res.Error)" 'WARN' }
    }
    $a = Get-PDVoiceAssets $UsbRoot
    if ($a.Whisper -and $a.WhisperModel -and $Mode -ne 'online') {
        try {
            $psi = New-Object Diagnostics.ProcessStartInfo $a.Whisper
            # the conversation language is a strong hint (Marathi is otherwise often heard as Hindi); a few typical words help the spelling
            $wl = if ($Lang -in 'mr', 'hi') { $Lang } else { 'auto' }
            $hint = @{ mr = 'संजीवनी, माझा PC, laptop, internet, WiFi, printer, आवाज, screen, battery, virus. मधेच बंद पडतो, चालत नाही, हळू चालतो, गरम होतो, उघडत नाही. हो, नाही, धन्यवाद.'
                       hi = 'संजीवनी, मेरा PC, laptop, internet, WiFi, printer, आवाज़, screen, battery, virus. बीच में बंद हो जाता है, नहीं चल रहा, धीमा चलता है, गर्म होता है। हाँ, नहीं, धन्यवाद।'
                       en = 'Sanjeevani, my PC, laptop, internet, WiFi, printer, sound, screen, battery, virus. Yes, no, thank you.' }[$Lang]
            $psi.Arguments = "-m `"$($a.WhisperModel)`" -f `"$Wav`" -l $wl --prompt `"$hint`" -nt -np -t $([int][math]::Max([double]2, [double]([Environment]::ProcessorCount - 1)))"
            $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
            $psi.WorkingDirectory = Split-Path $a.Whisper
            $p = [Diagnostics.Process]::Start($psi)
            $errTask = $p.StandardError.ReadToEndAsync()
            $out = $p.StandardOutput.ReadToEnd()
            if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { } }
            $t = ($out -replace '\[[^\]]*\]', '' -replace '\((music|silence|noise)[^)]*\)', '' -replace '\s+', ' ').Trim()
            if ($t -match '^(\[BLANK_AUDIO\]|you|thank you\.?)$') { $t = '' }
            $res.Text = $t; $res.Source = 'offline'; $res.Error = ''
            return $res
        } catch { $res.Error = $_.Exception.Message; Write-PDLog "voice: whisper failed: $($res.Error)" 'WARN' }
    }
    if (-not $res.Error) { $res.Error = 'no speech recognition available (no AI key and no offline voice on the USB)' }
    return $res
}

# With an online key: Sanjeevani's usual sentences are fetched once in the online voice, slowly (free keys allow only a
# few voice requests a minute), and kept - after that every usual sentence is in the same natural voice.
function Invoke-PDVoicePrefetch {
    param([string]$UsbRoot, [string]$Lang = 'mr')
    $cfg = Get-PDAiConfig $UsbRoot
    if (-not $cfg.key -or $cfg.provider -eq 'anthropic') { return 0 }
    $done = 0; $fails = 0
    Start-Sleep -Seconds 40          # the live conversation goes first
    foreach ($k in @($script:Lines.Keys | Sort-Object { $_ -notin 'greet', 'ack', 'thinking', 'more', 'bye', 'working', 'pressmic', 'nohear', 'sayagain', 'yesno' })) {
        $text = Get-PDVoiceLine $k $(if ($k -eq 'welcome') { 'en' } else { $Lang })
        if ($text -match '\{0\}') { continue }
        $l = if ($k -eq 'welcome') { 'en' } else { $Lang }
        $t = ConvertTo-PDSpeakable $text
        $c = Get-PDVoiceCachePath $UsbRoot $l $t
        if (Test-Path -LiteralPath $c) { continue }
        $off = [AppDomain]::CurrentDomain.GetData('SJTtsOff')
        if ($off -and ([datetime]$off) -gt (Get-Date)) { break }          # the key's voice limit is reached: try again next time
        $tmp = [IO.Path]::GetTempFileName()
        if (New-PDSpeechGemini $t $tmp $cfg) { try { New-Item -ItemType Directory -Path (Split-Path $c) -Force | Out-Null; Move-Item -LiteralPath $tmp -Destination $c -Force; $done++ } catch { } }
        else { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; break }
        Start-Sleep -Seconds 25
    }
    return $done
}

function Install-PDVoicePack {
    param([string]$UsbRoot, [string]$Lang = 'mr')
    $a = Get-PDVoiceAssets $UsbRoot
    if ($a.Piper -and $a.Voices[$Lang]) { return 'present' }
    $ProgressPreference = 'SilentlyContinue'      # Windows PowerShell downloads very slowly while drawing a progress bar
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $dest = $null
    foreach ($d in (Get-PDVoiceDirs $UsbRoot)) {
        try { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null; $t = Join-Path $d '.w'; [IO.File]::WriteAllText($t, 'x'); Remove-Item $t -Force; $dest = $d; break } catch { }
    }
    if (-not $dest) { return 'nowrite' }
    $ua = @{ 'User-Agent' = 'Sanjeevani-PCDoctor' }
    try {
        if (-not $a.Piper) {
            Write-PDLog 'voice: downloading the Piper voice engine (~22 MB)' 'STEP'
            $url = 'https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip'
            try { $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/rhasspy/piper/releases/latest' -Headers $ua -TimeoutSec 20; $u2 = @($rel.assets | Where-Object { $_.name -match '^piper_windows_amd64\.zip$' })[0].browser_download_url; if ($u2) { $url = $u2 } } catch { }
            $zip = Join-Path $env:TEMP 'sjv-piper.zip'
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -Headers $ua -TimeoutSec 300
            Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $dest 'Piper voice engine') -Force
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
        }
        if (-not $a.Voices[$Lang]) {
            Write-PDLog "voice: downloading the $Lang voice (~60 MB)" 'STEP'
            $prefer = @{ mr = @('female', 'sunita', 'medium'); hi = @('priyamvada', 'female', 'medium'); en = @('en_GB-alba', 'en_US-amy', 'hfc_female', 'lessac') }[$Lang]
            $j = Invoke-RestMethod -Uri 'https://huggingface.co/rhasspy/piper-voices/resolve/main/voices.json' -Headers $ua -TimeoutSec 60
            $all = @($j.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_.language.family -eq $Lang })
            if (-not $all.Count) { return 'novoice' }
            $best = $all | Sort-Object { $v = $_; $sc = 0; for ($i = 0; $i -lt $prefer.Count; $i++) { if ($v.key -match $prefer[$i]) { $sc += 100 - $i * 10 } }; $sc + @{ medium = 5; high = 4; low = 2; x_low = 1 }[[string]$v.quality] } -Descending | Select-Object -First 1
            $path = @($best.files.PSObject.Properties.Name | Where-Object { $_ -match '\.onnx$' })[0]
            $vd = Join-Path $dest "Piper voice - $Lang"
            New-Item -ItemType Directory -Path $vd -Force | Out-Null
            $base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/$path"
            $file = Join-Path $vd ([IO.Path]::GetFileName($path))
            Invoke-WebRequest -Uri ($base + '.json') -OutFile ($file + '.json') -UseBasicParsing -Headers $ua -TimeoutSec 120
            Invoke-WebRequest -Uri $base -OutFile ($file + '.part') -UseBasicParsing -Headers $ua -TimeoutSec 900
            Move-Item -LiteralPath ($file + '.part') -Destination $file -Force
        }
        Write-PDLog "voice: $Lang voice ready ($dest)" 'OK'
        return 'installed'
    } catch { Write-PDLog "voice: download failed: $($_.Exception.Message)" 'WARN'; return 'failed' }
}

# Can Sanjeevani hear at all (online key or offline whisper)?
function Test-PDCanListen([string]$UsbRoot, [string]$Mode = 'auto') {
    $cfg = Get-PDAiConfig $UsbRoot
    if ($Mode -in 'auto', 'online' -and $cfg.key -and $cfg.provider -ne 'claude') { return $true }
    $a = Get-PDVoiceAssets $UsbRoot
    return [bool]($a.Whisper -and $a.WhisperModel -and $Mode -ne 'online')
}

Export-ModuleMember -Function Invoke-PDVoicePrefetch, Get-PDVoiceCachePath, Test-PDYes, Test-PDNo, ConvertTo-PDRoman, Install-PDVoicePack, New-PDSpeechGemini, Get-PDVoiceLine, Get-PDVoiceKeys, Get-PDTextLang, Test-PDGoodbye, Get-PDVoiceAssets, Initialize-PDVoiceNative, Enable-PDMicrophone, Invoke-PDRecord, ConvertTo-PDSpeakable, New-PDSpeech, ConvertFrom-PDSpeech, Test-PDCanListen
