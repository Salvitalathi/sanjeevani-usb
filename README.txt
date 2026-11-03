SANJEEVANI RESCUE USB KIT
=========================

1. Extract this zip (right-click > Extract All).
2. Insert a 64 GB pendrive, or 256 GB if you also want the offline driver packs (ALL DATA ON IT WILL BE ERASED).
3. Double-click SETUP.cmd and allow Administrator.
4. Type the pendrive's Disk number, then type ERASE.
5. Wait for downloads (30 min - 2 hours depending on internet).

Later updates: run  <USB>\Sanjeevani\Setup\UPDATE.cmd

Inside Windows: open the USB and double-click START-Sanjeevani.cmd (PC Doctor).
Boot: press the Boot Menu key (F12 / F9 / Esc ...) and choose the USB.

Full Marathi guide: kit\Sanjeevani\Docs\guide-mr.html
(also copied to the USB root as READ-ME-मार्गदर्शक.html)

Folder layout on the USB
  ventoy\            boot menu theme + ventoy.json
  ISO\               bootable rescue images
  Tools\             portable Windows tools
  Installers\        installers (7-Zip, Malwarebytes ...)
  Sanjeevani\        PC Doctor, docs, tools catalog, setup
  Reports\           PC Doctor reports (one folder per PC)

Advanced:  Setup-Sanjeevani.ps1 -Usb E: -UpdateOnly
           Setup-Sanjeevani.ps1 -Only hbcd,cpuz
           Setup-Sanjeevani.ps1 -GPT -WithWindows -WithMint
