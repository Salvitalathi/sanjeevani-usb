# Hindi (हिन्दी) text for the Tools guide - part 2.
H = {}
def h(id, what, when, steps, good='', warn=()):
    H[id] = {'what': what, 'when': when, 'steps': list(steps), 'good': good, 'warn': list(warn)}

PART_STEPS = ['आसान तरीका: PC Doctor → "C: drive जगह" → "नया DATA drive बनाएँ" (सुरक्षित)।', '"Install करें" → बदलाव तय करें → "Apply" दबाने तक कुछ नहीं बदलता।']
PART_WARN = ['Partitions बदलने से पहले ज़रूरी data का backup लें।', 'काम के दौरान बिजली नहीं जानी चाहिए - laptop charger / UPS.', 'System Reserved / EFI / Recovery partitions को न छुएँ।']
BACKUP_STEPS = ['"Install करें" → "System Backup" → backup external disk पर रखें।', 'Windows शुरू न हो तो USB से boot → Rescuezilla से restore हो सकता है।']
BACKUP_WARN = ['Restore चुनी गई disk पर सब कुछ बदल देता है - disk ध्यान से चुनें।']
BOOT_STEPS = ['आसान तरीका: USB से boot → Hiren\'s PE → PCDoctor-Rescue.cmd → "Fix boot".']
BOOT_WARN = ['गलत बदलाव से Windows शुरू नहीं होगा।', 'कुछ भी बदलने से पहले backup / export लें।']
OPEN = ['"खोलें" - बिना install के चलता है।']
INST = ['"Install करें" - इस PC पर install होता है।']

h('hddscan', 'Disk surface test और SMART.', 'Victoria का आसान विकल्प।',
  ['"खोलें" → disk चुनें → "Surface Tests" → Read चुनें → Add test.'],
  'Bad blocks नहीं = ठीक।', ['सिर्फ़ "Read" / "Verify" इस्तेमाल करें। "Erase" test data मिटा देता है!'])
h('dmde', 'Format हुए या खोए partitions से files वापस लाता है।',
  'Drive format माँगता है, partition गायब हो गया, गलती से format हो गया।',
  ['"खोलें" → disk चुनें → partition चुनें → "Open Volume". Files पर right-click → "Recover" → दूसरे drive पर save करें।', 'Free version एक बार में एक folder वापस लाता है।'],
  '', ['जिस disk से files वापस ला रहे हैं उस पर कुछ भी save या install न करें - files हमेशा के लिए खो जाएँगी।', 'वापस मिली files हमेशा दूसरी disk / USB पर save करें।', '"Partition write / Apply" विकल्प इस्तेमाल न करें।'])
h('testdisk', 'PhotoRec: delete हुई photos और documents वापस लाता है। TestDisk: खोए partitions वापस लाता है।',
  'गलती से delete, memory card / USB format हो गया।',
  ['"खोलें" (QPhotoRec) → disk चुनें → "File Formats" में प्रकार चुनें → "Destination" दूसरा drive रखें → Search.'],
  'Files मूल नामों के बिना वापस आती हैं (f12345.jpg) - folder खोलकर चुनें।',
  ['Destination हमेशा दूसरे drive पर चुनें।', 'TestDisk (text window) में "Write" तभी इस्तेमाल करें जब पता हो क्या कर रहे हैं - गलत partition table से data खोता है।'])
h('recuva', 'हाल में delete हुई files आसानी से वापस लाता है।', 'Recycle Bin से भी delete हो गई हैं।',
  ['"खोलें" → wizard में file का प्रकार और जगह चुनें → Start. हरी (Excellent) files Recover करें → दूसरे drive पर।'],
  'हरा = पूरी तरह वापस मिलेगी, लाल = खराब।', ['वापस मिली files दूसरे drive पर save करें।'])
h('aomei-pa', 'Partitions का size बदलना, drives बनाना, disk को SSD पर ले जाना (installer)।',
  'C: बहुत छोटा है, D: से जगह लेनी है, HDD → SSD.', PART_STEPS, '', PART_WARN)
h('minitool-pw', 'Partitions का size बदलना, drives बनाना, disk को SSD पर ले जाना (installer)।',
  'C: बहुत छोटा है, D: से जगह लेनी है, HDD → SSD.', PART_STEPS, '', PART_WARN)
h('aomei-backupper', 'Windows / पूरी disk का image backup और restore (installer)।',
  'Windows को नए SSD पर ले जाना, बड़ी मरम्मत से पहले पूरा backup.', BACKUP_STEPS, '', BACKUP_WARN)
