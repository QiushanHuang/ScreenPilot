from pathlib import Path
import zipfile
root=Path(__file__).resolve().parents[1]
exe=root/'WindowsBridge/bin/Release/net48/ScreenPilotBridge.exe'
(root/'dist').mkdir(exist_ok=True)
assert exe.read_bytes()[:2]==b'MZ'
with zipfile.ZipFile(root/'dist/ScreenPilot-Windows.zip','w',zipfile.ZIP_DEFLATED) as z:
 z.write(exe,'ScreenPilot/ScreenPilotBridge.exe')
 for name in ['README.md','LICENSE']:
  z.write(root/name,'ScreenPilot/'+name)
 config=exe.with_suffix('.exe.config')
 if config.exists(): z.write(config,'ScreenPilot/'+config.name)
 z.write(root/'WindowsBridge/开始使用.txt','ScreenPilot/开始使用.txt')
 for name in ['Network-Diagnostics.cmd','Network-Diagnostics.ps1','ThirdPartyNotices.txt']:
  z.write(root/'WindowsBridge'/name,'ScreenPilot/'+name)
print(root/'dist/ScreenPilot-Windows.zip')
