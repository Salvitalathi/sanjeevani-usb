@echo off
rem Sanjeevani PC Doctor RESCUE - run inside Hiren's BootCD PE when Windows will not start.
title Sanjeevani PC Doctor - Rescue
set "PS1=%~dp0Sanjeevani\PCDoctor\Rescue\PCDoctor-Rescue.ps1"
set "PWSH="
for %%P in ("%ProgramFiles%\PowerShell\7\pwsh.exe" "X:\Program Files\PowerShell\7\pwsh.exe") do if not defined PWSH if exist %%P set "PWSH=%%~P"
if not defined PWSH for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if not defined PWSH for /f "delims=" %%P in ('dir /s /b "%SystemDrive%\pwsh.exe" 2^>nul') do if not defined PWSH set "PWSH=%%P"
if not defined PWSH for /f "delims=" %%P in ('where powershell.exe 2^>nul') do if not defined PWSH set "PWSH=%%P"
if not defined PWSH (
  echo PowerShell was not found in this boot environment - starting the basic repair menu.
  call "%~dp0Sanjeevani\PCDoctor\Offline-Repair.cmd"
  exit /b
)
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
if errorlevel 1 pause
