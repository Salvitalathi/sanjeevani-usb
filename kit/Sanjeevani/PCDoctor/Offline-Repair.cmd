@echo off
setlocal EnableDelayedExpansion
title Sanjeevani Offline Repair
color 0B
rem ------------------------------------------------------------------
rem  Sanjeevani Offline Repair - run inside Hiren's BootCD PE (or any
rem  Windows PE / recovery command prompt) when Windows will not start.
rem ------------------------------------------------------------------

rem fltmc works in WinPE (net session does not)
fltmc >nul 2>&1
if errorlevel 1 (
  echo Please right-click this file and choose "Run as administrator".
  pause & exit /b 1
)

:findwin
set WIN=
set FOUND=
set NFOUND=0
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist "%%d:\Windows\System32\config\SYSTEM" if /I not "%%d"=="%SystemDrive:~0,1%" (
    set "FOUND=!FOUND! %%d:"
    set /a NFOUND+=1
    set WIN=%%d
  )
)
cls
echo  ============================================================
echo    SANJEEVANI  -  Offline Windows Repair
echo  ============================================================
if "%NFOUND%"=="0" echo  Installed Windows was not found automatically.
if not "%NFOUND%"=="0" echo  Windows found on:%FOUND%
if "%NFOUND%"=="1" goto confirm1
set WIN=
set /p WIN=  Type the drive letter of the Windows to repair (e.g. C):
goto checkwin

:confirm1
set ANS=
set /p ANS=  Repair the Windows on %WIN%: ? [Y/N]:
if /I "%ANS%"=="Y" goto checkwin
set WIN=
set /p WIN=  Type the drive letter of the Windows to repair:

:checkwin
if "%WIN%"=="" goto findwin
set WIN=%WIN::=%
set WIN=%WIN:~0,1%
if not exist "%WIN%:\Windows\System32\config\SYSTEM" (
  echo  %WIN%: does not contain Windows.
  pause
  goto findwin
)
echo.
echo  Working on Windows at  %WIN%:
echo.

:menu
echo  1. Check and repair system files      (SFC offline)
echo  2. Repair Windows image from ISO       (DISM offline, needs Windows ISO)
echo  3. Check and fix disk errors           (CHKDSK /F)
echo  4. Rebuild boot files                  (BCDBOOT - "no bootable device" / boot loop)
echo  5. Undo stuck / failed updates         (DISM RevertPendingActions)
echo  6. Remove the last installed update    (list + remove package)
echo  7. Open Command Prompt
echo  0. Exit
echo.
set CH=
set /p CH=  Choose:
if "%CH%"=="1" goto sfc
if "%CH%"=="2" goto dism
if "%CH%"=="3" goto chk
if "%CH%"=="4" goto boot
if "%CH%"=="5" goto revert
if "%CH%"=="6" goto pkgs
if "%CH%"=="7" start cmd
if "%CH%"=="0" exit /b 0
goto menu

:sfc
echo.
echo  Running SFC on %WIN%: ... (10-30 minutes)
sfc /scannow /offbootdir=%WIN%:\ /offwindir=%WIN%:\Windows
echo.
pause
goto menu

:dism
echo.
echo  Mount or extract a Windows ISO of the SAME version first
echo  (In Hiren's PE: double-click the ISO in \ISO on the USB to mount it).
echo  Searching drives for sources\install.wim / install.esd ...
set SRC=
set KIND=
for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  if not defined SRC if exist "%%d:\sources\install.wim" (
    set "SRC=%%d:\sources\install.wim"
    set KIND=WIM
  )
  if not defined SRC if exist "%%d:\sources\install.esd" (
    set "SRC=%%d:\sources\install.esd"
    set KIND=ESD
  )
)
if not defined SRC (
  echo  No install.wim / install.esd found. Mount the ISO and try again.
  pause
  goto menu
)
echo  Found: %SRC%
dism /Get-WimInfo /WimFile:"%SRC%"
set IDX=
set /p IDX=  Type the Index of your edition (Home / Pro ...):
if "%IDX%"=="" goto menu
set "SCR=%WIN%:\$SanjeevaniScratch"
if exist "%SCR%" rd /s /q "%SCR%" 2>nul
mkdir "%SCR%"
dism /Image:%WIN%:\ /Cleanup-Image /RestoreHealth /Source:%KIND%:"%SRC%":%IDX% /LimitAccess /ScratchDir:"%SCR%"
rd /s /q "%SCR%" 2>nul
echo.
echo  Now run option 1 (SFC) again.
pause
goto menu

:chk
echo.
echo  Take a backup first if the disk is failing.
chkdsk %WIN%: /f
pause
goto menu

:boot
echo.
echo  Volumes on this PC:
echo list volume> "%TEMP%\sjv_dp.txt"
diskpart /s "%TEMP%\sjv_dp.txt"
echo.
echo  UEFI PC : pick the small FAT32 volume (100-500 MB, "System" / Hidden) on the SAME disk as Windows.
echo  Old BIOS: pick the "System Reserved" NTFS volume (or the Windows volume itself if none).
echo  DO NOT pick the Ventoy / USB volumes.
set VN=
set /p VN=  Volume number (empty = cancel):
if "%VN%"=="" goto menu
set SL=
for %%L in (S R Q P O N M L K) do if not defined SL if not exist %%L:\ set SL=%%L
if not defined SL (
  echo  No free drive letter - nothing changed.
  pause
  goto menu
)
(echo select volume %VN%& echo assign letter=%SL%)> "%TEMP%\sjv_dp.txt"
diskpart /s "%TEMP%\sjv_dp.txt"
if errorlevel 1 (
  echo  diskpart could not assign a letter - nothing changed.
  pause
  goto menu
)
if not exist %SL%:\ (
  echo  Could not assign letter %SL%: - nothing changed.
  pause
  goto menu
)
bcdboot %WIN%:\Windows /s %SL%: /f ALL
(echo select volume %VN%& echo remove letter=%SL%)> "%TEMP%\sjv_dp.txt"
diskpart /s "%TEMP%\sjv_dp.txt" >nul
del "%TEMP%\sjv_dp.txt" 2>nul
echo.
echo  Done. Remove the USB and restart.
pause
goto menu

:revert
echo.
dism /Image:%WIN%:\ /Cleanup-Image /RevertPendingActions
echo.
echo  Restart and let Windows finish. If it still loops, try option 6.
pause
goto menu

:pkgs
echo.
dism /Image:%WIN%:\ /Get-Packages /Format:Table | findstr /i "Install Pending"
echo.
echo  Copy the Package Identity of the most recent update (by install time).
set PKG=
set /p PKG=  Package Identity (empty = cancel):
if "%PKG%"=="" goto menu
dism /Image:%WIN%:\ /Remove-Package /PackageName:%PKG%
pause
goto menu
