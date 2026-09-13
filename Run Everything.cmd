@echo off
title Thornswood - everything at once
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Run-Everything.ps1"
