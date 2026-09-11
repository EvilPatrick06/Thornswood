@echo off
title Skyrim Together - build and package
cd /d "%~dp0"
if not exist "C:\SkyrimTogether\_dist" mkdir "C:\SkyrimTogether\_dist"
set LOG=C:\SkyrimTogether\_dist\run.log
echo ===== STARTED %DATE% %TIME% > "%LOG%"
echo.
echo Step 1 of 2: building the launcher
echo ===== BUILD LAUNCHER >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Launcher.ps1" <nul >> "%LOG%" 2>&1
echo ===== BUILD EXIT %ERRORLEVEL% >> "%LOG%"
echo.
echo Step 2 of 2: packaging. This takes about twenty minutes.
echo ===== PACKAGE >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Package-SkyrimTogether.ps1" -ReuseStage <nul >> "%LOG%" 2>&1
echo ===== PACKAGE EXIT %ERRORLEVEL% >> "%LOG%"
echo ===== FINISHED %DATE% %TIME% >> "%LOG%"
echo.
echo Done. This window can be closed.
timeout /t 20 >nul
