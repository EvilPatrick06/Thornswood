@echo off
title Skyrim Together - Installer
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-SkyrimTogether.ps1"
if errorlevel 1 pause
