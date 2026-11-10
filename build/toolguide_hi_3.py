# Hindi (हिन्दी) text for the Tools guide - part 3 + group names.
H = {}
def h(id, what, when, steps, good='', warn=()):
    H[id] = {'what': what, 'when': when, 'steps': list(steps), 'good': good, 'warn': list(warn)}

INST = ['"Install करें" - इस PC पर install होता है।']
INSTW = ['इस PC पर install होता है।']
BOOT = ['PC बंद करें, pendrive लगाएँ और चालू करते समय Boot Menu key दबाएँ (F12 / F9 / Esc / F11 - "Boot Menu / BIOS keys" देखें)।',
        'Sanjeevani के menu से यह विकल्प चुनें।']
AI = ['PC Doctor → Assistant में समस्या लिखें।']

h('libreoffice', 'मुफ़्त office suite (Word / Excel / PowerPoint files) - installer.', '', INST, '', INSTW)
h('qbittorrent', 'Torrent downloader (ads नहीं) - installer.', '', INST, '', INSTW)
h('firefox', 'Browser - Chrome भारी लगे तो विकल्प - installer.', '', INST, '', INSTW)
h('llamacpp', 'PC Doctor के Assistant के पीछे का offline AI engine - बिना internet समस्या समझता है।', 'इसे सीधे खोलने की ज़रूरत नहीं।', AI)
h('ai-model', 'Google Gemma 4 E2B (Apache-2.0) - Assistant के लिए हिंदी / मराठी / English समझने वाला AI model.', 'इसे सीधे खोलने की ज़रूरत नहीं।', AI)
h('rufus', 'Bootable Windows / Linux USB बनाता है।', 'किसी PC के लिए सिर्फ़ Windows install वाला USB चाहिए।',
  ['"खोलें" → Device में दूसरा (खाली) USB चुनें → SELECT → ISO → START.'], '',
  ['चुना गया USB पूरा मिट जाता है। Device सूची में यह Sanjeevani USB न चुनें!'])
h('hbcd', 'USB से Windows जैसा desktop - Windows शुरू न हो तब files copy करना, password reset और PC Doctor Rescue चलाना।',
  'Windows शुरू नहीं होता, blue screen loop, data निकालना है।', BOOT)
h('systemrescue', 'Linux पर आधारित repair toolkit (अनुभवी users के लिए)।', 'जब Hiren\'s PE काम न करे।', BOOT, '', ['सिर्फ़ तब, जब Linux commands आती हों।'])
h('memtest86plus', 'RAM का पूरा test (पुराने और नए PC)।', 'बार-बार blue screen, अचानक restart.', BOOT)
h('memtest86', 'RAM test - नए UEFI PC के लिए।', 'जब MemTest86+ शुरू न हो।', BOOT)
h('gparted', 'Partition editor (Linux).', 'जब Windows से partitions न बदल सकें।', BOOT, '', ['गलत partition बदलने से data और Windows खो जाते हैं। पहले backup लें।'])
h('clonezilla', 'पूरी disk की हूबहू copy / image.', 'HDD → SSD ले जाना, पूरा backup.', BOOT, '', ['Source और target उलटे हुए तो मूल disk मिट जाएगी - दो बार जाँचें।'])
h('rescuezilla', 'आसान windows के साथ disk backup / restore / clone.', 'Windows शुरू न हो तब पूरा backup, नए SSD पर ले जाना।', BOOT, '', ['Restore / clone चुनी गई target disk पर सब कुछ मिटा देता है।'])
h('supergrub2', 'Disk पर Windows / Linux ढूँढकर शुरू करता है।', 'Boot menu टूटने से Windows नहीं दिखता।', BOOT)
h('bootrepair', 'Linux / GRUB boot repair.', 'Linux + Windows dual boot टूट गया।', BOOT, '', ['सिर्फ़ Windows वाले PC पर न चलाएँ।'])
h('krd', 'Windows शुरू किए बिना virus scan (Kaspersky).', 'Virus Windows के अंदर scan रोकता है।', BOOT)
h('shredos', 'Disks हमेशा के लिए मिटाता है (data वापस नहीं आएगा)।', 'PC / disk बेचने से पहले।', BOOT, '', ['चुनी गई disk हमेशा के लिए मिट जाती है। पहले यह USB और दूसरी disks निकाल दें।'])
h('win11', 'Windows 11 install / repair.', 'नया Windows install, या "Repair your computer".', BOOT, '', ['Install के दौरान partition delete / format करने से उसका data मिट जाता है।'])
h('mint-xfce', 'पुराने / धीमे PC के लिए हल्का Linux.', 'पुराना PC जहाँ Windows बहुत भारी है।', BOOT, '', ['"Erase disk and install" Windows और data हटा देता है।'])
h('lazesoft', 'Windows boot repair और password reset.', 'Windows शुरू नहीं होता।', BOOT)
h('hdat2', 'Disk bad-sector test (DOS).', 'पुरानी IDE / SATA disks.', BOOT, '', ['सिर्फ़ Read / Verify tests इस्तेमाल करें।'])

GROUPS_HI = {
    'health': 'PC की सेहत जाँचें', 'stress': 'गर्म होना / अचानक बंद होना (stress test)', 'crash': 'Blue screen / crash का कारण',
    'virus': 'Virus / adware हटाएँ', 'speed': 'स्पीड और जगह', 'drivers': 'Drivers', 'disk': 'Disk test और data recovery',
    'backup': 'Partition और backup', 'windows': 'Windows tools (keys, password, boot)', 'network': 'Internet / network / remote मदद',
    'apps': 'उपयोगी apps', 'mytools': 'मेरे tools (MyTools folder)', 'bootmenu': 'Pendrive से boot करके इस्तेमाल करें',
}
