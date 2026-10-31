@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Action Install %*
set "result=%errorlevel%"
if not defined DESKTOP_CLEANER_NO_PAUSE pause
exit /b %result%
