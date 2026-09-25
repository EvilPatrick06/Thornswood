@echo off
title Thornswood - Setup
rem PowerShell 7 when it is installed, Windows PowerShell otherwise. The two
rem differ in ways that matter here, most of all whether a text file gets a
rem byte order mark, and the game stops dead on one.
set "PS=powershell"
where /q pwsh && set "PS=pwsh"
cd /d "%~dp0"

rem The folder the person picked in the setup window arrives here as the first
rem argument, and this line used to drop it. Setup-Thornswood.ps1 then fell back
rem to its own default, so choosing D: got you an install on C: with no error
rem and nothing in the output to say why.
rem
rem %~1 strips the quotes the setup program put round the path so they are not
rem doubled back on, and the empty case matters because this file is also run by
rem hand out of an unpacked payload, where there is no argument at all.
set "ROOT=%~1"
if "%ROOT%"=="" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Thornswood.ps1" -MovePayload
) else (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Thornswood.ps1" -MovePayload -Root "%ROOT%"
)
