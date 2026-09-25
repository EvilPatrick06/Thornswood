@echo off
title Skyrim Together - Skyrim Unbound, then publish
cd /d "%~dp0"
if not exist "C:\SkyrimTogether\_dist" mkdir "C:\SkyrimTogether\_dist"
set LOG=C:\SkyrimTogether\_dist\unbound.log
echo ===== STARTED %DATE% %TIME% > "%LOG%"
echo.
echo Installing Skyrim Unbound, then building and publishing.
echo Everything is written to %LOG% as it goes.
echo.
REM Nothing here asks a question. Read-Host reads end-of-file from nul and
REM carries on, so this runs start to finish without anyone at the keyboard.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Add-SkyrimUnbound.ps1" -NoPause <nul >> "%LOG%" 2>&1
echo ===== EXIT %ERRORLEVEL% >> "%LOG%"
echo ===== FINISHED %DATE% %TIME% >> "%LOG%"
type "%LOG%"
echo.
echo Done. This window can be closed.
timeout /t 60 >nul
