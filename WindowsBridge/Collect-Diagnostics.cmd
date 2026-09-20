@echo off
setlocal
set "SP_OUT=%TEMP%\ScreenPilot-diagnostics.txt"
(
 echo ScreenPilot read-only diagnostics. No display commands are sent.
 echo Startup value:
 reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v ScreenPilotBridge
 echo Process list - a temporary worker is normal during a switch:
 tasklist /fi "IMAGENAME eq ScreenPilotBridge.exe"
 echo Control event logs - no pairing code or key:
 type "%APPDATA%\ScreenPilotBridge\events-*.log"
) > "%SP_OUT%" 2>&1
notepad "%SP_OUT%"
