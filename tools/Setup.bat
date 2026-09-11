@echo off
title Skyrim Together - Setup
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-SkyrimTogether.ps1" -MovePayload
