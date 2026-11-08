@echo off
rem Sanjeevani Rescue USB - setup / update. Double-click, allow admin.
title Sanjeevani Rescue USB - Setup
if not exist "%~dp0Setup-Sanjeevani.ps1" (
  echo.
  echo   Setup-Sanjeevani.ps1 was not found next to this file.
  echo   You probably opened it from inside the ZIP file.
  echo   Right-click the downloaded ZIP - Extract All - then run SETUP.cmd from the extracted folder.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Sanjeevani.ps1" %*
if errorlevel 1 (
  echo.
  echo   Setup stopped with an error. Take a photo or screenshot of the message above and report it.
  pause
)
