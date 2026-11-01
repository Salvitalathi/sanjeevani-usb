@echo off
rem Sanjeevani PC Doctor launcher - double-click inside Windows 10/11.
title Sanjeevani PC Doctor
set "PS1=%~dp0Sanjeevani\PCDoctor\PCDoctor.ps1"
if not exist "%PS1%" (
  echo PC Doctor files are missing: %PS1%
  pause
  exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%PS1%"
