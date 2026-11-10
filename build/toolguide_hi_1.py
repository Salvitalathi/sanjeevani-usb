# Hindi (हिन्दी) text for the Tools guide - part 1. Used by make_toolguide.py.
H = {}
def h(id, what, when, steps, good='', warn=()):
    H[id] = {'what': what, 'when': when, 'steps': list(steps), 'good': good, 'warn': list(warn)}

h('crystaldiskinfo', 'Hard disk और SSD की सेहत (SMART) और तापमान बताता है।',
  'PC धीमा हो गया, files नहीं खुलतीं, disk से आवाज़ आती है, या Windows install करने से पहले।',
  ['"अपने आप जाँचें" दबाएँ - हर disk का नतीजा यहीं आसान भाषा में दिखेगा।',
   'खुद देखना हो तो "खोलें" - ऊपर का नीला/पीला/लाल box ही health है।'],
  'Good (नीला) = ठीक। Caution (पीला) = disk खराब होने लगी है - data अभी copy करें, disk बदलने की तैयारी करें। Bad (लाल) = तुरंत data copy करें।')
h('batteryinfoview', 'Laptop की battery कितनी घिसी है और कितना charge रखती है, यह बताता है।',
  'Laptop जल्दी बंद होता है, charging बीच में रुकती है, या नई battery का फ़ैसला करना है।',
  ['"अपने आप जाँचें" दबाएँ - Windows की अपनी battery report इस्तेमाल होती है।',
   '"खोलें" से BatteryInfoView में हर आँकड़ा दिखता है।'],
  '20% से कम घिसाव = ठीक। 20-40% = backup कम, फिर भी चलेगी। 40% से ज़्यादा = battery बदलने का समय।')
h('hwinfo', 'CPU, GPU और disks का तापमान, fan speed और voltages - हर sensor एक window में।',
  'PC / laptop गर्म होता है, fan तेज़ चलता है, या load पर अचानक बंद हो जाता है।',
  ['"अपने आप जाँचें" दबाएँ - HWiNFO सीधे Sensors window में खुलता है (कोई सवाल नहीं) और यह page बताता है क्या देखना है।',
   '5 मिनट काम करते हुए "CPU Package" या "CPU (Tctl/Tdie)" देखते रहें।'],
  'CPU: 40-75°C ठीक, 80-90°C ज़्यादा (धूल साफ़ करें / नया thermal paste), 95°C+ खतरनाक। "Thermal Throttling: Yes" = गर्मी से धीमा होता है। Disk 55°C से कम ठीक।')
h('cpuz', 'CPU, RAM (size, प्रकार, slots) और motherboard की पूरी जानकारी।',
  'RAM upgrade की योजना, कौन सी RAM खरीदें, Windows 11 चलेगा या नहीं, या PC के अंदर क्या है।',
  ['"अपने आप जाँचें" दबाएँ - PC की जानकारी और upgrade सलाह (RAM, SSD) यहाँ दिखती है; CPU-Z की पूरी report Reports folder में save होती है।',
   '"खोलें" - Memory tab में RAM का प्रकार (DDR3/DDR4/DDR5) और Channel (Single/Dual); SPD tab में हर slot।'],
  'Channel "Dual" होना चाहिए। "Single" हो तो वैसी ही दूसरी stick लगाने से तेज़ होता है। Windows 10/11 8 GB RAM या ज़्यादा और SSD के साथ अच्छा चलता है।')
h('gpuz', 'Graphics card की जानकारी और तापमान।',
  'Display या game की समस्या, graphics card असली है या नहीं जाँचना।',
  ['"खोलें" - Graphics Card tab में नाम और memory; Sensors tab में तापमान।'],
  'GPU 85°C से कम ठीक है।')
