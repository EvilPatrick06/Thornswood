@echo off
rem Double click this to throw away the character on the server, so the next
rem launch runs creation from the top. Nothing is deleted, it is moved aside.
rem PowerShell 7 when it is installed, Windows PowerShell otherwise. The two
rem differ in ways that matter here, most of all whether a text file gets a
rem byte order mark, and the game stops dead on one.
set "PS=powershell"
where /q pwsh && set "PS=pwsh"
cd /d "%~dp0"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reset-Character.ps1"
