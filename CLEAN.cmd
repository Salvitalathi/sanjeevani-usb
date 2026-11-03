@echo off
rem Sanjeevani Rescue USB - find and remove duplicate / leftover files on the USB. Asks before changing anything.
title Sanjeevani Rescue USB - Cleaner
if not exist "%~dp0Clean-Sanjeevani.ps1" (
  echo.
  echo   Clean-Sanjeevani.ps1 was not found next to this file.
  echo   You probably opened it from inside the ZIP file.
  echo   Right-click the downloaded ZIP - Extract All - then run CLEAN.cmd from the extracted folder.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clean-Sanjeevani.ps1" %*
echo.
pause