h('win-memdiag', 'RAM में खराबी जाँचता है (Windows में ही है)।',
  'बार-बार blue screen, programs अपने आप बंद होना, Windows install करते समय errors.',
  ['"अपने आप जाँचें" पिछले RAM test का नतीजा दिखाता है (अगर हुआ हो)।',
   '"खोलें" - "Restart now and check" चुनें। PC restart होकर 10-20 मिनट test करता है और फिर Windows शुरू करता है। वापस आकर नतीजे के लिए "अपने आप जाँचें" दबाएँ।',
   'और गहरी जाँच के लिए: USB से boot → MemTest86+.'],
  '"No errors" = RAM ठीक। Errors हों तो sticks एक-एक करके test करें और खराब stick बदलें।',
  ['"Restart now" PC को तुरंत restart करता है - पहले सारा काम save करें।'])
h('crystaldiskmark', 'Disk की speed मापता है (read/write MB/s)।',
  'PC धीमा है - क्या disk कारण है? नया SSD असली है?',
  ['"खोलें" → ऊपर "All" दबाएँ। 2-5 मिनट रुकें।', 'पहली row (SEQ1M Q8T1) का Read आँकड़ा देखें।'],
  'HDD: 80-200 MB/s. SATA SSD: 450-560 MB/s. NVMe SSD: 1500-7000 MB/s. HDD 50 से कम = घिस गई या खराब हो रही है।',
  ['Test कई GB लिखता है - खराब हो रही disk पर न चलाएँ (पहले CrystalDiskInfo देखें)।', 'SSD पर बार-बार न चलाएँ।'])
h('prime95', 'CPU और RAM पर पूरा load डालकर देखता है कि PC stable रहता है या नहीं।',
  'Load पर PC बंद / restart होता है या hang होता है, या मरम्मत (thermal paste, fan) के बाद पक्का करने के लिए।',
  ['"अपने आप जाँचें" दबाएँ - test 10 मिनट चलता है, तापमान पर नज़र रहती है और CPU 95°C पार करे तो अपने आप रुकता है। नतीजा यहाँ दिखेगा।',
   'नीचे "रोकें" कभी भी दबा सकते हैं।'],
  '10 मिनट बिना error = CPU/RAM stable. Error या बंद होना = cooling, RAM या power supply की खराबी।',
  ['PC बहुत गर्म होगा और fan तेज़ चलेगा - यह सामान्य है।', 'Laptop का charger लगाएँ। जो PC पहले से 90°C से ऊपर चलता है उसकी धूल पहले साफ़ करें।', 'Test के दौरान PC पर काम न करें।'])
h('occt', 'CPU, RAM, graphics card और power supply का stress test (graphs के साथ)।',
  'Prime95 से ज़्यादा जानकारी या graphics card का test चाहिए।',
  ['"खोलें" → बाईं ओर test चुनें (CPU / Memory / 3D) → Start. 10-15 मिनट।', 'Monitoring में तापमान देखें; error पर test खुद रुकता है।'],
  'Errors नहीं और तापमान 90°C से कम = ठीक।',
  ['PC बहुत गर्म होता है; कमज़ोर power supply वाले पुराने PC पर "Power" test न चलाएँ।', 'Laptop का charger लगाएँ।'])
h('furmark', 'Graphics card पर अधिकतम load (GPU stress test)।',
  'Game खेलते समय display जाता है या PC बंद होता है - क्या graphics card दोषी है?',
  ['"खोलें" → "GPU stress test". 5 मिनट से ज़्यादा न चलाएँ।'],
  'Dots/रंगों की गड़बड़ या बंद होना = GPU या power supply की खराबी।',
  ['GPU बहुत गर्म होता है। पुराने या laptop graphics पर खतरा - 5 मिनट में रोकें।', '90°C पार हो तो तुरंत रोकें।'])
