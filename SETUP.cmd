@echo off
rem Sanjeevani Rescue USB - setup / update. Double-click, allow admin.
title Sanjeevani Rescue USB - Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Sanjeevani.ps1" %*
