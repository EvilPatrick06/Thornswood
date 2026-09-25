@echo off
title Skyrim Together - build and package
rem PowerShell 7 when it is installed, Windows PowerShell otherwise. The two
rem differ in ways that matter here, most of all whether a text file gets a
rem byte order mark, and the game stops dead on one.
set "PS=powershell"
where /q pwsh && set "PS=pwsh"
cd /d "%~dp0"
if not exist "C:\Thornswood\_dist" mkdir "C:\Thornswood\_dist"
set LOG=C:\Thornswood\_dist\run.log
echo ===== STARTED %DATE% %TIME% > "%LOG%"
echo.
echo Step 1 of 2: building the launcher
echo ===== BUILD LAUNCHER >> "%LOG%"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Launcher.ps1" <nul >> "%LOG%" 2>&1
echo ===== BUILD EXIT %ERRORLEVEL% >> "%LOG%"
echo.
echo Step 2 of 2: packaging. Twenty minutes or so the first time, and only
echo the files that changed after that.
echo ===== PACKAGE >> "%LOG%"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Package-Thornswood.ps1" -ReuseStage <nul >> "%LOG%" 2>&1
echo ===== PACKAGE EXIT %ERRORLEVEL% >> "%LOG%"
echo ===== FINISHED %DATE% %TIME% >> "%LOG%"
echo.
echo Done. This window can be closed.
timeout /t 20 >nul
