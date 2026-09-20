@echo off
setlocal
cd /d "%~dp0"
set "SP_CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%SP_CSC%" set "SP_CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%SP_CSC%" (
 echo .NET Framework compiler not found. Nothing was installed.
 pause
 exit /b 1
)
tasklist /fi "IMAGENAME eq ScreenPilotBridge.exe" | find /i "ScreenPilotBridge.exe" >nul
if not errorlevel 1 (
 echo Exit the old ScreenPilot window or tray process before updating.
 pause
 exit /b 1
)
set "SP_DIR=%LOCALAPPDATA%\ScreenPilotBridge"
if not exist "%SP_DIR%" mkdir "%SP_DIR%"
"%SP_CSC%" /nologo /target:winexe /win32icon:"%~dp0ScreenPilot.ico" /resource:"%~dp0ScreenPilot.ico",ScreenPilot.ico /resource:"%~dp0ThirdPartyNotices.txt",ScreenPilot.ThirdPartyNotices.txt /codepage:65001 /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /out:"%SP_DIR%\ScreenPilotBridge.exe" "%~dp0ScreenPilotBridge.cs" "%~dp0LocalControlPanel.cs" "%~dp0DesktopSetup.cs" "%~dp0AboutPanel.cs"
if errorlevel 1 (
 echo Build failed. If the bridge is already running, close its window first.
 pause
 exit /b 1
)
"%SP_DIR%\ScreenPilotBridge.exe" --self-test
if errorlevel 1 (
 echo Self-tests failed. The server will not start.
 pause
 exit /b 1
)
start "" "%SP_DIR%\ScreenPilotBridge.exe" --gui