h('hasleo-backup', 'Windows / पूरी disk का image backup और restore (installer)।',
  'Windows को नए SSD पर ले जाना, बड़ी मरम्मत से पहले पूरा backup.', BACKUP_STEPS, '', BACKUP_WARN)
h('produkey', 'Windows / Office की product key दिखाता है।', 'Windows reinstall से पहले key लिख लें।',
  ['"अपने आप जाँचें" - BIOS में रखी Windows key (नए laptops) और ProduKey की मिली keys यहाँ दिखती हैं और Reports में save होती हैं।'],
  'BIOS में key हो तो reinstall के बाद Windows अपने आप activate होता है।',
  ['Product keys निजी रखें - customer के अलावा किसी को न दें।'])
h('dismpp', 'Windows cleanup और updates/drivers/apps का प्रबंधन।', 'अनुभवी users के लिए - पुरानी Windows update files साफ़ करना।',
  ['आसान तरीका: "PC Doctor में देखें" - मरम्मत और स्पीड pages पर सुरक्षित cleanup.', 'Dism++: "Space Cleanup" → Scan → Clean.'],
  '', ['"Drivers", "Apps" या "Optimizations" में जो समझ न आए वह न बदलें।'])
h('ntpwedit', 'भूला हुआ local Windows password हटाता है।', 'Customer अपने ही PC का password भूल गया।',
  ['USB से boot → Hiren\'s BootCD PE → NTPWEdit खोलें।', 'User चुनें → "Change password" → खाली छोड़ें → OK → "Save changes".'],
  'अगली बार बिना password के login होगा।',
  ['सिर्फ़ मालिक की अनुमति से इस्तेमाल करें।', 'Microsoft account (email login) पर नहीं चलता - account.live.com/password/reset इस्तेमाल करें।', 'BitLocker चालू हो तो पहले recovery key चाहिए।'])
h('winntsetup', 'Windows सीधे दूसरी disk / partition पर install करता है।', 'अनुभवी users के लिए - PE से Windows install करना।',
  ['Hiren\'s PE में खोलें → Windows ISO से install.wim चुनें → boot और install drives चुनें → Setup.'],
  '', ['चुना गया partition format होता है - उसका data मिट जाता है।'])
for x in ('bootice', 'easyuefi', 'visualbcd'):
    h(x, 'Boot entries / boot records (MBR, UEFI, BCD) बदलता है।', 'अनुभवी users के लिए - boot की समस्याएँ।', BOOT_STEPS, '', BOOT_WARN)
h('winmtr', 'Internet connection कहाँ टूटता है ढूँढता है (router, ISP, website)।', 'Internet नहीं, बहुत धीमा, या बार-बार कटता है।',
  ['"अपने आप जाँचें" - router, internet और DNS जाँचकर बताता है समस्या कहाँ है।', 'WinMTR: host google.com → Start. पहली row जिसमें "Loss %" ज़्यादा हो वहीं टूटता है।'],
  'पहली row (router) पर loss = घर का WiFi/cable. बाद की rows = ISP.')
h('advipscanner', 'Network पर हर device ढूँढता है (printers, CCTV, PCs)।', 'Printer का IP चाहिए या देखना है network पर कौन है।', ['"खोलें" → "Scan".'])
h('rustdesk', 'Remote support - कोई और इस PC को चला सकता है (मुफ़्त)।', 'दूर से customer की मदद करना।',
  ['"खोलें" → दिखने वाला ID और password मदद करने वाले को दें।', 'काम खत्म होने पर RustDesk बंद करें।'],
  '', ['ID / password सिर्फ़ जान-पहचान वाले technician को दें - phone पर माँगने वाले अनजान लोगों को कभी नहीं (धोखा)।', 'काम होने पर program बंद करें।'])
h('7zip', 'Zip / rar / 7z files खोलता और बनाता है (installer)।', '', INST, '', ['इस PC पर install होता है।'])
h('notepadpp', 'Text और config files के लिए अच्छा editor.', '', OPEN)
h('everything', 'PC की कोई भी file नाम से एक सेकंड में ढूँढता है।', '', OPEN)
h('vlc', 'हर तरह का video / audio चलाता है।', '', OPEN)
h('explorerpp', 'File manager - Hiren\'s PE में files copy करने के लिए उपयोगी।', '', OPEN)
h('sumatra', 'बहुत हल्का PDF reader (Adobe से बहुत हल्का) - installer.', '', INST, '', ['इस PC पर install होता है।'])
