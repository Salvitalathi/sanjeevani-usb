"""Writes kit/Sanjeevani/PCDoctor/data/toolguide.json - the Marathi / English guide for every tool
shown in PC Doctor's "Tools मार्गदर्शक" page.

Per entry:
  group  - task group (see GROUPS)
  risk   - safe | caution | danger   (caution/danger: warnings are shown and confirmed before opening)
  auto   - auto handler in lib/ToolGuide.psm1 (runs the check itself and explains the result), or
           pd:<page|repair> to send the user to the matching PC Doctor feature
  boot   - true for boot-menu items (used by restarting from the USB, not opened in Windows)
  builtin- true when the entry uses Windows' own tools (nothing to download)
  mr/en  - what (one line), when (when to use it), steps (how to use, manual mode), warn (warnings),
           good (how to read the result)
Run:  python3 build/make_toolguide.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'kit', 'Sanjeevani', 'PCDoctor', 'data', 'toolguide.json')

GROUPS = [
    ('health',   'PC ची तब्येत तपासा',              'Check PC health'),
    ('stress',   'गरम होणे / अचानक बंद पडणे (stress test)', 'Overheating / sudden shutdowns (stress test)'),
    ('crash',    'Blue screen / crash चे कारण',      'Blue screen / crash cause'),
    ('virus',    'Virus / adware काढा',              'Remove viruses / adware'),
    ('speed',    'वेग आणि जागा',                     'Speed and disk space'),
    ('drivers',  'Drivers',                         'Drivers'),
    ('disk',     'Disk test आणि data recovery',      'Disk test and data recovery'),
    ('backup',   'Partition आणि backup',             'Partitions and backup'),
    ('windows',  'Windows tools (keys, password, boot)', 'Windows tools (keys, password, boot)'),
    ('network',  'Internet / network / remote मदत',  'Internet / network / remote help'),
    ('apps',     'उपयोगी apps',                      'Useful apps'),
    ('mytools',  'माझे tools (MyTools folder)',        'My tools (MyTools folder)'),
    ('bootmenu', 'Pendrive वरून boot करून वापरायचे',  'Use by booting from the USB'),
]

def E(group, risk, mr, en, auto=None, boot=False, builtin=False, name=None):
    d = {'group': group, 'risk': risk, 'mr': mr, 'en': en}
    if auto: d['auto'] = auto
    if boot: d['boot'] = True
    if builtin: d['builtin'] = True
    if name: d['name'] = name
    return d

BOOT_STEPS_MR = ['PC बंद करा, pendrive लावा आणि सुरू करताना Boot Menu key दाबा (F12 / F9 / Esc / F11 - "Boot Menu / BIOS keys" पहा).',
                 'Sanjeevani च्या menu मधून हा पर्याय निवडा.']
BOOT_STEPS_EN = ['Shut the PC down, plug in the USB and press the Boot Menu key while it starts (F12 / F9 / Esc / F11 - see "Boot Menu / BIOS keys").',
                 'Choose this item in the Sanjeevani menu.']

T = {}

# ------------------------------------------------------------------ health
T['crystaldiskinfo'] = E('health', 'safe', auto='disk-health',
    mr={'what': 'Hard disk / SSD ची तब्येत (SMART) आणि तापमान सांगतो.',
        'when': 'PC हळू झाला, files उघडत नाहीत, आवाज येतो, किंवा Windows install करण्याआधी.',
        'steps': ['"आपोआप तपासा" दाबा - प्रत्येक disk चा निकाल इथेच सोप्या भाषेत दिसेल.',
                  'स्वतः पाहायचे असल्यास "उघडा" - वरचा निळा/पिवळा/लाल box म्हणजे health.'],
        'good': 'Good (निळा) = ठीक. Caution (पिवळा) = disk खराब होऊ लागली - data लगेच copy करा, disk बदलायची तयारी करा. Bad (लाल) = आत्ताच data copy करा.',
        'warn': []},
    en={'what': 'Shows the health (SMART) and temperature of hard disks and SSDs.',
        'when': 'The PC got slow, files will not open, the disk makes noise, or before installing Windows.',
        'steps': ['Press "Check automatically" - each disk gets a plain-language result here.',
                  'To look yourself press "Open" - the blue/yellow/red box at the top is the health.'],
        'good': 'Good (blue) = fine. Caution (yellow) = the disk is starting to fail - copy the data now and plan a replacement. Bad (red) = copy the data immediately.',
        'warn': []})
T['batteryinfoview'] = E('health', 'safe', auto='battery',
    mr={'what': 'Laptop battery किती झिजली (wear level) आणि किती charge धरते ते सांगतो.',
        'when': 'Laptop लवकर discharge होतो, charging मध्येच थांबते, battery बदलायची का ठरवायचे असेल.',
        'steps': ['"आपोआप तपासा" दाबा - Windows च्या battery report मधून निकाल येतो.', '"उघडा" ने BatteryInfoView मध्ये सगळे आकडे दिसतात.'],
        'good': '20% पेक्षा कमी झीज = ठीक. 20-40% = कमी backup, चालेल. 40% पेक्षा जास्त = battery बदलण्याची वेळ.',
        'warn': []},
    en={'what': 'Shows how worn the laptop battery is and how much charge it still holds.',
        'when': 'The laptop runs out quickly, charging stops halfway, or you need to decide on a new battery.',
        'steps': ['Press "Check automatically" - uses Windows\' own battery report.', '"Open" shows every number in BatteryInfoView.'],
        'good': 'Under 20% wear = fine. 20-40% = shorter backup, still usable. Over 40% = time to replace the battery.',
        'warn': []})
T['hwinfo'] = E('health', 'safe', auto='temps',
    mr={'what': 'CPU, GPU, disk यांचे तापमान, fan speed, voltage - सगळे sensors एका window मध्ये.',
        'when': 'PC / laptop गरम होतो, fan जोरात फिरतो, games / काम करताना अचानक बंद पडतो.',
        'steps': ['"आपोआप तपासा" दाबा - HWiNFO थेट Sensors window मध्ये उघडेल (कुठलेही प्रश्न न विचारता) आणि काय पाहायचे ते इथे दिसेल.',
                  'Window मध्ये "CPU Package" किंवा "CPU (Tctl/Tdie)" चे तापमान पाहा. काम करताना 5 मिनिटे लक्ष ठेवा.'],
        'good': 'CPU: 40-75°C ठीक, 80-90°C जास्त (धूळ साफ करा / thermal paste), 95°C+ धोका. "Thermal Throttling: Yes" = गरमीमुळे वेग कमी होतो. Disk 55°C पेक्षा कमी ठीक.',
        'warn': []},
    en={'what': 'Temperatures of CPU, GPU and disks, fan speeds and voltages - every sensor in one window.',
        'when': 'The PC / laptop runs hot, the fan is loud, or it shuts down suddenly under load.',
        'steps': ['Press "Check automatically" - HWiNFO opens straight into the Sensors window (no questions) and this page tells you what to look at.',
                  'Watch "CPU Package" or "CPU (Tctl/Tdie)" while you work for 5 minutes.'],
        'good': 'CPU: 40-75°C fine, 80-90°C high (clean the dust / new thermal paste), 95°C+ dangerous. "Thermal Throttling: Yes" = it slows down from heat. Disk under 55°C is fine.',
        'warn': []})
T['cpuz'] = E('health', 'safe', auto='system-summary',
    mr={'what': 'CPU, RAM (किती, कोणती, किती slots), motherboard ची पूर्ण माहिती.',
        'when': 'RAM वाढवायची / नवीन RAM कोणती घ्यायची, Windows 11 चालेल का, PC मध्ये काय आहे ते जाणून घ्यायचे.',
        'steps': ['"आपोआप तपासा" दाबा - PC ची माहिती आणि upgrade सल्ला (RAM, SSD) इथे दिसेल. CPU-Z चा पूर्ण report Reports folder मध्ये save होतो.',
                  '"उघडा" - Memory tab मध्ये RAM type (DDR3/DDR4/DDR5) आणि Channel (Single/Dual), SPD tab मध्ये प्रत्येक slot.'],
        'good': 'Channel "Dual" असावा. "Single" असल्यास तशीच दुसरी RAM लावल्यास वेग वाढतो. Windows 10/11 साठी किमान 8 GB RAM आणि SSD चांगले.',
        'warn': []},
    en={'what': 'Full details of the CPU, RAM (size, type, slots) and motherboard.',
        'when': 'Planning a RAM upgrade, checking which RAM to buy, whether Windows 11 suits, or what is inside the PC.',
        'steps': ['Press "Check automatically" - PC details and upgrade advice (RAM, SSD) appear here; the full CPU-Z report is saved in the Reports folder.',
                  '"Open" - the Memory tab shows the RAM type (DDR3/DDR4/DDR5) and Channel (Single/Dual); the SPD tab shows each slot.'],
        'good': 'Channel should be "Dual". With "Single", adding a matching second stick makes it faster. Windows 10/11 runs well with 8 GB RAM or more and an SSD.',
        'warn': []})
T['gpuz'] = E('health', 'safe',
    mr={'what': 'Graphics card ची माहिती आणि तापमान.', 'when': 'Display / game समस्या, graphics card खरी आहे का ते पाहायचे.',
        'steps': ['"उघडा" - Graphics Card tab मध्ये नाव, memory; Sensors tab मध्ये तापमान.'], 'good': 'GPU 85°C पेक्षा कमी ठीक.', 'warn': []},
    en={'what': 'Graphics card details and temperature.', 'when': 'Display or game problems, checking whether a graphics card is genuine.',
        'steps': ['"Open" - the Graphics Card tab shows name and memory; the Sensors tab the temperature.'], 'good': 'GPU under 85°C is fine.', 'warn': []})
T['win-memdiag'] = E('health', 'caution', auto='memdiag', builtin=True, name='Windows Memory Diagnostic (RAM test)',
    mr={'what': 'RAM खराब आहे का ते तपासतो (Windows मध्येच असलेला test).',
        'when': 'वारंवार blue screen, programs अचानक बंद, Windows install होताना error.',
        'steps': ['"आपोआप तपासा" - आधी झालेल्या RAM test चा निकाल (असल्यास) दाखवतो.',
                  '"उघडा" - "Restart now and check" निवडा. PC restart होऊन 10-20 मिनिटे test चालतो, नंतर Windows सुरू होते. परत इथे येऊन "आपोआप तपासा" ने निकाल पाहा.',
                  'जास्त खोल test साठी: pendrive वरून boot → MemTest86+.'],
        'good': '"No errors" = RAM ठीक. Errors आल्यास RAM stick एक-एक काढून test करा; खराब stick बदला.',
        'warn': ['"Restart now" निवडल्यास PC लगेच restart होतो - आधी सगळे काम save करा.']},
    en={'what': 'Checks the RAM for faults (built into Windows).',
        'when': 'Repeated blue screens, programs closing by themselves, errors while installing Windows.',
        'steps': ['"Check automatically" shows the result of the last RAM test, if any.',
                  '"Open" - choose "Restart now and check". The PC restarts, tests for 10-20 minutes and starts Windows again. Come back and press "Check automatically" for the result.',
                  'For a deeper test: boot the USB → MemTest86+.'],
        'good': '"No errors" = RAM is fine. With errors, test the sticks one at a time and replace the bad one.',
        'warn': ['"Restart now" restarts the PC at once - save all work first.']})
T['crystaldiskmark'] = E('health', 'caution',
    mr={'what': 'Disk चा वेग (read/write MB/s) मोजतो.', 'when': 'PC हळू आहे - disk कारण आहे का ते पाहायचे; नवीन SSD खरी आहे का.',
        'steps': ['"उघडा" → वरचा "All" दाबा. 2-5 मिनिटे थांबा.', 'पहिल्या ओळीतील (SEQ1M Q8T1) Read आकडा पाहा.'],
        'good': 'HDD: 80-200 MB/s. SATA SSD: 450-560 MB/s. NVMe SSD: 1500-7000 MB/s. HDD ला 50 पेक्षा कमी = disk थकली / खराब.',
        'warn': ['Test disk वर काही GB लिहितो - खराब होत असलेल्या disk वर चालवू नका (आधी CrystalDiskInfo ने health पाहा).', 'SSD वर वारंवार चालवू नका.']},
    en={'what': 'Measures disk speed (read/write MB/s).', 'when': 'The PC is slow - is the disk the reason? Is a new SSD genuine?',
        'steps': ['"Open" → press "All" at the top. Wait 2-5 minutes.', 'Look at the Read number in the first row (SEQ1M Q8T1).'],
        'good': 'HDD: 80-200 MB/s. SATA SSD: 450-560 MB/s. NVMe SSD: 1500-7000 MB/s. An HDD under 50 = worn out or failing.',
        'warn': ['The test writes several GB - do not run it on a failing disk (check CrystalDiskInfo first).', 'Do not run it again and again on an SSD.']})

# ------------------------------------------------------------------ stress
T['prime95'] = E('stress', 'caution', auto='stress-cpu',
    mr={'what': 'CPU आणि RAM वर पूर्ण load देऊन PC stable आहे का ते तपासतो.',
        'when': 'काम करताना PC अचानक बंद / restart होतो, hang होतो, किंवा दुरुस्तीनंतर (thermal paste, fan) खात्री करायची.',
        'steps': ['"आपोआप तपासा" दाबा - 10 मिनिटे test चालेल, तापमानावर लक्ष ठेवले जाईल आणि CPU 95°C ओलांडल्यास test आपोआप थांबेल. निकाल इथे दिसेल.',
                  'कधीही थांबवायचे असल्यास खालचा "थांबवा" button दाबा.'],
        'good': 'Error न येता 10 मिनिटे पूर्ण = CPU/RAM stable. Error / PC बंद पडणे = cooling, RAM किंवा power supply मध्ये दोष.',
        'warn': ['PC खूप गरम होतो आणि fan जोरात फिरतो - हे अपेक्षित आहे.', 'Laptop ला charger लावा. आधीच 90°C पेक्षा गरम होणाऱ्या PC वर आधी धूळ साफ करा.', 'Test चालू असताना इतर काम करू नका.']},
    en={'what': 'Puts full load on the CPU and RAM to check that the PC stays stable.',
        'when': 'The PC shuts down / restarts or hangs under load, or after a repair (thermal paste, fan) to confirm it.',
        'steps': ['Press "Check automatically" - the test runs for 10 minutes, temperatures are watched and it stops by itself if the CPU passes 95°C. The result appears here.',
                  'Press "Stop" at the bottom at any time.'],
        'good': '10 minutes without an error = CPU/RAM are stable. An error or a shutdown = a cooling, RAM or power-supply fault.',
        'warn': ['The PC gets very hot and the fan gets loud - that is expected.', 'Plug in the laptop charger. Clean the dust first on a PC that already runs above 90°C.', 'Do not work on the PC during the test.']})
T['occt'] = E('stress', 'caution',
    mr={'what': 'CPU, RAM, graphics card आणि power supply साठी stress test (graph सह).', 'when': 'Prime95 पेक्षा जास्त तपशील / graphics card test हवा असेल.',
        'steps': ['"उघडा" → डावीकडे Test निवडा (CPU / Memory / 3D) → Start. 10-15 मिनिटे.', 'Monitoring मध्ये तापमान पाहा; error आल्यास test स्वतः थांबतो.'],
        'good': 'Errors नाहीत आणि तापमान 90°C च्या आत = ठीक.',
        'warn': ['PC खूप गरम होतो; "Power" test कमकुवत power supply असलेल्या जुन्या PC वर चालवू नका.', 'Laptop ला charger लावा.']},
    en={'what': 'Stress test for CPU, RAM, graphics card and power supply (with graphs).', 'when': 'You need more detail than Prime95 or a graphics card test.',
        'steps': ['"Open" → pick a test on the left (CPU / Memory / 3D) → Start. 10-15 minutes.', 'Watch temperatures in Monitoring; the test stops itself on an error.'],
        'good': 'No errors and temperatures under 90°C = fine.',
        'warn': ['The PC gets very hot; do not run the "Power" test on old PCs with a weak power supply.', 'Plug in the laptop charger.']})
T['furmark'] = E('stress', 'danger',
    mr={'what': 'Graphics card वर जास्तीत जास्त load (GPU stress test).', 'when': 'Game खेळताना display जातो / PC बंद पडतो - graphics card दोषी आहे का.',
        'steps': ['"उघडा" → "GPU stress test". 5 मिनिटांपेक्षा जास्त चालवू नका.'], 'good': 'Screen वर ठिपके/रंग बिघडणे किंवा PC बंद = GPU / power supply दोष.',
        'warn': ['GPU खूप गरम होतो. जुन्या / laptop graphics वर धोका - 5 मिनिटांत थांबवा.', 'तापमान 90°C ओलांडल्यास लगेच थांबवा.']},
    en={'what': 'Maximum load on the graphics card (GPU stress test).', 'when': 'The display drops or the PC shuts off while gaming - is the graphics card to blame?',
        'steps': ['"Open" → "GPU stress test". Do not run it longer than 5 minutes.'], 'good': 'Dots/colour artefacts or a shutdown = GPU or power-supply fault.',
        'warn': ['The GPU gets very hot. Risky on old or laptop graphics - stop within 5 minutes.', 'Stop at once if it passes 90°C.']})

# ------------------------------------------------------------------ crash
T['bluescreenview'] = E('crash', 'safe', auto='crashes',
    mr={'what': 'Blue screen (BSOD) कधी झाले आणि कोणत्या driver मुळे ते सांगतो.',
        'when': 'PC मध्येच blue screen येऊन restart होतो.',
        'steps': ['"आपोआप तपासा" दाबा - मागचे crashes, जबाबदार driver आणि काय करायचे ते इथे दिसेल.', '"उघडा" - खालच्या भागात लाल दिसणारा driver दोषी असण्याची शक्यता.'],
        'good': 'एकच third-party driver (उदा. nvlddmkm.sys = nVIDIA, rt640x64.sys = Realtek LAN) वारंवार = तो driver बदला/update करा. ntoskrnl.exe / वेगवेगळे drivers = RAM किंवा disk तपासा.',
        'warn': []},
    en={'what': 'Shows when blue screens (BSOD) happened and which driver caused them.',
        'when': 'The PC shows a blue screen and restarts.',
        'steps': ['Press "Check automatically" - recent crashes, the responsible driver and what to do appear here.', '"Open" - drivers highlighted in red in the lower part are the likely cause.'],
        'good': 'One third-party driver again and again (e.g. nvlddmkm.sys = nVIDIA, rt640x64.sys = Realtek LAN) = update/replace that driver. ntoskrnl.exe or many different drivers = test RAM and disk.',
        'warn': []})
T['whocrashed'] = E('crash', 'caution',
    mr={'what': 'Crash चे कारण साध्या इंग्रजीत समजावून सांगतो (installer).', 'when': 'BlueScreenView चा निकाल कळत नसेल.',
        'steps': ['"Install करा" - या PC वर install होईल.', 'उघडून "Analyze" दाबा; खाली "Conclusion" वाचा.'], 'good': 'Conclusion मध्ये सुचवलेला driver update करा.',
        'warn': ['हा program या PC वर install होतो (नंतर Control Panel मधून काढता येतो).']},
    en={'what': 'Explains crash causes in plain English (installer).', 'when': 'The BlueScreenView result is hard to understand.',
        'steps': ['"Install" - installs it on this PC.', 'Open it and press "Analyze"; read the "Conclusion" at the bottom.'], 'good': 'Update the driver the conclusion names.',
        'warn': ['This program installs on this PC (remove it later from Control Panel).']})

# ------------------------------------------------------------------ virus
T['msert'] = E('virus', 'safe', auto='msert',
    mr={'what': 'Microsoft चा मोफत virus scanner (install न करता).', 'when': 'Virus / popups / browser आपोआप उघडणे / PC विचित्र वागणे.',
        'steps': ['"आपोआप तपासा" - quick scan (10-20 मिनिटे) फक्त तपासणीसाठी (काहीही delete करत नाही). निकाल इथे दिसेल.',
                  'Virus सापडल्यास "उघडा" → Full scan निवडा आणि तो काढू द्या.'],
        'good': '"No infection found" = virus नाही.', 'warn': []},
    en={'what': 'Microsoft\'s free virus scanner (no install).', 'when': 'Viruses, pop-ups, browser opening by itself, strange behaviour.',
        'steps': ['"Check automatically" - quick scan (10-20 minutes), detection only (deletes nothing). The result appears here.',
                  'If something is found: "Open" → choose Full scan and let it remove it.'],
        'good': '"No infection found" = no virus.', 'warn': []})
T['kvrt'] = E('virus', 'safe',
    mr={'what': 'Kaspersky चा मोफत virus removal tool (install न करता).', 'when': 'Microsoft scanner नंतरही virus संशय असेल.',
        'steps': ['"उघडा" → Accept → "Start scan". 15-60 मिनिटे.', 'सापडलेल्या threats साठी "Continue" दाबून काढू द्या.'], 'good': '"No threats" = ठीक.',
        'warn': ['Scan ला वेळ लागतो; मध्येच PC बंद करू नका.']},
    en={'what': 'Kaspersky\'s free virus removal tool (no install).', 'when': 'You still suspect a virus after the Microsoft scanner.',
        'steps': ['"Open" → Accept → "Start scan". 15-60 minutes.', 'For any threats found, press "Continue" to remove them.'], 'good': '"No threats" = fine.',
        'warn': ['The scan takes time; do not switch the PC off in the middle.']})
T['adwcleaner'] = E('virus', 'caution',
    mr={'what': 'Adware, toolbar, browser hijack (आपोआप उघडणाऱ्या ads/sites) काढतो.', 'when': 'Browser मध्ये ads, homepage बदललेले, नको ते extensions.',
        'steps': ['"उघडा" → "Scan now". यादी तपासा - ओळखीचे program untick करा.', '"Quarantine" दाबा; PC restart होईल.'],
        'good': 'Restart नंतर browser सामान्य.', 'warn': ['Clean केल्यावर PC restart मागतो - काम save करा.', 'कंपनीने दिलेले काही "PUP" programs पण काढले जातात - यादी पाहूनच quarantine करा.']},
    en={'what': 'Removes adware, toolbars and browser hijackers.', 'when': 'Ads in the browser, changed homepage, unwanted extensions.',
        'steps': ['"Open" → "Scan now". Review the list - untick programs you know.', 'Press "Quarantine"; the PC restarts.'],
        'good': 'The browser is normal after the restart.', 'warn': ['It asks to restart after cleaning - save your work.', 'Some vendor-bundled "PUP" programs are removed too - check the list before quarantining.']})
T['malwarebytes'] = E('virus', 'caution',
    mr={'what': 'Malware साठी चांगला scanner (installer; free version scan आणि clean करते).', 'when': 'इतर scanners नंतरही समस्या असेल.',
        'steps': ['"Install करा" → Free version निवडा → Scan.'], 'good': 'Threats सापडल्यास Quarantine.',
        'warn': ['या PC वर install होतो. 14 दिवसांचा "Premium trial" सुरू होतो - तो नंतर आपोआप free होतो, पैसे लागत नाहीत.']},
    en={'what': 'Good malware scanner (installer; the free version scans and cleans).', 'when': 'Problems remain after the other scanners.',
        'steps': ['"Install" → choose the free version → Scan.'], 'good': 'Quarantine whatever it finds.',
        'warn': ['Installs on this PC. A 14-day "Premium trial" starts - it turns into the free version by itself, no payment needed.']})

# ------------------------------------------------------------------ speed
T['wiztree'] = E('speed', 'safe', auto='bigfolders',
    mr={'what': 'C: drive वर कोणते folders सगळ्यात जास्त जागा घेतात ते काही सेकंदात दाखवतो.', 'when': 'C: drive भरला आहे.',
        'steps': ['"आपोआप तपासा" - सगळ्यात मोठे 15 folders इथे दिसतील.', 'हलवण्यासाठी PC Doctor च्या "C: drive जागा" page चा वापर करा (सुरक्षितपणे दुसऱ्या drive वर हलवतो).'],
        'good': 'Downloads, Videos, जुन्या backups सारखे मोठे folders हलवता / delete करता येतात.',
        'warn': ['Windows, Program Files, ProgramData मधले folders हाताने delete करू नका - Windows बिघडेल.']},
    en={'what': 'Shows in seconds which folders take the most space on C:.', 'when': 'The C: drive is full.',
        'steps': ['"Check automatically" - the 15 biggest folders appear here.', 'To move them, use PC Doctor\'s "C: drive space" page (moves them safely to another drive).'],
        'good': 'Big folders such as Downloads, Videos and old backups can be moved or deleted.',
        'warn': ['Never delete folders in Windows, Program Files or ProgramData by hand - Windows will break.']})
T['autoruns'] = E('speed', 'caution', auto='pd:speed',
    mr={'what': 'Windows सुरू होताना चालणारे सगळे programs, services, drivers.', 'when': 'PC सुरू व्हायला खूप वेळ लागतो.',
        'steps': ['सोपा मार्ग: "PC Doctor मध्ये पहा" - Startup यादीत सुचवलेले programs सुरक्षितपणे बंद करता येतात (Undo सह).',
                  'Autoruns फक्त अनुभवी लोकांसाठी: "Logon" tab मध्येच बदल करा.'],
        'good': 'Startup मध्ये फक्त antivirus, touchpad/sound driver सारखे आवश्यक programs ठेवा.',
        'warn': ['Drivers / Services / Microsoft entries untick करू नका - Windows सुरू होणार नाही.', 'Delete न करता फक्त untick करा, म्हणजे परत चालू करता येते.']},
    en={'what': 'Every program, service and driver that starts with Windows.', 'when': 'The PC takes very long to start.',
        'steps': ['Easy way: "See in PC Doctor" - turn off suggested startup programs safely (with Undo).', 'Autoruns is for experienced users: change only the "Logon" tab.'],
        'good': 'Keep only essentials (antivirus, touchpad/sound drivers) at startup.',
        'warn': ['Do not untick Drivers / Services / Microsoft entries - Windows may not start.', 'Untick instead of Delete so it can be turned back on.']})
T['procexp'] = E('speed', 'caution',
    mr={'what': 'Task Manager पेक्षा जास्त तपशील - कोणता program CPU/RAM खातो, तो कुठून चालतो.', 'when': 'PC मध्येच हळू होतो, fan सतत फिरतो, संशयास्पद program.',
        'steps': ['"उघडा" → CPU column वर click करून क्रम लावा. सगळ्यात वर असलेला program कारण.', 'Process वर right-click → "Check VirusTotal" ने तो सुरक्षित आहे का पाहा.'],
        'good': 'Idle असताना CPU 10% पेक्षा कमी असावा.', 'warn': ['System, csrss, wininit, lsass, svchost सारखे Windows processes "Kill" करू नका - PC बंद पडेल.']},
    en={'what': 'More detail than Task Manager - which program uses CPU/RAM and where it runs from.', 'when': 'The PC slows down, the fan runs all the time, a suspicious program.',
        'steps': ['"Open" → click the CPU column to sort. The top program is the cause.', 'Right-click a process → "Check VirusTotal" to see if it is safe.'],
        'good': 'At idle the CPU should be under 10%.', 'warn': ['Do not "Kill" Windows processes such as System, csrss, wininit, lsass, svchost - the PC will crash.']})
T['bcu'] = E('speed', 'caution', auto='pd:advisor',
    mr={'what': 'एकाच वेळी अनेक नको असलेले programs पूर्ण काढतो (उरलेल्या files सह).', 'when': 'PC मध्ये खूप bloatware / trial programs.',
        'steps': ['सोपा मार्ग: "PC Doctor मध्ये पहा" - "OS / Apps सल्ला" मध्ये काढण्यासारखे apps आणि हलके पर्याय दिसतात.',
                  'BCU: नको असलेल्या programs वर tick → "Uninstall". शेवटी उरलेल्या files काढू द्या.'],
        'good': '', 'warn': ['Driver, Microsoft Visual C++ / .NET, antivirus काढू नका.', 'नाव ओळखत नसाल तर काढू नका.']},
    en={'what': 'Removes many unwanted programs at once, leftovers included.', 'when': 'Lots of bloatware / trial programs.',
        'steps': ['Easy way: "See in PC Doctor" - "OS / Apps advice" lists apps to remove and lighter alternatives.', 'BCU: tick unwanted programs → "Uninstall", then let it remove leftovers.'],
        'good': '', 'warn': ['Do not remove drivers, Microsoft Visual C++ / .NET or the antivirus.', 'If you do not recognise a name, leave it.']})

# ------------------------------------------------------------------ drivers
T['sdio'] = E('drivers', 'caution', auto='pd:drivers',
    mr={'what': 'Internet शिवाय drivers (pendrive वरच्या driver packs मधून).', 'when': 'नवीन Windows नंतर WiFi / LAN / sound / display चालत नाही.',
        'steps': ['सुरक्षित मार्ग: "PC Doctor मध्ये पहा" - कोणते drivers नाहीत ते तपासून योग्य क्रम सुचवतो.',
                  'SDIO मध्ये: आधी "Create restore point" वर tick, मग फक्त "Missing" (नसलेले) drivers निवडा → Install.'],
        'good': 'Device Manager मध्ये पिवळे उद्गारचिन्ह नसावे.',
        'warn': ['"Select all" करून सगळे drivers update करू नका - चालू असलेले drivers बिघडू शकतात.', 'Laptop च्या display / touchpad साठी कंपनीच्या website वरचा driver जास्त योग्य.']},
    en={'what': 'Drivers without internet (from the driver packs on the USB).', 'when': 'WiFi / LAN / sound / display do not work after a new Windows.',
        'steps': ['Safe way: "See in PC Doctor" - finds missing drivers and suggests the right order.', 'In SDIO: tick "Create restore point" first, then select only "Missing" drivers → Install.'],
        'good': 'No yellow exclamation marks in Device Manager.',
        'warn': ['Do not "Select all" and update everything - working drivers can break.', 'For laptop display / touchpad the maker\'s website driver is the better choice.']})
T['doubledriver'] = E('drivers', 'safe',
    mr={'what': 'या PC चे drivers backup / restore.', 'when': 'Windows reinstall करण्याआधी.',
        'steps': ['सोपा मार्ग: PC Doctor → दुरुस्ती → "Drivers backup" (Windows चा DISM वापरतो).', 'Double Driver: Backup → Scan Current System → Backup Now.'],
        'good': '', 'warn': []},
    en={'what': 'Backs up / restores this PC\'s drivers.', 'when': 'Before reinstalling Windows.',
        'steps': ['Easy way: PC Doctor → Repair → "Drivers backup" (uses Windows DISM).', 'Double Driver: Backup → Scan Current System → Backup Now.'],
        'good': '', 'warn': []})

# ------------------------------------------------------------------ disk / recovery
T['victoria'] = E('disk', 'danger',
    mr={'what': 'Hard disk चे bad sectors शोधणारा surface test.', 'when': 'CrystalDiskInfo "Caution" दाखवतो, disk मधून आवाज, files खराब होतात.',
        'steps': ['"उघडा" → उजवीकडे disk निवडा → "Test & Repair" tab → **"Ignore"** निवडलेले आहे याची खात्री करा → Scan.',
                  'रंग: राखाडी = ठीक, हिरवा/नारिंगी = हळू, लाल/निळा "Err" = bad sector.'],
        'good': 'लाल / Err नाहीत = disk surface ठीक. अनेक लाल ब्लॉक्स = disk बदला.',
        'warn': ['फक्त "Ignore" mode वापरा. "Erase", "Write", "Refresh" mode disk वरचा data पुसतात!', 'खराब disk वर आधी data copy करा, मगच test - test मुळे disk अजून बिघडू शकते.']},
    en={'what': 'Surface test that finds bad sectors on a hard disk.', 'when': 'CrystalDiskInfo shows "Caution", the disk makes noise, files get corrupted.',
        'steps': ['"Open" → pick the disk on the right → "Test & Repair" tab → make sure **"Ignore"** is selected → Scan.', 'Colours: grey = fine, green/orange = slow, red/blue "Err" = bad sector.'],
        'good': 'No red / Err = the surface is fine. Many red blocks = replace the disk.',
        'warn': ['Use only "Ignore" mode. "Erase", "Write" and "Refresh" modes wipe data on the disk!', 'On a failing disk copy the data first, then test - the test itself can make it worse.']})
T['hdtune'] = E('disk', 'caution',
    mr={'what': 'Disk health, वेग आणि error scan (installer).', 'when': 'Disk तपासणी - सोपा पर्याय.',
        'steps': ['"Install करा" → उघडा → "Error Scan" tab → Start (Quick scan नको).'], 'good': 'सगळे हिरवे चौकोन = ठीक; लाल = bad sectors.',
        'warn': ['या PC वर install होतो.']},
    en={'what': 'Disk health, speed and error scan (installer).', 'when': 'An easy disk check.',
        'steps': ['"Install" → open → "Error Scan" tab → Start (not Quick scan).'], 'good': 'All green squares = fine; red = bad sectors.',
        'warn': ['Installs on this PC.']})
T['hddscan'] = E('disk', 'danger',
    mr={'what': 'Disk surface test आणि SMART.', 'when': 'Victoria ऐवजी सोपा पर्याय.',
        'steps': ['"उघडा" → disk निवडा → "Surface Tests" → **Read** निवडा → Add test.'], 'good': 'Bad blocks नाहीत = ठीक.',
        'warn': ['फक्त "Read" / "Verify" test. "Erase" test data पुसतो!']},
    en={'what': 'Disk surface test and SMART.', 'when': 'An easier alternative to Victoria.',
        'steps': ['"Open" → pick the disk → "Surface Tests" → choose **Read** → Add test.'], 'good': 'No bad blocks = fine.',
        'warn': ['Use only "Read" / "Verify". The "Erase" test wipes data!']})
T['dmde'] = E('disk', 'danger',
    mr={'what': 'Format झालेल्या / गायब झालेल्या partition मधून files परत मिळवतो.', 'when': 'Drive "format करा" विचारतो, partition गायब, चुकून format केले.',
        'steps': ['"उघडा" → disk निवडा → partition निवडा → "Open Volume". Files दिसल्यास त्यावर right-click → "Recover" → **दुसऱ्या drive वर** save करा.',
                  'Free version एका वेळी एका folder मधील files recover करू देते.'],
        'good': '',
        'warn': ['ज्या disk वरून files परत घ्यायच्या आहेत त्या disk वर काहीही save / install करू नका - files कायमच्या जातील.', 'Recover केलेल्या files नेहमी दुसऱ्या disk / pendrive वर save करा.', '"Partition write / Apply" चे पर्याय वापरू नका.']},
    en={'what': 'Gets files back from formatted or lost partitions.', 'when': 'The drive asks to be formatted, a partition vanished, formatted by mistake.',
        'steps': ['"Open" → pick the disk → pick the partition → "Open Volume". Right-click the files → "Recover" → save to **another drive**.', 'The free version recovers one folder at a time.'],
        'good': '',
        'warn': ['Do not save or install anything on the disk you are recovering from - the files would be lost for good.', 'Always save recovered files to a different disk / USB.', 'Do not use the "Partition write / Apply" options.']})
T['testdisk'] = E('disk', 'danger',
    mr={'what': 'PhotoRec: delete झालेले photos, documents परत आणतो. TestDisk: हरवलेले partition परत.', 'when': 'चुकून delete, memory card / pendrive format.',
        'steps': ['"उघडा" (QPhotoRec) → disk निवडा → "File Formats" मध्ये हवे प्रकार → खाली "Destination" = **दुसरा drive** → Search.'],
        'good': 'Files मूळ नावाशिवाय (f12345.jpg) परत मिळतात - folder मध्ये पाहून निवडा.',
        'warn': ['Destination folder नेहमी दुसऱ्या drive वर द्या.', 'TestDisk (text window) मध्ये "Write" फक्त माहिती असल्यासच - चुकीचे partition लिहिल्यास data जातो.']},
    en={'what': 'PhotoRec: brings back deleted photos and documents. TestDisk: restores lost partitions.', 'when': 'Deleted by mistake, formatted memory card / USB.',
        'steps': ['"Open" (QPhotoRec) → pick the disk → choose types under "File Formats" → set "Destination" to **another drive** → Search.'],
        'good': 'Files come back without original names (f12345.jpg) - browse the folder to pick them.',
        'warn': ['Always choose a destination on a different drive.', 'In TestDisk (text window) use "Write" only if you know what you are doing - a wrong partition table loses data.']})
T['recuva'] = E('disk', 'caution',
    mr={'what': 'नुकत्याच delete झालेल्या files सोप्या पद्धतीने परत.', 'when': 'Recycle Bin मधूनही delete झाले.',
        'steps': ['"उघडा" → wizard मध्ये file प्रकार आणि जागा निवडा → Start. हिरव्या (Excellent) files Recover करा → दुसऱ्या drive वर.'],
        'good': 'हिरवे = पूर्ण परत, लाल = खराब.', 'warn': ['Recover केलेल्या files दुसऱ्या drive वर save करा.']},
    en={'what': 'Easy recovery of recently deleted files.', 'when': 'Deleted from the Recycle Bin too.',
        'steps': ['"Open" → choose file type and location in the wizard → Start. Recover the green (Excellent) files → to another drive.'],
        'good': 'Green = fully recoverable, red = damaged.', 'warn': ['Save recovered files to a different drive.']})

# ------------------------------------------------------------------ partition / backup
for tid, nm in (('aomei-pa', 'AOMEI Partition Assistant'), ('minitool-pw', 'MiniTool Partition Wizard')):
    T[tid] = E('backup', 'danger',
        mr={'what': 'Partition लहान/मोठे करणे, नवीन drive बनवणे, disk SSD वर हलवणे (installer).', 'when': 'C: drive लहान आहे, D: मधून जागा द्यायची, HDD → SSD.',
            'steps': ['सोपा मार्ग: PC Doctor → "C: drive जागा" → "नवीन DATA drive बनवा" (सुरक्षित).', '"Install करा" → बदल निवडा → शेवटी "Apply" दाबल्यावरच बदल होतात.'],
            'good': '',
            'warn': ['Partition बदलण्याआधी महत्त्वाच्या data चा backup घ्या.', 'काम चालू असताना वीज जाऊ नये - laptop charger / UPS.', 'System Reserved / EFI / Recovery partitions ला हात लावू नका.']},
        en={'what': 'Resize partitions, create drives, move a disk to an SSD (installer).', 'when': 'C: is too small, take space from D:, HDD → SSD.',
            'steps': ['Easy way: PC Doctor → "C: drive space" → "Create a DATA drive" (safe).', '"Install" → plan the changes → nothing changes until you press "Apply".'],
            'good': '',
            'warn': ['Back up important data before changing partitions.', 'Power must not fail during the job - laptop charger / UPS.', 'Do not touch System Reserved / EFI / Recovery partitions.']})
for tid in ('aomei-backupper', 'hasleo-backup'):
    T[tid] = E('backup', 'caution',
        mr={'what': 'पूर्ण Windows / disk चा image backup आणि restore (installer).', 'when': 'नवीन SSD वर Windows हलवायचे, मोठ्या दुरुस्तीआधी पूर्ण backup.',
            'steps': ['"Install करा" → "System Backup" → backup external disk वर ठेवा.', 'Windows चालत नसल्यास pendrive वरून boot → Rescuezilla ने restore करता येतो.'],
            'good': '', 'warn': ['Restore करताना निवडलेल्या disk वरचा सगळा data बदलतो - disk नीट निवडा.']},
        en={'what': 'Image backup and restore of Windows / whole disks (installer).', 'when': 'Moving Windows to a new SSD, a full backup before a big repair.',
            'steps': ['"Install" → "System Backup" → keep the backup on an external disk.', 'If Windows will not start, boot the USB → Rescuezilla can restore it.'],
            'good': '', 'warn': ['Restoring replaces everything on the chosen disk - choose the disk carefully.']})

# ------------------------------------------------------------------ windows tools
T['produkey'] = E('windows', 'safe', auto='keys',
    mr={'what': 'Windows / Office ची product key दाखवतो.', 'when': 'Windows reinstall करण्याआधी key लिहून ठेवायची.',
        'steps': ['"आपोआप तपासा" - BIOS मधली Windows key (नवीन laptops) आणि ProduKey ने सापडलेल्या keys इथे दिसतील आणि Reports मध्ये save होतील.'],
        'good': 'BIOS मध्ये key असल्यास Windows reinstall नंतर आपोआप activate होते.',
        'warn': ['Product key गुप्त ठेवा - customer शिवाय कोणालाही देऊ नका.']},
    en={'what': 'Shows the Windows / Office product key.', 'when': 'Note the key down before reinstalling Windows.',
        'steps': ['"Check automatically" - the Windows key stored in the BIOS (newer laptops) and keys found by ProduKey appear here and are saved in Reports.'],
        'good': 'With a key in the BIOS, Windows activates by itself after a reinstall.',
        'warn': ['Keep product keys private - do not share them with anyone but the customer.']})
T['dismpp'] = E('windows', 'caution', auto='pd:repair',
    mr={'what': 'Windows साफसफाई, updates/drivers/apps चे व्यवस्थापन.', 'when': 'अनुभवी लोकांसाठी - Windows मधील जुने update files साफ करणे.',
        'steps': ['सोपा मार्ग: "PC Doctor मध्ये पहा" - दुरुस्ती आणि वेग page मध्ये सुरक्षित cleanup.', 'Dism++: "Space Cleanup" → Scan → Clean.'],
        'good': '', 'warn': ['"Drivers" / "Apps" / "Optimizations" मध्ये न समजलेल्या गोष्टी बदलू नका.']},
    en={'what': 'Windows cleanup and management of updates/drivers/apps.', 'when': 'For experienced users - cleaning old Windows update files.',
        'steps': ['Easy way: "See in PC Doctor" - safe cleanup on the Repair and Speed pages.', 'Dism++: "Space Cleanup" → Scan → Clean.'],
        'good': '', 'warn': ['Do not change things you do not understand under "Drivers", "Apps" or "Optimizations".']})
T['ntpwedit'] = E('windows', 'danger',
    mr={'what': 'विसरलेला local Windows password काढतो.', 'when': 'Customer स्वतःच्या PC चा password विसरला.',
        'steps': ['Pendrive वरून boot → Hiren\'s BootCD PE → NTPWEdit उघडा.', 'User निवडा → "Change password" → रिकामे ठेवून OK → "Save changes".'],
        'good': 'पुढच्या start ला password न विचारता login.',
        'warn': ['फक्त PC मालकाच्या परवानगीनेच वापरा.', 'Microsoft account (email ने login) वर चालत नाही - तिथे account.live.com/password/reset.', 'BitLocker चालू असेल तर आधी recovery key लागते.']},
    en={'what': 'Removes a forgotten local Windows password.', 'when': 'The customer forgot the password of their own PC.',
        'steps': ['Boot the USB → Hiren\'s BootCD PE → open NTPWEdit.', 'Pick the user → "Change password" → leave empty → OK → "Save changes".'],
        'good': 'The next start logs in without a password.',
        'warn': ['Use only with the owner\'s permission.', 'It does not work for Microsoft accounts (email login) - use account.live.com/password/reset.', 'With BitLocker on, the recovery key is needed first.']})
T['winntsetup'] = E('windows', 'danger',
    mr={'what': 'Windows थेट दुसऱ्या disk / partition वर install करतो.', 'when': 'अनुभवी लोकांसाठी - PE मधून Windows install.',
        'steps': ['Hiren\'s PE मध्ये उघडा → Windows ISO मधील install.wim निवडा → boot व install drive निवडा → Setup.'],
        'good': '', 'warn': ['निवडलेली partition format होते - data पुसला जातो.']},
    en={'what': 'Installs Windows directly to another disk / partition.', 'when': 'For experienced users - installing Windows from PE.',
        'steps': ['Open in Hiren\'s PE → pick install.wim from the Windows ISO → choose boot and install drives → Setup.'],
        'good': '', 'warn': ['The chosen partition is formatted - its data is erased.']})
for tid in ('bootice', 'easyuefi', 'visualbcd'):
    T[tid] = E('windows', 'danger',
        mr={'what': 'Boot entries / boot record (MBR, UEFI, BCD) बदलणे.', 'when': 'अनुभवी लोकांसाठी - boot समस्या.',
            'steps': ['सोपा मार्ग: pendrive वरून boot → Hiren\'s PE → PCDoctor-Rescue.cmd → "Fix boot".'], 'good': '',
            'warn': ['चुकीचा बदल केल्यास Windows सुरूच होत नाही.', 'बदलण्याआधी backup / export घ्या.']},
        en={'what': 'Edits boot entries / boot records (MBR, UEFI, BCD).', 'when': 'For experienced users - boot problems.',
            'steps': ['Easy way: boot the USB → Hiren\'s PE → PCDoctor-Rescue.cmd → "Fix boot".'], 'good': '',
            'warn': ['A wrong change stops Windows from starting.', 'Back up / export before changing anything.']})

# ------------------------------------------------------------------ network
T['winmtr'] = E('network', 'safe', auto='network',
    mr={'what': 'Internet कुठे अडते ते शोधतो (router, ISP, website).', 'when': 'Internet चालत नाही / खूप हळू / मध्येच तुटते.',
        'steps': ['"आपोआप तपासा" - router, internet आणि DNS तपासून समस्या कुठे आहे ते इथे सांगेल.', 'WinMTR: host मध्ये google.com → Start. "Loss %" जास्त असलेली पहिली ओळ म्हणजे अडचणीची जागा.'],
        'good': 'पहिल्या ओळीत (router) loss = घरातले WiFi/cable. पुढच्या ओळींत = ISP.',
        'warn': []},
    en={'what': 'Finds where the internet connection breaks (router, ISP, website).', 'when': 'No internet, very slow, or it keeps dropping.',
        'steps': ['"Check automatically" - checks the router, internet and DNS and tells you where the problem is.', 'WinMTR: host google.com → Start. The first row with a high "Loss %" is where it breaks.'],
        'good': 'Loss on the first row (router) = WiFi/cable at home. Later rows = the ISP.',
        'warn': []})
T['advipscanner'] = E('network', 'safe',
    mr={'what': 'Network वरचे सगळे devices (printer, CCTV, PCs) शोधतो.', 'when': 'Printer चा IP हवा, network वर कोण आहे ते पाहायचे.',
        'steps': ['"उघडा" → "Scan".'], 'good': '', 'warn': []},
    en={'what': 'Finds every device on the network (printers, CCTV, PCs).', 'when': 'You need a printer\'s IP or want to see who is on the network.',
        'steps': ['"Open" → "Scan".'], 'good': '', 'warn': []})
T['rustdesk'] = E('network', 'caution',
    mr={'what': 'Remote support - दुसऱ्या ठिकाणाहून हा PC चालवता येतो (मोफत).', 'when': 'Customer ला दूरून मदत करायची.',
        'steps': ['"उघडा" → दिसणारा ID आणि password मदत करणाऱ्याला द्या.', 'काम झाल्यावर RustDesk बंद करा.'],
        'good': '',
        'warn': ['ID / password फक्त ओळखीच्या technician ला द्या - फोनवरून मागणाऱ्या अनोळखी लोकांना कधीही नाही (fraud).', 'काम झाल्यावर program बंद करा.']},
    en={'what': 'Remote support - someone else can control this PC (free).', 'when': 'Helping a customer from a distance.',
        'steps': ['"Open" → give the shown ID and password to the helper.', 'Close RustDesk when finished.'],
        'good': '',
        'warn': ['Give the ID / password only to a technician you know - never to strangers who ask on the phone (fraud).', 'Close the program when done.']})

# ------------------------------------------------------------------ apps
APPS = {
    '7zip': ('safe', 'Zip / RAR / 7z files उघडतो आणि बनवतो (installer).', 'Opens and creates zip / rar / 7z files (installer).'),
    'notepadpp': ('safe', 'Text / config files साठी चांगला editor.', 'A good editor for text and config files.'),
    'everything': ('safe', 'PC मधली कोणतीही file एका सेकंदात नावाने शोधतो.', 'Finds any file on the PC by name in a second.'),
    'vlc': ('safe', 'सगळ्या प्रकारचे video / audio चालवणारा player.', 'Plays every kind of video / audio.'),
    'explorerpp': ('safe', 'File manager - Hiren\'s PE मध्ये files copy करायला उपयोगी.', 'File manager - handy for copying files in Hiren\'s PE.'),
    'sumatra': ('safe', 'हलका PDF reader (Adobe पेक्षा खूप हलका) - installer.', 'Very light PDF reader (much lighter than Adobe) - installer.'),
    'libreoffice': ('safe', 'मोफत Office (Word / Excel / PowerPoint files) - installer.', 'Free office suite (Word / Excel / PowerPoint files) - installer.'),
    'qbittorrent': ('safe', 'Torrent downloader (जाहिराती नाहीत) - installer.', 'Torrent downloader (no ads) - installer.'),
    'firefox': ('safe', 'Browser - Chrome जड वाटत असल्यास पर्याय - installer.', 'Browser - an alternative when Chrome feels heavy - installer.'),
}
for tid, (risk, mr, en) in APPS.items():
    inst = tid in ('7zip', 'sumatra', 'libreoffice', 'qbittorrent', 'firefox')
    T[tid] = E('apps', 'caution' if inst else risk,
        mr={'what': mr, 'when': '', 'steps': ['"Install करा" - या PC वर install होईल.' if inst else '"उघडा" - install न करता चालतो.'], 'good': '',
            'warn': ['या PC वर install होतो.'] if inst else []},
        en={'what': en, 'when': '', 'steps': ['"Install" - installs on this PC.' if inst else '"Open" - runs without installing.'], 'good': '',
            'warn': ['Installs on this PC.'] if inst else []})
T['rufus'] = E('apps', 'danger',
    mr={'what': 'Windows / Linux ची bootable pendrive बनवतो.', 'when': 'एखाद्या PC साठी साधी Windows install pendrive हवी.',
        'steps': ['"उघडा" → Device मध्ये **दुसरा** (रिकामा) pendrive निवडा → SELECT → ISO → START.'],
        'good': '', 'warn': ['निवडलेला pendrive पूर्ण पुसला जातो. Device यादीत हा Sanjeevani pendrive निवडू नका!']},
    en={'what': 'Makes a bootable Windows / Linux USB.', 'when': 'You need a plain Windows install USB for a PC.',
        'steps': ['"Open" → pick **another** (empty) USB under Device → SELECT → ISO → START.'],
        'good': '', 'warn': ['The chosen USB is erased completely. Do not pick this Sanjeevani USB in the Device list!']})

# ------------------------------------------------------------------ boot menu (ISOs)
BOOT = {
    'hbcd': ('safe', 'Windows सारखा desktop pendrive वरून - Windows सुरू होत नसताना files copy, password reset, PC Doctor Rescue.', 'A Windows-like desktop from the USB - copy files, reset passwords and run PC Doctor Rescue when Windows will not start.',
             'Windows सुरूच होत नाही, blue screen loop, data काढायचा.', 'Windows will not start, blue-screen loop, data must be copied off.'),
    'systemrescue': ('caution', 'Linux वर आधारित दुरुस्ती toolkit (अनुभवी लोकांसाठी).', 'Linux-based repair toolkit (for experienced users).', 'Hiren\'s PE चालत नसेल तर.', 'When Hiren\'s PE does not work.'),
    'memtest86plus': ('safe', 'RAM चा पूर्ण test (जुन्या आणि नवीन PCs).', 'Full RAM test (old and new PCs).', 'वारंवार blue screen, अचानक restart.', 'Repeated blue screens, sudden restarts.'),
    'memtest86': ('safe', 'RAM test - नवीन UEFI PCs साठी.', 'RAM test - for newer UEFI PCs.', 'MemTest86+ सुरू होत नसेल तर.', 'When MemTest86+ does not start.'),
    'gparted': ('danger', 'Partitions बदलणे (Linux).', 'Partition editor (Linux).', 'Windows मधून partition बदलता येत नसेल तर.', 'When partitions cannot be changed from Windows.'),
    'clonezilla': ('danger', 'पूर्ण disk ची हुबेहूब copy / image.', 'Exact copy / image of a whole disk.', 'HDD → SSD हलवणे, पूर्ण backup.', 'Moving HDD → SSD, full backup.'),
    'rescuezilla': ('caution', 'सोप्या खिडक्यांसह disk backup / restore / clone.', 'Disk backup / restore / clone with simple windows.', 'Windows चालत नसताना पूर्ण backup, नवीन SSD वर हलवणे.', 'Full backup when Windows will not start, moving to a new SSD.'),
    'supergrub2': ('safe', 'Disk वरचे Windows / Linux शोधून सुरू करतो.', 'Finds and starts Windows / Linux on the disk.', 'Boot menu खराब झाल्यामुळे Windows दिसत नाही.', 'Windows does not show up because the boot menu is broken.'),
    'bootrepair': ('caution', 'Linux / GRUB boot दुरुस्ती.', 'Linux / GRUB boot repair.', 'Linux + Windows dual boot बिघडले.', 'Linux + Windows dual boot is broken.'),
    'krd': ('safe', 'Windows सुरू न करता virus scan (Kaspersky).', 'Virus scan without starting Windows (Kaspersky).', 'Virus मुळे Windows मध्ये scan करता येत नाही.', 'A virus stops scanning inside Windows.'),
    'shredos': ('danger', 'Disk कायमचा पुसतो (data परत मिळत नाही).', 'Wipes disks for good (data cannot be recovered).', 'PC / disk विकण्याआधी.', 'Before selling a PC / disk.'),
    'win11': ('caution', 'Windows 11 install / repair.', 'Windows 11 install / repair.', 'नवीन Windows install, किंवा "Repair your computer".', 'A fresh Windows install, or "Repair your computer".'),
    'mint-xfce': ('caution', 'जुन्या / हळू PC साठी हलके Linux.', 'Light Linux for old / slow PCs.', 'Windows खूप जड वाटते असा जुना PC.', 'An old PC where Windows is too heavy.'),
    'lazesoft': ('caution', 'Windows boot दुरुस्ती आणि password reset.', 'Windows boot repair and password reset.', 'Windows सुरू होत नाही.', 'Windows will not start.'),
    'hdat2': ('danger', 'Disk bad sector test (DOS).', 'Disk bad-sector test (DOS).', 'जुने IDE / SATA disks.', 'Old IDE / SATA disks.'),
}
BOOT_WARN = {
    'gparted': (['चुकीचे partition बदलल्यास data आणि Windows जातात. आधी backup.'], ['Changing the wrong partition loses data and Windows. Back up first.']),
    'clonezilla': (['Source आणि Target उलटे निवडल्यास जुना disk पुसला जातो - दोनदा तपासा.'], ['Swapping source and target erases the original disk - check twice.']),
    'rescuezilla': (['Restore / clone करताना निवडलेल्या target disk वरचे सगळे पुसले जाते.'], ['Restore / clone erases everything on the chosen target disk.']),
    'shredos': (['निवडलेला disk कायमचा पुसला जातो. हा pendrive आणि दुसरे disks काढून ठेवा.'], ['The chosen disk is erased for good. Unplug this USB and other disks first.']),
    'win11': (['Install करताना partition delete / format केल्यास त्यातला data जातो.'], ['Deleting / formatting a partition during install erases its data.']),
    'mint-xfce': (['"Erase disk and install" Windows आणि data पुसते.'], ['"Erase disk and install" removes Windows and data.']),
    'hdat2': (['फक्त Read / Verify test वापरा.'], ['Use only the Read / Verify tests.']),
    'systemrescue': (['Linux commands माहिती असल्यासच.'], ['Only if you know Linux commands.']),
    'bootrepair': (['Windows-only PC वर चालवू नका.'], ['Do not run it on a Windows-only PC.']),
    'lazesoft': ([], []),
}
for tid, (risk, mr, en, wmr, wen) in BOOT.items():
    w = BOOT_WARN.get(tid, ([], []))
    T[tid] = E('bootmenu', risk, boot=True,
        mr={'what': mr, 'when': wmr, 'steps': BOOT_STEPS_MR, 'good': '', 'warn': w[0]},
        en={'what': en, 'when': wen, 'steps': BOOT_STEPS_EN, 'good': '', 'warn': w[1]})

doc = {'_comment': 'Generated by build/make_toolguide.py - edit there.', 'groups': [{'id': g, 'mr': m, 'en': e} for g, m, e in GROUPS], 'tools': T}
txt = json.dumps(doc, ensure_ascii=False, indent=1).replace('**', '')
with open(OUT, 'w', encoding='utf-8') as f:
    f.write(txt)
print('wrote', OUT, len(T), 'entries')
