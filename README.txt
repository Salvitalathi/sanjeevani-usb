SANJEEVANI RESCUE USB
=====================
A free, legal toolkit on one pendrive: boot menu of rescue tools + PC Doctor
(health check, automatic repair, speed-up, Assistant). English / मराठी / हिन्दी.
Marathi: README-Marathi.txt    Hindi: README-Hindi.txt

MAKE THE USB
1. Extract this zip (right-click > Extract All).
2. Insert a 64 GB pendrive (256 GB if you also want the offline driver packs).
   ALL DATA ON IT WILL BE ERASED.
3. Double-click SETUP.cmd and allow Administrator.
4. Choose the language (English / Marathi / Hindi).
5. Type the pendrive's Disk number, then type ERASE.
6. Wait for the downloads (30 min - 2 hours depending on the internet).

USE IT
- Inside Windows: open the USB and double-click START-Sanjeevani.cmd (PC Doctor).
  Describe a problem in the Assistant - it checks the PC and fixes it automatically.
- Windows will not start: press the Boot Menu key (F12 / F9 / Esc ...) and choose the USB,
  then Hiren's BootCD PE > PCDoctor-Rescue.cmd.
- Full guide: "READ-ME - Guide.html" on the USB (kit\Sanjeevani\Docs\guide-en.html).

LATER
- Update:  <USB>\Sanjeevani\Setup\UPDATE.cmd
- USB full: CLEAN.cmd (lists first, deletes only after you agree)
- Your own apps: copy them to <USB>\MyTools   Other OS / ISO files: <USB>\ISO

Folder layout on the USB
  ventoy\        boot menu theme + ventoy.json
  ISO\           bootable rescue images (add your own .iso here)
  Tools\         portable Windows tools (hidden - use them from PC Doctor's Tools guide)
  Installers\    installers (7-Zip, Malwarebytes ...) (hidden)
  MyTools\       your own apps
  Sanjeevani\    PC Doctor, docs, tools catalog, setup
  Reports\       PC Doctor reports (one folder per PC)

Advanced:  Setup-Sanjeevani.ps1 -Usb E: -UpdateOnly
           Setup-Sanjeevani.ps1 -Only hbcd,cpuz
           Setup-Sanjeevani.ps1 -GPT -WithWindows -WithMint -WithAI -Lang en
