"""Writes the user guide in three languages:
   kit/Sanjeevani/Docs/guide-en.html, guide-mr.html, guide-hi.html
Setup copies the one in the chosen language to the USB root ("READ-ME - ...html") and PC Doctor's
Tools guide opens it. Edit the texts here, then run:  python3 build/make_guides.py"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, 'kit', 'Sanjeevani', 'Docs')

LOGO = ('<svg width="44" height="47" viewBox="0 0 120 128" aria-hidden="true"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#5EEAD4"/><stop offset="1" stop-color="#0D9488"/></linearGradient></defs>'
        '<path d="M60 0 116 20 110 84 60 128 10 84 4 20Z" fill="url(#g)"/>'
        '<polyline points="18,62 42,62 52,38 66,88 78,52 86,62 104,62" fill="none" stroke="#0B1220" stroke-width="10" stroke-linejoin="round" stroke-linecap="round"/></svg>')

CSS = """
*{box-sizing:border-box}
body{font-family:'Segoe UI','Nirmala UI',system-ui,sans-serif;background:#f4f7fb;color:#0f172a;margin:0;line-height:1.7;font-size:15.5px}
header{background:linear-gradient(135deg,#0b1220 0%,#0f2a3a 100%);color:#fff;padding:34px 0 30px}
.w{max-width:960px;margin:auto;padding:0 26px}
.brand{display:flex;align-items:center;gap:14px}
.brand h1{margin:0;font-size:30px;letter-spacing:.2px}
.brand small{display:block;color:#2dd4bf;font-weight:600;letter-spacing:2px;font-size:11px}
header p{margin:12px 0 0;color:#94a3b8;max-width:720px}
nav{margin-top:18px;display:flex;flex-wrap:wrap;gap:8px}
nav a{color:#cbd5e1;text-decoration:none;font-size:13px;border:1px solid #23344f;border-radius:999px;padding:4px 12px}
nav a:hover{border-color:#2dd4bf;color:#fff}
h2{margin:40px 0 12px;font-size:22px;display:flex;align-items:center;gap:10px}
h2 .n{background:#0d9488;color:#fff;border-radius:8px;font-size:14px;width:28px;height:28px;display:inline-flex;align-items:center;justify-content:center}
.card{background:#fff;border:1px solid #e3e9f2;border-radius:14px;padding:16px 20px;margin:12px 0}
.warn{border-left:5px solid #f59e0b} .danger{border-left:5px solid #e11d48} .tip{border-left:5px solid #14b8a6}
table{width:100%;border-collapse:separate;border-spacing:0;background:#fff;border:1px solid #e3e9f2;border-radius:14px;overflow:hidden}
td,th{border-bottom:1px solid #edf1f7;padding:10px 14px;text-align:left;vertical-align:top}
tr:last-child td{border-bottom:none} th{background:#f1f5f9;font-weight:600}
td:first-child{font-weight:600;white-space:nowrap}
code,kbd{background:#e8eef6;border-radius:6px;padding:1px 7px;font-family:Consolas,monospace;font-size:13px}
ol li,ul li{margin:5px 0}
footer{color:#64748b;font-size:13px;margin:40px 0 30px}
@media print{header{background:#0b1220 !important;-webkit-print-color-adjust:exact}}
"""

L = {}  # language -> dict of texts (lists of HTML strings)

L['en'] = dict(
    lang='en', title='Sanjeevani Rescue USB - Guide', brand='Sanjeevani Rescue USB',
    tagline='A pendrive to check, repair and speed up PCs · only free and legal tools · English / मराठी / हिन्दी',
    nav=['Make the USB', 'Boot', 'Boot menu', 'PC Doctor', 'Assistant', 'Your apps', 'Problems', 'Safety'],
    s1='Make the USB', s1_steps=[
        'Take a 64 GB USB 3.x pendrive (256 GB for the offline driver packs). <b>Everything on it will be erased.</b>',
        'Extract the kit zip (right-click → Extract All).',
        'Double-click <code>SETUP.cmd</code> and allow Administrator.',
        'Choose the language (English / मराठी / हिन्दी) - PC Doctor and this guide use it.',
        'Type the pendrive\'s <b>Disk number</b>, then type <code>ERASE</code>.',
        'Answer the optional downloads: Windows 11 ISO (7.5 GB), Linux Mint (3 GB), offline AI for the Assistant (3.2 GB), offline driver packs (70 GB).',
        'It takes 30 minutes to 2 hours depending on the internet. If some tool needs a manual download, its list opens by itself at the end.'],
    s1_update='<b>Update:</b> run <code>Sanjeevani\\Setup\\UPDATE.cmd</code> on the USB at any time. Only newer versions are downloaded; nothing is erased.',
    s1_lock='<b>Write-protect switch:</b> if the pendrive has a lock switch, keep it <b>locked</b> on customers\' PCs - viruses cannot write to it. Unlock it only on your own clean PC for updates. Even without a switch, PC Doctor checks the USB for changes made by viruses every time it starts.',
    s2='Boot from the USB', s2_steps=[
        'Switch the PC off and plug in the pendrive.',
        'Press the Boot Menu key right after pressing power (HP <kbd>F9</kbd>, Dell <kbd>F12</kbd>, Lenovo <kbd>F12</kbd>, Asus <kbd>Esc</kbd> ...). Full list: <a href="boot-keys.html">boot-keys.html</a>.',
        'The Sanjeevani menu appears. Choose a tool with ↑ ↓ and press Enter; a short description shows below.',
        'If a Secure Boot error appears, follow the "Enroll key" steps in boot-keys.html - needed only once.'],
    s3='Tools in the boot menu', s3_head=('Tool', 'When to use it'), s3_rows=[
        ("Hiren's BootCD PE", 'Windows will not start, data must be copied off, reset the password of the owner\'s PC. Run <code>PCDoctor-Rescue.cmd</code> from the USB inside it.'),
        ('SystemRescue', 'Linux toolkit: recover deleted files (PhotoRec), bring back partitions (TestDisk), disk checks.'),
        ('MemTest86+ / MemTest86', 'Blue screens, sudden restarts or hangs - test the RAM. A single red error means faulty RAM.'),
        ('GParted', 'Create, shrink or grow partitions.'),
        ('Clonezilla / Rescuezilla', 'Clone the whole Windows from an HDD to a new SSD, or back up a full disk.'),
        ('Super Grub2 / Boot-Repair', '"No bootable device" because the boot loader is broken.'),
        ('Kaspersky Rescue Disk', 'Windows is so infected that an antivirus cannot run inside it.'),
        ('ShredOS', '<b style="color:#e11d48">Dangerous:</b> wipes a disk for good. Only before selling a PC.'),
        ('Windows 11', 'Fresh install, or open the ISO inside Windows → <code>setup.exe</code> → "Keep files and apps" (repairs without losing data).'),
        ('Linux Mint XFCE', 'A light, free OS for old PCs with little RAM. Try it without installing.')],
    s4='PC Doctor (inside Windows)', s4_intro='Open the USB and double-click <code>START-Sanjeevani.cmd</code> (allow Administrator).',
    s4_items=[
        '<b>Health Check:</b> Quick Scan (2 minutes) or Deep Scan (with system files). Shows a health score, why it is not 100 and a fix button next to every finding.',
        '<b>One-Click Optimize:</b> restore point → junk cleanup → unneeded startup off → lighter effects → power plan → ads / bloatware removed → report.',
        '<b>Repair:</b> DISM + SFC (damaged system files), disk check, Windows Update reset, network reset, Defender, drivers, registry check (settings changed by viruses).',
        '<b>Speed Up:</b> startup programs, tweaks, bloatware. <b>Every change can be undone.</b>',
        '<b>Disk Space:</b> move Desktop, Documents, Downloads, Photos and your own folders in C:\\ to another drive; without a second drive, shrink C: and create a DATA drive.',
        '<b>OS &amp; Apps Advice:</b> does Windows 11 fit, which OS suits this PC, which apps to remove and lighter alternatives, RAM / SSD upgrades.',
        '<b>Tools Guide:</b> 60+ tools - what each does, when and how to use it, with warnings. "Check automatically" runs the tool and explains the result (disk, battery, temperature, RAM, crashes, viruses, internet, C: drive). The raw Tools / Installers folders on the USB are hidden - use the tools from here.',
        '<b>Report:</b> an HTML report for the customer, saved in the USB\'s <code>Reports\\</code> folder.',
        '<b>Language:</b> switch English / मराठी / हिन्दी in the title bar at any time.'],
    s5='Assistant - describe the problem, it fixes it', s5_items=[
        'Type the problem in your own words - English, Marathi, Hindi or Roman script ("net nahi chal raha", "laptop खूप गरम होतो", "printer not printing").',
        'You allow it once. A restore point is made, then everything is automatic: the Assistant understands the problem, <b>checks whether it really exists on this PC</b>, fixes it, checks again, and moves on to the next likely cause if the first one was fine.',
        'At the end it tells you briefly what the issue was, what was done and whether a restart is needed.',
        '<b>Offline AI</b> (Gemma, on the USB) works without internet on PCs with 6 GB+ RAM. <b>Online AI</b> is optional with your own key (Google Gemini keys are free). Without AI it still understands 38 common problems by keywords.',
        'The AI never runs commands - it only picks from PC Doctor\'s own tested checks and repairs.'],
    s6='Adding your own apps and other OSes', s6_items=[
        '<b>Other OS / boot tools:</b> copy the <code>.iso</code> (or <code>.wim</code>, <code>.img</code>, <code>.vhd</code>) to the USB\'s <code>ISO</code> folder - it appears in the boot menu by itself (e.g. Windows 10, Ubuntu). ISOs over 4 GB work too. Delete the file to remove it.',
        '<b>Your Windows apps:</b> put a portable app\'s folder, a single <code>.exe</code>, an installer (<code>.exe</code> / <code>.msi</code>) or a <code>.zip</code> / <code>.7z</code> / <code>.rar</code> in the USB\'s <code>MyTools</code> folder. Zips are extracted by UPDATE.cmd, or press "Extract" in PC Doctor. They appear in PC Doctor → Tools Guide → <b>My tools</b>. A <code>.txt</code> with the app\'s name (e.g. <code>AnyDesk.txt</code>) - its first line is shown as the description.',
        'The first time, the virus check asks <i>"Did you put these here yourself?"</i> - answer <b>Yes</b> so they are recorded. If you see a program you did not add, answer <b>No</b>: it is quarantined.',
        'Keep apps in <code>MyTools</code> only - a new program inside <code>Tools</code> is treated as a virus.',
        'Use only programs from official websites, virus-scanned.',
        'USB full? Run <code>CLEAN.cmd</code> - it lists duplicate driver packs, old versions and partial downloads first and moves them to <code>_to_delete</code> only after you agree. It never touches <code>Reports</code> or <code>Rescue</code> (customer data).'],
    s7='Common problems: what to do', s7_head=('Problem', 'What to do'), s7_rows=[
        ('Anything', 'PC Doctor → <b>Assistant</b>: describe it - it checks and fixes automatically.'),
        ('PC very slow', 'Health Check → One-Click Optimize. Windows on an HDD → fit an SSD (clone with Rescuezilla). Get 8 GB RAM.'),
        ('C: drive full', 'Disk Space → move files to another drive; cleanup on the Speed Up page.'),
        ('Windows will not start / restart loop', "Boot menu → Hiren's BootCD PE → open the USB → <b>PCDoctor-Rescue.cmd</b>: save files first if the disk is failing, then stuck updates, blue-screen driver, SFC, boot files. No Wi-Fi? Option 1 loads the drivers from that PC's own Windows."),
        ('Blue screen', 'Tools Guide → BlueScreenView → "Check automatically" (which driver and the fix). MemTest86+ from the boot menu.'),
        ('Virus / ads / changed homepage', 'Tools Guide → Microsoft Safety Scanner, AdwCleaner, KVRT; registry check. Badly infected: Kaspersky Rescue Disk from the boot menu.'),
        ('Deleted files / formatted pendrive', 'Do not write anything new to that drive. Recuva (in Windows) or SystemRescue → PhotoRec.'),
        ('Reinstalling Windows', 'First Repair → <b>Drivers backup</b> and Tools Guide → ProduKey (saves the product key). After the reinstall → <b>Drivers restore</b>.'),
        ('No internet', 'Assistant: "internet not working" - or Repair → Network reset → restart.')],
    s8='Safety rules', s8_items=[
        '<b>Always back up</b> before changing partitions or cloning a disk. Keep the laptop on the charger.',
        'Password resets and data recovery <b>only with the owner\'s permission</b>.',
        'ShredOS and disk-wipe tools erase a disk for good. Check the disk number twice.',
        'Never use cracked software or activators - they often carry malware.'],
    note='<b>Note:</b> every tool is downloaded from its maker\'s official website and is free. Check each licence before commercial use (e.g. on customers\' PCs in a shop).',
    footer='Sanjeevani Rescue USB · open source · github.com/Salvitalathi/sanjeevani-usb')

L['mr'] = dict(
    lang='mr', title='संजीवनी Rescue USB - मार्गदर्शक', brand='संजीवनी Rescue USB',
    tagline='PC तपासणी, दुरुस्ती आणि वेग वाढवण्याचा pendrive · फक्त free आणि legal tools · English / मराठी / हिन्दी',
    nav=['Pendrive तयार करणे', 'Boot', 'Boot menu', 'PC Doctor', 'Assistant', 'स्वतःचे apps', 'समस्या', 'सुरक्षितता'],
    s1='Pendrive तयार करणे', s1_steps=[
        '64 GB USB 3.x pendrive घ्या (offline driver packs हवे असतील तर 256 GB). <b>त्यातील सगळा data पुसला जाईल.</b>',
        'Kit ची zip file extract करा (right-click → Extract All).',
        '<code>SETUP.cmd</code> वर double-click करा आणि Administrator परवानगी द्या.',
        'भाषा निवडा (English / मराठी / हिन्दी) - PC Doctor आणि हे मार्गदर्शक त्याच भाषेत येतात.',
        'Pendrive चा <b>Disk number</b> टाका, नंतर <code>ERASE</code> टाइप करा.',
        'Optional downloads विचारले जातील: Windows 11 ISO (7.5 GB), Linux Mint (3 GB), Assistant साठी offline AI (3.2 GB), offline driver packs (70 GB).',
        'Internet speed नुसार 30 मिनिटे ते 2 तास लागतात. काही tools हाताने download करायचे असतील तर त्यांची यादी शेवटी आपोआप उघडते.'],
    s1_update='<b>Update:</b> नंतर कधीही pendrive वरील <code>Sanjeevani\\Setup\\UPDATE.cmd</code> चालवा. फक्त नवीन versions download होतात आणि काहीही पुसले जात नाही.',
    s1_lock='<b>Write-protect switch:</b> pendrive ला lock switch असेल तर customer च्या PC वर तो <b>lock</b> ठेवा - virus त्यावर काहीही लिहू शकत नाही. फक्त तुमच्या स्वच्छ PC वर update करताना unlock करा. Switch नसला तरी PC Doctor प्रत्येक वेळी सुरू होताना virus ने pendrive वर केलेले बदल तपासतो.',
    s2='Pendrive वरून boot करणे', s2_steps=[
        'PC बंद करा आणि pendrive लावा.',
        'Power दाबताच Boot Menu key दाबत राहा (HP <kbd>F9</kbd>, Dell <kbd>F12</kbd>, Lenovo <kbd>F12</kbd>, Asus <kbd>Esc</kbd>...). पूर्ण यादी <a href="boot-keys.html">boot-keys.html</a> मध्ये आहे.',
        'संजीवनी menu दिसेल. ↑ ↓ ने tool निवडा आणि Enter दाबा. प्रत्येक tool ची माहिती खाली दिसते.',
        'Secure Boot error आला तर boot-keys.html मधील "Enroll key" पायऱ्या करा. हे एकदाच करावे लागते.'],
    s3='Boot menu मधील tools', s3_head=('Tool', 'कधी वापरायचे'), s3_rows=[
        ("Hiren's BootCD PE", 'Windows सुरू होत नाही, data काढायचा आहे, मालकाच्या PC चा password reset करायचा आहे. आतून USB वरील <code>PCDoctor-Rescue.cmd</code> चालवा.'),
        ('SystemRescue', 'Linux toolkit: delete झालेले files परत मिळवणे (PhotoRec), partition परत आणणे (TestDisk), disk तपासणी.'),
        ('MemTest86+ / MemTest86', 'Blue screen, अचानक restart किंवा hang होत असेल तर RAM तपासा. एकही लाल error आला तर RAM खराब आहे.'),
        ('GParted', 'Partition बनवणे, लहान/मोठे करणे.'),
        ('Clonezilla / Rescuezilla', 'HDD वरून नवीन SSD वर पूर्ण Windows clone करणे, किंवा पूर्ण disk चा backup.'),
        ('Super Grub2 / Boot-Repair', 'Bootloader खराब झाल्यामुळे "No bootable device" येत असेल तर.'),
        ('Kaspersky Rescue Disk', 'Windows इतका infected आहे की आतून antivirus चालत नाही तेव्हा.'),
        ('ShredOS', '<b style="color:#e11d48">धोकादायक:</b> disk कायमची पुसते. फक्त PC विकण्याआधी वापरा.'),
        ('Windows 11', 'नवीन install, किंवा Windows मध्ये ISO उघडून <code>setup.exe</code> → "Keep files and apps" (data राहून repair).'),
        ('Linux Mint XFCE', 'जुन्या / कमी RAM च्या PC साठी हलके, free OS. Install न करता चालवून पाहता येते.')],
    s4='PC Doctor (Windows चालू असताना)', s4_intro='Pendrive उघडा आणि <code>START-Sanjeevani.cmd</code> वर double-click करा (Administrator परवानगी द्या).',
    s4_items=[
        '<b>PC तपासणी:</b> Quick Scan (2 मिनिटे) किंवा Deep Scan (system files सह). Health score, तो 100 का नाही, आणि प्रत्येक समस्येपुढे दुरुस्तीचे button.',
        '<b>One-Click Optimize:</b> restore point → junk cleanup → अनावश्यक startup बंद → हलके effects → power plan → ads / bloatware काढणे → report.',
        '<b>दुरुस्ती:</b> DISM + SFC (खराब system files), disk check, Windows Update reset, network reset, Defender, drivers, registry तपासणी (virus ने बदललेल्या settings).',
        '<b>वेग वाढवा:</b> startup programs, tweaks, bloatware. <b>सर्व बदल Undo करता येतात.</b>',
        '<b>C: drive जागा:</b> Desktop, Documents, Downloads, Photos आणि C:\\ मधले स्वतःचे folders दुसऱ्या drive वर हलवा; दुसरा drive नसेल तर C: लहान करून DATA drive बनवा.',
        '<b>OS व Apps सल्ला:</b> Windows 11 चालेल का, या PC ला कोणते OS योग्य, कोणते apps काढावेत आणि हलके पर्याय, RAM / SSD upgrade.',
        '<b>Tools मार्गदर्शक:</b> 60+ tools - प्रत्येक काय करतो, कधी आणि कसा वापरायचा, इशाऱ्यांसह. "आपोआप तपासा" tool स्वतः चालवून निकाल समजावतो (disk, battery, तापमान, RAM, crash, virus, internet, C: drive). Pendrive वरचे Tools / Installers folders लपवलेले आहेत - tools इथूनच वापरा.',
        '<b>Report:</b> customer साठी HTML report, pendrive च्या <code>Reports\\</code> folder मध्ये save होतो.',
        '<b>भाषा:</b> title bar मधून English / मराठी / हिन्दी कधीही बदला.'],
    s5='Assistant - समस्या सांगा, तो दुरुस्त करतो', s5_items=[
        'समस्या स्वतःच्या शब्दांत लिहा - मराठी, हिंदी, English किंवा Roman ("net chalat nahi", "laptop खूप गरम होतो", "printer print देत नाही").',
        'एकदाच परवानगी द्या. Restore point बनतो आणि मग सगळे आपोआप: Assistant समस्या समजून घेतो, <b>ती या PC वर खरंच आहे का ते तपासतो</b>, दुरुस्त करतो, पुन्हा तपासतो, आणि पहिले कारण ठीक असल्यास पुढच्या संभाव्य कारणाकडे जातो.',
        'शेवटी थोडक्यात सांगतो: काय समस्या होती, काय केले, आणि restart लागेल का.',
        '<b>Offline AI</b> (Gemma, pendrive वर) 6 GB+ RAM च्या PC वर internet शिवाय चालतो. <b>Online AI</b> optional - तुमच्या स्वतःच्या key ने (Google Gemini ची key मोफत). AI नसला तरी keywords ने 38 सामान्य समस्या ओळखतो.',
        'AI कधीही स्वतः commands चालवत नाही - तो फक्त PC Doctor च्या तपासलेल्या तपासण्या आणि दुरुस्त्यांमधून निवडतो.'],
    s6='स्वतःचे apps आणि दुसरे OS जोडणे', s6_items=[
        '<b>दुसरे OS / boot tools:</b> <code>.iso</code> (किंवा <code>.wim</code>, <code>.img</code>, <code>.vhd</code>) pendrive च्या <code>ISO</code> folder मध्ये copy करा - boot menu मध्ये आपोआप दिसते (उदा. Windows 10, Ubuntu). 4 GB पेक्षा मोठी ISO पण चालते. काढायची असेल तर फाईल delete करा.',
        '<b>स्वतःचे Windows apps:</b> portable app चा folder, एकटी <code>.exe</code>, installer (<code>.exe</code> / <code>.msi</code>) किंवा <code>.zip</code> / <code>.7z</code> / <code>.rar</code> pendrive च्या <code>MyTools</code> folder मध्ये ठेवा. Zip UPDATE.cmd आपोआप extract करतो, किंवा PC Doctor मध्ये "Extract करा" दाबा. ते PC Doctor → Tools मार्गदर्शक → <b>माझे tools</b> मध्ये दिसतात. App च्या नावाची <code>.txt</code> ठेवल्यास (उदा. <code>AnyDesk.txt</code>) पहिली ओळ वर्णन म्हणून दिसते.',
        'पहिल्यांदा virus तपासणी विचारेल <i>"हे तुम्ही स्वतः टाकले का?"</i> - <b>हो</b> म्हणा म्हणजे ते नोंदवले जातील. तुम्ही न टाकलेला program दिसला तर <b>नाही</b> म्हणा: तो quarantine होईल.',
        'Apps <code>MyTools</code> मध्येच ठेवा - <code>Tools</code> मध्ये टाकलेला नवीन program virus समजला जातो.',
        'फक्त official website वरून घेतलेले, virus scan केलेले programs ठेवा.',
        'Pendrive भरला? <code>CLEAN.cmd</code> चालवा - duplicate driver packs, जुनी versions, अर्धवट downloads आधी यादीत दाखवतो आणि तुम्ही हो म्हटल्यावरच <code>_to_delete</code> मध्ये हलवतो. <code>Reports</code> आणि <code>Rescue</code> (customer data) ला कधीच हात लावत नाही.'],
    s7='सामान्य समस्या: काय करायचे', s7_head=('समस्या', 'उपाय'), s7_rows=[
        ('कोणतीही समस्या', 'PC Doctor → <b>Assistant</b>: समस्या लिहा - तो आपोआप तपासून दुरुस्त करतो.'),
        ('PC खूप slow', 'PC तपासणी → One-Click Optimize. Windows HDD वर असेल तर SSD लावा (Rescuezilla ने clone). RAM 8 GB करा.'),
        ('C: drive भरला', 'C: drive जागा → files दुसऱ्या drive वर हलवा; "वेग वाढवा" page वर cleanup.'),
        ('Windows सुरू होत नाही / restart loop', "Boot menu → Hiren's BootCD PE → USB उघडा → <b>PCDoctor-Rescue.cmd</b>: disk खराब असल्यास आधी files वाचवा, मग अडकलेले updates, blue screen चा driver, SFC, boot files. Wi-Fi नसेल तर पर्याय 1 त्याच PC च्या Windows मधले drivers load करतो."),
        ('Blue screen', 'Tools मार्गदर्शक → BlueScreenView → "आपोआप तपासा" (कोणता driver आणि उपाय). Boot menu मधून MemTest86+.'),
        ('Virus / ads / homepage बदलला', 'Tools मार्गदर्शक → Microsoft Safety Scanner, AdwCleaner, KVRT; registry तपासणी. फार infected: boot menu मधील Kaspersky Rescue Disk.'),
        ('File delete / pendrive format', 'त्या drive वर काहीही नवीन लिहू नका. Recuva (Windows मध्ये) किंवा SystemRescue → PhotoRec.'),
        ('Windows reinstall', 'आधी दुरुस्ती → <b>Drivers backup</b> आणि Tools मार्गदर्शक → ProduKey (product key save). Reinstall नंतर → <b>Drivers restore</b>.'),
        ('Internet चालत नाही', 'Assistant: "internet chalat nahi" - किंवा दुरुस्ती → Network reset → restart.')],
    s8='सुरक्षितता नियम', s8_items=[
        'Partition बदलण्याआधी आणि disk clone करण्याआधी <b>नेहमी backup घ्या</b>. Laptop charging ला लावून ठेवा.',
        'Password reset आणि data recovery <b>फक्त मालकाच्या परवानगीने</b> करा.',
        'ShredOS आणि disk wipe tools disk कायमची पुसतात. Disk number दोनदा तपासा.',
        'Cracked software किंवा activators कधीही वापरू नका - त्यांच्यासोबत बऱ्याचदा virus येतो.'],
    note='<b>टीप:</b> सर्व tools त्यांच्या निर्मात्यांच्या official websites वरून download होतात आणि free आहेत. Commercial वापराआधी (उदा. दुकानात customer PC साठी) प्रत्येकाचे license तपासा.',
    footer='संजीवनी Rescue USB · open source · github.com/Salvitalathi/sanjeevani-usb')

L['hi'] = dict(
    lang='hi', title='संजीवनी Rescue USB - गाइड', brand='संजीवनी Rescue USB',
    tagline='PC जाँच, मरम्मत और स्पीड बढ़ाने वाला pendrive · सिर्फ़ free और legal tools · English / मराठी / हिन्दी',
    nav=['Pendrive बनाना', 'Boot', 'Boot menu', 'PC Doctor', 'Assistant', 'अपने apps', 'समस्याएँ', 'सुरक्षा'],
    s1='Pendrive बनाना', s1_steps=[
        '64 GB USB 3.x pendrive लें (offline driver packs चाहिए तो 256 GB)। <b>उसका सारा data मिट जाएगा।</b>',
        'Kit की zip file extract करें (right-click → Extract All)।',
        '<code>SETUP.cmd</code> पर double-click करें और Administrator अनुमति दें।',
        'भाषा चुनें (English / मराठी / हिन्दी) - PC Doctor और यह गाइड उसी भाषा में आते हैं।',
        'Pendrive का <b>Disk number</b> लिखें, फिर <code>ERASE</code> टाइप करें।',
        'Optional downloads पूछे जाएँगे: Windows 11 ISO (7.5 GB), Linux Mint (3 GB), Assistant के लिए offline AI (3.2 GB), offline driver packs (70 GB)।',
        'Internet speed के अनुसार 30 मिनट से 2 घंटे लगते हैं। कुछ tools हाथ से download करने हों तो उनकी सूची आख़िर में अपने आप खुलती है।'],
    s1_update='<b>Update:</b> बाद में कभी भी pendrive पर <code>Sanjeevani\\Setup\\UPDATE.cmd</code> चलाएँ। सिर्फ़ नए versions download होते हैं, कुछ नहीं मिटता।',
    s1_lock='<b>Write-protect switch:</b> pendrive में lock switch हो तो customer के PC पर उसे <b>lock</b> रखें - virus उस पर कुछ नहीं लिख सकता। सिर्फ़ अपने साफ़ PC पर update करते समय unlock करें। Switch न हो तो भी PC Doctor हर बार शुरू होते समय virus द्वारा pendrive पर किए बदलाव जाँचता है।',
    s2='Pendrive से boot करना', s2_steps=[
        'PC बंद करें और pendrive लगाएँ।',
        'Power दबाते ही Boot Menu key दबाते रहें (HP <kbd>F9</kbd>, Dell <kbd>F12</kbd>, Lenovo <kbd>F12</kbd>, Asus <kbd>Esc</kbd>...)। पूरी सूची <a href="boot-keys.html">boot-keys.html</a> में है।',
        'संजीवनी menu दिखेगा। ↑ ↓ से tool चुनें और Enter दबाएँ। हर tool की जानकारी नीचे दिखती है।',
        'Secure Boot error आए तो boot-keys.html के "Enroll key" कदम करें। यह एक ही बार करना होता है।'],
    s3='Boot menu के tools', s3_head=('Tool', 'कब इस्तेमाल करें'), s3_rows=[
        ("Hiren's BootCD PE", 'Windows शुरू नहीं होता, data निकालना है, मालिक के PC का password reset करना है। अंदर से USB पर <code>PCDoctor-Rescue.cmd</code> चलाएँ।'),
        ('SystemRescue', 'Linux toolkit: delete हुई files वापस लाना (PhotoRec), partition वापस लाना (TestDisk), disk जाँच।'),
        ('MemTest86+ / MemTest86', 'Blue screen, अचानक restart या hang हो तो RAM जाँचें। एक भी लाल error = RAM खराब।'),
        ('GParted', 'Partition बनाना, छोटा/बड़ा करना।'),
        ('Clonezilla / Rescuezilla', 'HDD से नए SSD पर पूरा Windows clone करना, या पूरी disk का backup।'),
        ('Super Grub2 / Boot-Repair', 'Bootloader खराब होने से "No bootable device" आए तो।'),
        ('Kaspersky Rescue Disk', 'Windows इतना infected है कि अंदर antivirus नहीं चलता।'),
        ('ShredOS', '<b style="color:#e11d48">खतरनाक:</b> disk हमेशा के लिए मिटाता है। सिर्फ़ PC बेचने से पहले।'),
        ('Windows 11', 'नया install, या Windows में ISO खोलकर <code>setup.exe</code> → "Keep files and apps" (data रखकर repair)।'),
        ('Linux Mint XFCE', 'पुराने / कम RAM वाले PC के लिए हल्का, free OS। बिना install किए चलाकर देख सकते हैं।')],
    s4='PC Doctor (Windows चालू होने पर)', s4_intro='Pendrive खोलें और <code>START-Sanjeevani.cmd</code> पर double-click करें (Administrator अनुमति दें)।',
    s4_items=[
        '<b>PC जाँच:</b> Quick Scan (2 मिनट) या Deep Scan (system files सहित)। Health score, वह 100 क्यों नहीं, और हर समस्या के सामने मरम्मत का button.',
        '<b>One-Click Optimize:</b> restore point → junk cleanup → बेकार startup बंद → हल्के effects → power plan → ads / bloatware हटाना → report.',
        '<b>मरम्मत:</b> DISM + SFC (खराब system files), disk check, Windows Update reset, network reset, Defender, drivers, registry जाँच (virus द्वारा बदली settings)।',
        '<b>स्पीड बढ़ाएँ:</b> startup programs, tweaks, bloatware. <b>सभी बदलाव Undo हो सकते हैं।</b>',
        '<b>C: drive जगह:</b> Desktop, Documents, Downloads, Photos और C:\\ के अपने folders दूसरे drive पर ले जाएँ; दूसरा drive न हो तो C: छोटा करके DATA drive बनाएँ।',
        '<b>OS और Apps सलाह:</b> Windows 11 चलेगा या नहीं, इस PC के लिए कौन सा OS सही, कौन से apps हटाएँ और हल्के विकल्प, RAM / SSD upgrade.',
        '<b>Tools गाइड:</b> 60+ tools - हर एक क्या करता है, कब और कैसे इस्तेमाल करें, चेतावनियों के साथ। "अपने आप जाँचें" tool खुद चलाकर नतीजा समझाता है (disk, battery, तापमान, RAM, crash, virus, internet, C: drive)। Pendrive के Tools / Installers folders छिपे हैं - tools यहीं से इस्तेमाल करें।',
        '<b>Report:</b> customer के लिए HTML report, pendrive के <code>Reports\\</code> folder में save होती है।',
        '<b>भाषा:</b> title bar से English / मराठी / हिन्दी कभी भी बदलें।'],
    s5='Assistant - समस्या बताइए, वह ठीक करता है', s5_items=[
        'समस्या अपने शब्दों में लिखें - हिंदी, मराठी, English या Roman ("net nahi chal raha", "laptop बहुत गर्म होता है", "printer print नहीं कर रहा")।',
        'एक बार अनुमति दें। Restore point बनता है और फिर सब अपने आप: Assistant समस्या समझता है, <b>जाँचता है कि वह इस PC पर सच में है या नहीं</b>, ठीक करता है, फिर से जाँचता है, और पहला कारण ठीक हो तो अगले संभावित कारण पर जाता है।',
        'आख़िर में थोड़े में बताता है: क्या समस्या थी, क्या किया, और restart चाहिए या नहीं।',
        '<b>Offline AI</b> (Gemma, pendrive पर) 6 GB+ RAM वाले PC पर बिना internet चलता है। <b>Online AI</b> optional - अपनी key से (Google Gemini की key मुफ़्त)। AI न हो तो भी keywords से 38 आम समस्याएँ पहचानता है।',
        'AI कभी खुद commands नहीं चलाता - वह सिर्फ़ PC Doctor की जाँची हुई जाँचों और मरम्मतों में से चुनता है।'],
    s6='अपने apps और दूसरे OS जोड़ना', s6_items=[
        '<b>दूसरे OS / boot tools:</b> <code>.iso</code> (या <code>.wim</code>, <code>.img</code>, <code>.vhd</code>) pendrive के <code>ISO</code> folder में copy करें - boot menu में अपने आप दिखता है (जैसे Windows 10, Ubuntu)। 4 GB से बड़ी ISO भी चलती है। हटाना हो तो file delete करें।',
        '<b>अपने Windows apps:</b> portable app का folder, अकेली <code>.exe</code>, installer (<code>.exe</code> / <code>.msi</code>) या <code>.zip</code> / <code>.7z</code> / <code>.rar</code> pendrive के <code>MyTools</code> folder में रखें। Zip को UPDATE.cmd अपने आप extract करता है, या PC Doctor में "Extract करें" दबाएँ। वे PC Doctor → Tools गाइड → <b>मेरे tools</b> में दिखते हैं। App के नाम की <code>.txt</code> रखें (जैसे <code>AnyDesk.txt</code>) तो पहली line विवरण के रूप में दिखती है।',
        'पहली बार virus जाँच पूछेगी <i>"क्या ये आपने खुद रखे हैं?"</i> - <b>हाँ</b> कहें ताकि वे दर्ज हों। आपने न रखा program दिखे तो <b>नहीं</b> कहें: वह quarantine होगा।',
        'Apps सिर्फ़ <code>MyTools</code> में रखें - <code>Tools</code> में रखा नया program virus माना जाता है।',
        'सिर्फ़ official website से लिए, virus scan किए programs रखें।',
        'Pendrive भर गया? <code>CLEAN.cmd</code> चलाएँ - duplicate driver packs, पुराने versions और अधूरे downloads पहले सूची में दिखाता है और आपकी हाँ के बाद ही <code>_to_delete</code> में ले जाता है। <code>Reports</code> और <code>Rescue</code> (customer data) को कभी नहीं छूता।'],
    s7='आम समस्याएँ: क्या करें', s7_head=('समस्या', 'उपाय'), s7_rows=[
        ('कोई भी समस्या', 'PC Doctor → <b>Assistant</b>: समस्या लिखें - वह अपने आप जाँचकर ठीक करता है।'),
        ('PC बहुत slow', 'PC जाँच → One-Click Optimize. Windows HDD पर हो तो SSD लगाएँ (Rescuezilla से clone)। RAM 8 GB करें।'),
        ('C: drive भर गया', 'C: drive जगह → files दूसरे drive पर ले जाएँ; "स्पीड बढ़ाएँ" page पर cleanup.'),
        ('Windows शुरू नहीं होता / restart loop', "Boot menu → Hiren's BootCD PE → USB खोलें → <b>PCDoctor-Rescue.cmd</b>: disk खराब हो तो पहले files बचाएँ, फिर अटके updates, blue screen का driver, SFC, boot files. Wi-Fi नहीं? विकल्प 1 उसी PC के Windows से drivers load करता है।"),
        ('Blue screen', 'Tools गाइड → BlueScreenView → "अपने आप जाँचें" (कौन सा driver और उपाय)। Boot menu से MemTest86+.'),
        ('Virus / ads / homepage बदला', 'Tools गाइड → Microsoft Safety Scanner, AdwCleaner, KVRT; registry जाँच। बहुत infected: boot menu का Kaspersky Rescue Disk.'),
        ('File delete / pendrive format', 'उस drive पर कुछ भी नया न लिखें। Recuva (Windows में) या SystemRescue → PhotoRec.'),
        ('Windows reinstall', 'पहले मरम्मत → <b>Drivers backup</b> और Tools गाइड → ProduKey (product key save)। Reinstall के बाद → <b>Drivers restore</b>.'),
        ('Internet नहीं चल रहा', 'Assistant: "internet nahi chal raha" - या मरम्मत → Network reset → restart.')],
    s8='सुरक्षा नियम', s8_items=[
        'Partition बदलने और disk clone करने से पहले <b>हमेशा backup लें</b>। Laptop को charger पर रखें।',
        'Password reset और data recovery <b>सिर्फ़ मालिक की अनुमति से</b> करें।',
        'ShredOS और disk wipe tools disk हमेशा के लिए मिटाते हैं। Disk number दो बार जाँचें।',
        'Cracked software या activators कभी इस्तेमाल न करें - उनके साथ अक्सर virus आता है।'],
    note='<b>नोट:</b> सभी tools अपने निर्माताओं की official websites से download होते हैं और free हैं। Commercial इस्तेमाल से पहले (जैसे दुकान में customer PC के लिए) हर एक का license जाँचें।',
    footer='संजीवनी Rescue USB · open source · github.com/Salvitalathi/sanjeevani-usb')


def page(t):
    ids = ['make', 'boot', 'menu', 'pcdoctor', 'assistant', 'apps', 'problems', 'safety']
    nav = ''.join(f'<a href="#{i}">{n}</a>' for i, n in zip(ids, t['nav']))
    other = {'en': ('guide-mr.html', 'मराठी', 'guide-hi.html', 'हिन्दी'), 'mr': ('guide-en.html', 'English', 'guide-hi.html', 'हिन्दी'), 'hi': ('guide-en.html', 'English', 'guide-mr.html', 'मराठी')}[t['lang']]
    li = lambda xs: ''.join(f'<li>{x}</li>' for x in xs)
    rows = lambda rs: ''.join(f'<tr><td>{a}</td><td>{b}</td></tr>' for a, b in rs)
    h2 = lambda n, i, s: f'<h2 id="{i}"><span class="n">{n}</span>{s}</h2>'
    return f"""<!DOCTYPE html>
<html lang="{t['lang']}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{t['title']}</title><style>{CSS}</style></head><body>
<header><div class="w">
<div class="brand">{LOGO}<div><small>RESCUE USB · PC DOCTOR</small><h1>{t['brand']}</h1></div></div>
<p>{t['tagline']}</p>
<nav>{nav}<a href="{other[0]}">{other[1]}</a><a href="{other[2]}">{other[3]}</a></nav>
</div></header>
<div class="w">
{h2(1, 'make', t['s1'])}
<div class="card"><ol>{li(t['s1_steps'])}</ol><p>{t['s1_update']}</p></div>
<div class="card tip">{t['s1_lock']}</div>
{h2(2, 'boot', t['s2'])}
<div class="card"><ol>{li(t['s2_steps'])}</ol></div>
{h2(3, 'menu', t['s3'])}
<table><tr><th>{t['s3_head'][0]}</th><th>{t['s3_head'][1]}</th></tr>{rows(t['s3_rows'])}</table>
{h2(4, 'pcdoctor', t['s4'])}
<div class="card"><p>{t['s4_intro']}</p><ul>{li(t['s4_items'])}</ul></div>
{h2(5, 'assistant', t['s5'])}
<div class="card tip"><ul>{li(t['s5_items'])}</ul></div>
{h2(6, 'apps', t['s6'])}
<div class="card"><ul>{li(t['s6_items'])}</ul></div>
{h2(7, 'problems', t['s7'])}
<table><tr><th>{t['s7_head'][0]}</th><th>{t['s7_head'][1]}</th></tr>{rows(t['s7_rows'])}</table>
{h2(8, 'safety', t['s8'])}
<div class="card danger"><ul>{li(t['s8_items'])}</ul></div>
<div class="card warn">{t['note']}</div>
<footer>{t['footer']}</footer>
</div></body></html>
"""


for code, t in L.items():
    path = os.path.join(DOCS, f'guide-{code}.html')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(page(t))
    print('wrote', path)