h('bluescreenview', 'Blue screens (BSOD) कब हुईं और कौन सा driver कारण था, यह दिखाता है।',
  'PC पर blue screen आकर restart होता है।',
  ['"अपने आप जाँचें" दबाएँ - हाल के crash, ज़िम्मेदार driver और क्या करें यहाँ दिखेगा।',
   '"खोलें" - नीचे के हिस्से में लाल रंग वाले drivers संभावित कारण हैं।'],
  'एक ही third-party driver बार-बार (जैसे nvlddmkm.sys = nVIDIA, rt640x64.sys = Realtek LAN) = वह driver update/बदलें। ntoskrnl.exe या कई अलग drivers = RAM और disk जाँचें।')
h('whocrashed', 'Crash के कारण आसान English में समझाता है (installer)।',
  'BlueScreenView का नतीजा समझना मुश्किल है।',
  ['"Install करें" - इस PC पर install होता है।', 'खोलकर "Analyze" दबाएँ; नीचे का "Conclusion" पढ़ें।'],
  'Conclusion में बताया driver update करें।',
  ['यह program इस PC पर install होता है (बाद में Control Panel से हटाएँ)।'])
h('msert', 'Microsoft का मुफ़्त virus scanner (install नहीं)।',
  'Virus, pop-ups, browser अपने आप खुलना, अजीब व्यवहार।',
  ['"अपने आप जाँचें" - quick scan (10-20 मिनट), सिर्फ़ पहचान (कुछ delete नहीं करता)। नतीजा यहाँ दिखेगा।',
   'कुछ मिले तो: "खोलें" → Full scan चुनें और उसे हटाने दें।'],
  '"No infection found" = virus नहीं।')
h('kvrt', 'Kaspersky का मुफ़्त virus removal tool (install नहीं)।',
  'Microsoft scanner के बाद भी virus का शक है।',
  ['"खोलें" → Accept → "Start scan". 15-60 मिनट।', 'मिले हर खतरे के लिए हटाने को "Continue" दबाएँ।'],
  '"No threats" = ठीक।',
  ['Scan में समय लगता है; बीच में PC बंद न करें।'])
h('adwcleaner', 'Adware, toolbars और browser hijackers हटाता है।',
  'Browser में ads, homepage बदला, अनचाहे extensions.',
  ['"खोलें" → "Scan now". सूची देखें - पहचाने programs का ✔ हटाएँ।', '"Quarantine" दबाएँ; PC restart होगा।'],
  'Restart के बाद browser सामान्य हो जाता है।',
  ['Cleaning के बाद restart माँगता है - काम save करें।', 'Company के साथ आए कुछ "PUP" programs भी हटते हैं - quarantine से पहले सूची देखें।'])
h('malwarebytes', 'अच्छा malware scanner (installer; free version scan और साफ़ करता है)।',
  'दूसरे scanners के बाद भी समस्या बनी है।',
  ['"Install करें" → free version चुनें → Scan.'],
  'जो मिले उसे quarantine करें।',
  ['इस PC पर install होता है। 14 दिन का "Premium trial" शुरू होता है - फिर अपने आप free version बन जाता है, कोई भुगतान नहीं।'])
h('wiztree', 'कुछ सेकंड में दिखाता है कि C: पर कौन से folders सबसे ज़्यादा जगह लेते हैं।',
  'C: drive भर गया है।',
  ['"अपने आप जाँचें" - 15 सबसे बड़े folders यहाँ दिखेंगे।', 'ले जाने के लिए PC Doctor का "C: drive जगह" page इस्तेमाल करें (सुरक्षित रूप से दूसरे drive पर)।'],
  'Downloads, Videos और पुराने backups जैसे बड़े folders ले जा सकते हैं या delete कर सकते हैं।',
  ['Windows, Program Files या ProgramData के folders हाथ से कभी delete न करें - Windows खराब होगा।'])
