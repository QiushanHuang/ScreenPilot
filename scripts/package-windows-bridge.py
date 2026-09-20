#!/usr/bin/env python3
from pathlib import Path
import zipfile
root=Path(__file__).resolve().parents[1]
(root/'dist').mkdir(exist_ok=True)
with zipfile.ZipFile(root/'dist/ScreenPilot-WindowsBridge.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((root/'WindowsBridge').iterdir()):
        if path.is_file():archive.write(path,arcname='ScreenPilot-WindowsBridge/'+path.name)

    for name in ['README.md','LICENSE']:
        archive.write(root/name,arcname='ScreenPilot-WindowsBridge/'+name)
    executable=root/"WindowsBridge/bin/Release/net48/ScreenPilotBridge.exe"
    if executable.exists(): archive.write(executable,arcname="ScreenPilot-WindowsBridge/ScreenPilotBridge.exe")
