"""Run the Windows production protocol and arrival self-tests without Win32 hardware."""
from pathlib import Path
import subprocess, os, shutil
root=Path(__file__).resolve().parents[1]
main=(root/'WindowsBridge/ScreenPilotBridge.cs').read_text(encoding='utf-8')
local=(root/'WindowsBridge/LocalControlPanel.cs').read_text(encoding='utf-8')
work=root/'.build/windows-core-tests';work.mkdir(exist_ok=True)
parts=[main[main.index('    sealed class Settings'):main.index('    [StructLayout')], main[main.index('    static string Hex'):main.index('    static void LoadNonces')],local[local.index('    sealed class ArrivalGate'):local.index('    [StructLayout')],local[local.index('    static void TestArrivalRules'):local.index('    static Icon BrandIcon')],main[main.index('    static void SelfTest()'):main.index('    [STAThread]')]]
(work/'Program.cs').write_text('using System;using System.Collections.Generic;using System.Globalization;using System.Security.Cryptography;using System.Text;\nclass CoreTests { static readonly Dictionary<string,long> Nonces=new Dictionary<string,long>();\n'+ '\n'.join(parts)+'\n static void Main(){ SelfTest(); } }',encoding='utf-8')
(work/'Tests.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework><OutputType>Exe</OutputType><NoWarn>0649</NoWarn></PropertyGroup></Project>',encoding='utf-8')
subprocess.run([os.environ.get('DOTNET_HOST_PATH') or shutil.which('dotnet') or str(root/'.build/windows-tools/dotnet/dotnet'),'run','--project',str(work/'Tests.csproj'),'-c','Release'],check=True)
