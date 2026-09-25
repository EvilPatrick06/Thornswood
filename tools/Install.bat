@echo off
title Thornswood - Installer
rem PowerShell 7 when it is installed, Windows PowerShell otherwise. The two
rem differ in ways that matter here, most of all whether a text file gets a
rem byte order mark, and the game stops dead on one.
set "PS=powershell"
where /q pwsh && set "PS=pwsh"
cd /d "%~dp0"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Thornswood.ps1"
if errorlevel 1 pause