h('autoruns', 'Windows के साथ शुरू होने वाला हर program, service और driver.',
  'PC शुरू होने में बहुत समय लगता है।',
  ['आसान तरीका: "PC Doctor में देखें" - सुझाए startup programs सुरक्षित रूप से बंद करें (Undo के साथ)।', 'Autoruns अनुभवी users के लिए है: सिर्फ़ "Logon" tab बदलें।'],
  'Startup पर सिर्फ़ ज़रूरी चीज़ें रखें (antivirus, touchpad/sound drivers)।',
  ['Drivers / Services / Microsoft entries का ✔ न हटाएँ - Windows शुरू नहीं हो सकता।', 'Delete के बजाय ✔ हटाएँ ताकि फिर चालू कर सकें।'])
h('procexp', 'Task Manager से ज़्यादा जानकारी - कौन सा program CPU/RAM ले रहा है और कहाँ से चलता है।',
  'PC धीमा होता है, fan लगातार चलता है, संदिग्ध program.',
  ['"खोलें" → CPU column पर click करके क्रम लगाएँ। सबसे ऊपर वाला program कारण है।', 'Process पर right-click → "Check VirusTotal" से देखें कि सुरक्षित है या नहीं।'],
  'खाली बैठे CPU 10% से कम होना चाहिए।',
  ['System, csrss, wininit, lsass, svchost जैसी Windows processes को "Kill" न करें - PC crash होगा।'])
h('bcu', 'कई अनचाहे programs एक साथ हटाता है, बचा हुआ कचरा भी।',
  'बहुत सारे bloatware / trial programs.',
  ['आसान तरीका: "PC Doctor में देखें" - "OS / Apps सलाह" हटाने लायक apps और हल्के विकल्प बताता है।', 'BCU: अनचाहे programs पर ✔ → "Uninstall", फिर बचा कचरा हटाने दें।'],
  '',
  ['Drivers, Microsoft Visual C++ / .NET या antivirus न हटाएँ।', 'नाम न पहचानें तो छोड़ दें।'])
h('sdio', 'बिना internet के drivers (USB पर रखे driver packs से)।',
  'नए Windows के बाद WiFi / LAN / sound / display नहीं चलते।',
  ['सुरक्षित तरीका: "PC Doctor में देखें" - कम drivers ढूँढकर सही क्रम बताता है।', 'SDIO में: पहले "Create restore point" पर ✔, फिर सिर्फ़ "Missing" drivers चुनें → Install.'],
  'Device Manager में पीले विस्मयादिबोधक चिह्न नहीं।',
  ['"Select all" करके सब update न करें - चलते drivers खराब हो सकते हैं।', 'Laptop display / touchpad के लिए निर्माता की website का driver बेहतर है।'])
h('doubledriver', 'इस PC के drivers का backup / restore.',
  'Windows reinstall से पहले।',
  ['आसान तरीका: PC Doctor → मरम्मत → "Drivers backup" (Windows DISM इस्तेमाल करता है)।', 'Double Driver: Backup → Scan Current System → Backup Now.'])
h('victoria', 'Hard disk में bad sectors ढूँढने वाला surface test.',
  'CrystalDiskInfo "Caution" दिखाए, disk आवाज़ करे, files खराब हों।',
  ['"खोलें" → दाईं ओर disk चुनें → "Test & Repair" tab → "Ignore" चुना है पक्का करें → Scan.', 'रंग: grey = ठीक, green/orange = धीमा, red/blue "Err" = bad sector.'],
  'Red / Err नहीं = surface ठीक। कई red blocks = disk बदलें।',
  ['सिर्फ़ "Ignore" mode इस्तेमाल करें। "Erase", "Write" और "Refresh" modes disk का data मिटा देते हैं!', 'खराब disk पर पहले data copy करें, फिर test - test खुद हालत बिगाड़ सकता है।'])
h('hdtune', 'Disk की सेहत, speed और error scan (installer)।',
  'आसान disk जाँच।',
  ['"Install करें" → खोलें → "Error Scan" tab → Start (Quick scan नहीं)।'],
  'सब हरे चौकोर = ठीक; लाल = bad sectors.',
  ['इस PC पर install होता है।'])
