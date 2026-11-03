@echo off
rem Sanjeevani Rescue USB - find and remove duplicate / leftover files on the USB. Asks before changing anything.
title Sanjeevani Rescue USB - Cleaner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clean-Sanjeevani.ps1" %*
echo.
pause
