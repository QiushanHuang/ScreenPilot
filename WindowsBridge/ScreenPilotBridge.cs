// ScreenPilot bridge: one paired Mac, one selected monitor, HDMI 1 only.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Microsoft.Win32;

[assembly: AssemblyCopyright("© 2026 QiushanHuang")]
[assembly: AssemblyCompany("QiushanHuang")]
[assembly: AssemblyProduct("ScreenPilot")]
[assembly: AssemblyTitle("屏幕管家 · ScreenPilot")]
[assembly: AssemblyDescription("显示器输入切换与 USB 局域网联动 · QiushanHuang")]
[assembly: AssemblyVersion("1.6.3.0")]
[assembly: AssemblyFileVersion("1.6.3.0")]

public static partial class ScreenPilotBridge {
    const int Port=43871;
    static readonly object ArrivalLock=new object();
    static string ArrivalID=Guid.NewGuid().ToString("N");
    static long ArrivalTime=0;
    static bool ForceLocalOnly;
    static string ConfigDir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"ScreenPilotBridge");
    static string ConfigFile=Path.Combine(ConfigDir,"settings.ini");
    static readonly Dictionary<string,long> Nonces=new Dictionary<string,long>();
    sealed class Settings { public string ListenIP,MacIP,DeviceID,Description; public byte[] Key; public bool NetworkEnabled,AutoEnabled; public string KeyboardID="",MouseID="",TriggerMode="either",ProtectedKey=""; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct MonitorInfo {
        public int Size; public Rect Monitor,Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Device;
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct DisplayDevice {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Description;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string ID;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Key;
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Physical {
        public IntPtr Handle;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Description;
    }
    sealed class Screen { public Physical Physical; public string ID,Device; public Rect Rect; }
    delegate bool MonitorCallback(IntPtr monitor,IntPtr hdc,ref Rect rect,IntPtr data);
    [DllImport("user32.dll",SetLastError=true)] static extern bool EnumDisplayMonitors(IntPtr hdc,IntPtr clip,MonitorCallback cb,IntPtr data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="GetMonitorInfoW",SetLastError=true)] static extern bool GetMonitorInfo(IntPtr monitor,ref MonitorInfo info);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="EnumDisplayDevicesW",SetLastError=true)] static extern bool EnumDisplayDevices(string device,uint index,ref DisplayDevice info,uint flags);
    [DllImport("dxva2.dll",SetLastError=true)] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor,out uint count);
    [DllImport("dxva2.dll",SetLastError=true)] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor,uint count,[Out] Physical[] physical);
    [DllImport("dxva2.dll",SetLastError=true)] static extern bool SetVCPFeature(IntPtr monitor,byte code,uint value);
    [DllImport("dxva2.dll",SetLastError=true)] static extern bool DestroyPhysicalMonitor(IntPtr monitor);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window,int command);
    static long Now() { return (long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalSeconds; }
    static string Hex(byte[] data) { return BitConverter.ToString(data).Replace("-","").ToLowerInvariant(); }
    static string Sign(byte[] key,string text) { using(var h=new HMACSHA256(key)) return Hex(h.ComputeHash(Encoding.UTF8.GetBytes(text))); }
    static bool Equal(string a,string b) { if(a==null || b==null || a.Length!=b.Length) return false; int d=0; for(int i=0;i<a.Length;i++) d|=a[i]^b[i]; return d==0; }
    static bool PrivateIP(string host) {
        string[] parts=host.Split('.'); if(parts.Length!=4) return false; int[] n=new int[4];
        for(int i=0;i<4;i++) if(!int.TryParse(parts[i],NumberStyles.None,CultureInfo.InvariantCulture,out n[i]) || n[i]>255 || n[i]<0 || n[i].ToString(CultureInfo.InvariantCulture)!=parts[i]) return false;
        return n[0]==10 || (n[0]==172 && n[1]>=16 && n[1]<=31) || (n[0]==192 && n[1]==168);
    }
    static bool Authenticate(Settings s,string method,string path,string stamp,string nonce,string signature,long now) {
        long time;
        if(stamp==null || stamp.Length>12 || !long.TryParse(stamp,NumberStyles.None,CultureInfo.InvariantCulture,out time) || time<now-60 || time>now+60) return false;
        if(nonce==null || nonce.Length!=32 || signature==null || signature.Length!=64) return false;
        foreach(char c in nonce) if(!((c>='0'&&c<='9')||(c>='a'&&c<='f'))) return false;
        if(!Equal(Sign(s.Key,stamp+"\n"+nonce+"\n"+method+"\n"+path),signature)) return false;
        var expired=new List<string>(); foreach(var pair in Nonces) if(pair.Value<now-90) expired.Add(pair.Key);
        foreach(string key in expired) Nonces.Remove(key);
        if(Nonces.ContainsKey(nonce) || Nonces.Count>=256) return false;
        Nonces[nonce]=now; return true;
    }
    static void LoadNonces() {
        string path=Path.Combine(ConfigDir,"nonces.txt");
        if(!File.Exists(path)) return;
        foreach(string line in File.ReadAllLines(path)) {
            string[] p=line.Split('|'); long time;
            if(p.Length==2 && p[0].Length==32 && long.TryParse(p[1],out time) && time>=Now()-90 && time<=Now()+60 && Nonces.Count<256) Nonces[p[0]]=time;
        }
    }
    static void SaveNonces() {
        var lines=new List<string>(); foreach(var item in Nonces) lines.Add(item.Key+"|"+item.Value.ToString(CultureInfo.InvariantCulture));
        string path=Path.Combine(ConfigDir,"nonces.txt"),temp=path+".tmp";
        File.WriteAllLines(temp,lines.ToArray());
        if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
    }
    static List<Screen> Screens() {
        var list=new List<Screen>();
        MonitorCallback cb=delegate(IntPtr monitor,IntPtr hdc,ref Rect rect,IntPtr data) {
            var info=new MonitorInfo(); info.Size=Marshal.SizeOf(typeof(MonitorInfo));
            var device=new DisplayDevice(); device.Size=Marshal.SizeOf(typeof(DisplayDevice));
            if(!GetMonitorInfo(monitor,ref info) || !EnumDisplayDevices(info.Device,0,ref device,1) || String.IsNullOrEmpty(device.ID)) return true;
            uint count; if(!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor,out count) || count!=1) return true;
            var physical=new Physical[count]; if(!GetPhysicalMonitorsFromHMONITOR(monitor,count,physical)) return true;
            list.Add(new Screen { Physical=physical[0],ID=device.ID,Device=info.Device,Rect=rect }); return true;
        };
        if(!EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,cb,IntPtr.Zero)) { Close(list); throw new Exception("Monitor enumeration failed"); }
        GC.KeepAlive(cb); return list;
    }
    static void Close(List<Screen> list) { foreach(var s in list) DestroyPhysicalMonitor(s.Physical.Handle); }
    static Settings Load(bool requireKey=true) {
        var data=new Dictionary<string,string>();
        foreach(string line in File.ReadAllLines(ConfigFile)) { int i=line.IndexOf('='); if(i>0) data[line.Substring(0,i)]=line.Substring(i+1); }
        var s=new Settings { ListenIP=data["listen"],MacIP=data["mac"],DeviceID=Encoding.UTF8.GetString(Convert.FromBase64String(data["device"])),Description=Encoding.UTF8.GetString(Convert.FromBase64String(data["description"])),Key=new byte[0],ProtectedKey=data.ContainsKey("protectedKey")?data["protectedKey"]:"" };
        try { if(requireKey && s.ProtectedKey.Length>0) s.Key=ProtectedData.Unprotect(Convert.FromBase64String(s.ProtectedKey),null,DataProtectionScope.CurrentUser); }
        catch { if(requireKey) throw; Log("network_key_unavailable","local controls remain available"); }
        s.NetworkEnabled=data.ContainsKey("network")?data["network"]=="True":PrivateIP(s.ListenIP)&&PrivateIP(s.MacIP);
        s.AutoEnabled=data.ContainsKey("auto")&&data["auto"]=="True";
        if(data.ContainsKey("keyboard")) s.KeyboardID=Encoding.UTF8.GetString(Convert.FromBase64String(data["keyboard"]));
        if(data.ContainsKey("mouse")) s.MouseID=Encoding.UTF8.GetString(Convert.FromBase64String(data["mouse"]));
        if(data.ContainsKey("trigger")) s.TriggerMode=data["trigger"];
        if(requireKey && (s.Key.Length!=32 || (s.NetworkEnabled&&(!PrivateIP(s.ListenIP)||!PrivateIP(s.MacIP))))) throw new Exception("Invalid settings; run --setup"); return s;
    }
    static int Choose(string prompt,int count) { Console.Write(prompt); int n; if(!int.TryParse(Console.ReadLine(),out n)||n<1||n>count) throw new Exception("Cancelled; nothing changed"); return n-1; }
    static Settings Setup() {
        var ips=new List<string>();
        foreach(var ni in NetworkInterface.GetAllNetworkInterfaces()) if(ni.OperationalStatus==OperationalStatus.Up)
            foreach(var u in ni.GetIPProperties().UnicastAddresses) if(u.Address.AddressFamily==AddressFamily.InterNetwork && PrivateIP(u.Address.ToString()) && !ips.Contains(u.Address.ToString())) ips.Add(u.Address.ToString());
        if(ips.Count==0) throw new Exception("No private IPv4 address available");
        for(int i=0;i<ips.Count;i++) Console.WriteLine("{0}. Listen on {1}",i+1,ips[i]);
        string ip=ips[Choose("Choose Windows LAN address: ",ips.Count)];
        Console.Write("Paired Mac LAN IPv4: "); string mac=Console.ReadLine();
        if(!PrivateIP(mac)) throw new Exception("Invalid Mac LAN IPv4");
        var screens=Screens(); Settings s;
        try {
            for(int i=0;i<screens.Count;i++) Console.WriteLine("{0}. {1} ({2}), desktop ({3},{4})",i+1,screens[i].Physical.Description,screens[i].Device,screens[i].Rect.Left,screens[i].Rect.Top);
            if(screens.Count==0) throw new Exception("No unambiguous physical monitors found");
            var selected=screens[Choose("Choose the shared monitor wired to Mac HDMI 1 / Windows HDMI 2: ",screens.Count)];
            int matches=0; foreach(var item in screens) if(item.ID==selected.ID && item.Physical.Description==selected.Physical.Description) matches++;
            if(matches!=1) throw new Exception("Monitor identity is ambiguous; no configuration saved");
            var key=new byte[32]; using(var rng=RandomNumberGenerator.Create()) rng.GetBytes(key);
            s=new Settings { ListenIP=ip,MacIP=mac,DeviceID=selected.ID,Description=selected.Physical.Description,Key=key,NetworkEnabled=true };
        } finally { Close(screens); }
        Save(s);
        return s;
    }
    static void Pairing(Settings s) {
        Console.WriteLine("Paste this pairing code into ScreenPilot on your Mac. Treat it as a private key:");
        Console.WriteLine("SP1|"+s.ListenIP+"|"+Port+"|"+Convert.ToBase64String(s.Key));
        Console.WriteLine("Accepts only paired Mac "+s.MacIP+". No network key is sent in plaintext.");
    }
    static int SwitchOnce(Settings settings,int value) {
        if(value!=17 && value!=18) return 2;
        var screens=Screens();
        try {
            Screen selected=null; int matches=0;
            foreach(var s in screens) if(s.ID==settings.DeviceID && s.Physical.Description==settings.Description) { selected=s; matches++; }
            if(matches!=1) { Console.Error.WriteLine("Configured monitor missing or ambiguous"); return 3; }
            if(!SetVCPFeature(selected.Physical.Handle,0x60,(uint)value)) { Console.Error.WriteLine("DDC write failed: "+Marshal.GetLastWin32Error()); return 4; }
            Console.WriteLine("Command sent; physical result not verified"); return 0;
        } finally { Close(screens); }
    }
    static bool ExecuteWorker(int value=17,string source="network") {
        lock(SwitchLock) {
            if(Switching || DateTime.UtcNow<NextSwitch) { LastSwitchMessage="切换进行中或冷却中，请等待5秒。";Log("switch_rejected",source);return false; }
            Switching=true;
        }
        try {
            Log("switch_begin","source="+source+" input="+value);
            var start=new ProcessStartInfo(Assembly.GetExecutingAssembly().Location,"--switch-once "+value);
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;
            using(var p=Process.Start(start)) {
                if(!p.WaitForExit(5000)) { try { p.Kill(); } catch {} LastSwitchMessage="显示器控制超时，结果未确认。";Log("switch_timeout","worker="+p.Id);return false; }
                bool ok=p.ExitCode==0;LastSwitchMessage=ok?"命令已发送，结果需观察。":"本机命令失败，请导出诊断。";
                Log("switch_end","source="+source+" input="+value+" worker="+p.Id+" exit="+p.ExitCode+" detail="+p.StandardError.ReadToEnd());return ok;
            }
        } catch(Exception e) { LastSwitchMessage=e.Message;Log("switch_exception",e.GetType().Name);return false; }
        finally { lock(SwitchLock) { Switching=false;NextSwitch=DateTime.UtcNow.AddSeconds(5); } }
    }
    static void SetStartup(bool enabled) {
        if(enabled) { Load(false); InstallLocal(); }
        using(var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run")) {
            if(enabled) key.SetValue("ScreenPilotBridge","\""+Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ScreenPilotBridge","ScreenPilotBridge.exe")+"\" --serve");else key.DeleteValue("ScreenPilotBridge",false);
        }
        Log(enabled?"startup_enabled":"startup_disabled","registry_only; no display command");
    }
    static void StartOptionalNetwork(Settings settings) {
        if(ForceLocalOnly || !settings.NetworkEnabled) { NetworkStatus="网络服务关闭";return; }
        var thread=new Thread(delegate() {
            try {
                if(settings.Key.Length!=32) settings.Key=ProtectedData.Unprotect(Convert.FromBase64String(settings.ProtectedKey),null,DataProtectionScope.CurrentUser);
                if(settings.Key.Length!=32 || !PrivateIP(settings.ListenIP) || !PrivateIP(settings.MacIP)) throw new Exception("Network configuration unavailable");
                var listener=new TcpListener(IPAddress.Parse(settings.ListenIP),Port);listener.Start(4);
                NetworkStatus="网络服务："+settings.ListenIP+":"+Port;Log("server_started",settings.ListenIP);
                while(true) using(var client=listener.AcceptTcpClient()) { try { Handle(client,settings); } catch(Exception e) { Log("network_error",e.GetType().Name); } }
            } catch(Exception e) { NetworkStatus="网络服务不可用，本地/USB仍可使用";Log("network_unavailable",e.GetType().Name); }
        });thread.IsBackground=true;thread.Start();
    }
    static void Reply(NetworkStream stream,Settings settings,string nonce,int status,string body) {
        string signature=Sign(settings.Key,(nonce??"")+"\n"+status.ToString(CultureInfo.InvariantCulture)+"\n"+body);
        byte[] bytes=Encoding.UTF8.GetBytes(body);
        string header="HTTP/1.1 "+status+" Result\r\nContent-Type: application/json\r\nContent-Length: "+bytes.Length+"\r\nX-SP-Response: "+signature+"\r\nConnection: close\r\n\r\n";
        byte[] head=Encoding.ASCII.GetBytes(header); stream.Write(head,0,head.Length); stream.Write(bytes,0,bytes.Length);
    }
    static void Handle(TcpClient client,Settings settings) {
        var remote=client.Client.RemoteEndPoint as IPEndPoint;
        if(remote==null || remote.Address.ToString()!=settings.MacIP) return;
        client.ReceiveTimeout=2000; client.SendTimeout=2000;
        using(var stream=client.GetStream()) {
            var bytes=new List<byte>(); int c;
            while(bytes.Count<8192 && (c=stream.ReadByte())>=0) {
                bytes.Add((byte)c); int n=bytes.Count;
                if(n>=4 && bytes[n-4]==13 && bytes[n-3]==10 && bytes[n-2]==13 && bytes[n-1]==10) break;
            }
            string text=Encoding.ASCII.GetString(bytes.ToArray());
            if(!text.EndsWith("\r\n\r\n")) return;
            string[] lines=text.Split(new string[]{"\r\n"},StringSplitOptions.None); string[] first=lines[0].Split(' ');
            if(first.Length!=3) return;
            var headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            for(int i=1;i<lines.Length;i++) {
                if(lines[i].Length==0) continue; int colon=lines[i].IndexOf(':'); if(colon<1) return;
                string k=lines[i].Substring(0,colon).Trim(); if(headers.ContainsKey(k)) return; headers[k]=lines[i].Substring(colon+1).Trim();
            }
            string nonce,stamp,signature,length;
            headers.TryGetValue("X-SP-Nonce",out nonce); headers.TryGetValue("X-SP-Time",out stamp); headers.TryGetValue("X-SP-Signature",out signature); headers.TryGetValue("Content-Length",out length);
            if(length!="0" || headers.ContainsKey("Transfer-Encoding")) { Reply(stream,settings,nonce,400,"{\"ok\":false,\"error\":\"bad_request\"}"); return; }
            string method=first[0],path=first[1];
            if(!((method=="GET"&&(path=="/health"||path=="/usb-arrival"))||(method=="POST"&&path=="/switch-to-mac"))) { Reply(stream,settings,nonce,404,"{\"ok\":false,\"error\":\"unknown_action\"}"); return; }
            if(!Authenticate(settings,method,path,stamp,nonce,signature,Now())) { Reply(stream,settings,nonce,403,"{\"ok\":false,\"error\":\"authentication_failed\"}"); return; }
            if(method=="POST") SaveNonces(); // Persist only mutations; read-only polling has no side effects to replay.
            if(path=="/usb-arrival") {
                lock(ArrivalLock) Reply(stream,settings,nonce,200,"{\"ok\":true,\"ready\":true,\"arrivalID\":\""+ArrivalID+"\",\"arrivalTime\":"+ArrivalTime.ToString(CultureInfo.InvariantCulture)+"}");
                return;
            }
            if(path=="/health") { Reply(stream,settings,nonce,200,"{\"ok\":true,\"ready\":true}"); return; }
            bool sent=ExecuteWorker(); Reply(stream,settings,nonce,sent?200:502,sent?"{\"ok\":true,\"sent\":true}":"{\"ok\":false,\"error\":\"monitor_command_failed\"}");
        }
    }
    static void SelfTest() {
        byte[] key=new byte[32]; for(int i=0;i<key.Length;i++) key[i]=(byte)i;
        string nonce="0123456789abcdef0123456789abcdef",stamp="1700000000";
        string signed=Sign(key,stamp+"\n"+nonce+"\nPOST\n/switch-to-mac");
        if(signed!="afedb0a5017bbcfc714de465e6b5d83a855364090768e96ef463607293a61372") throw new Exception("Request HMAC test failed");
        if(Sign(key,nonce+"\n200\n{\"ok\":true,\"sent\":true}")!="0b227e04e974972854f9c1858aa20f89149e0bb44ef045bbef78a222fea90c01") throw new Exception("Response HMAC test failed");
        var s=new Settings { Key=key };
        if(!Authenticate(s,"POST","/switch-to-mac",stamp,nonce,signed,1700000000)) throw new Exception("Auth test failed");
        if(Authenticate(s,"POST","/switch-to-mac",stamp,nonce,signed,1700000000)) throw new Exception("Replay accepted");
        Nonces.Clear();
        if(Authenticate(s,"POST","/switch-to-mac",stamp,nonce,signed,1700000100)) throw new Exception("Expired request accepted");
        if(!PrivateIP("192.168.31.10") || PrivateIP("127.0.0.1") || PrivateIP("8.8.8.8") || PrivateIP("010.0.0.1")) throw new Exception("IP test failed");
        TestArrivalRules();
        Console.WriteLine("Protocol + offline USB self-tests passed. No monitor commands sent.");
    }
    [STAThread]
    public static int Main(string[] args) {
        try {
            string mode=args.Length==0?"":args[0];
            if(mode=="--self-test") { SelfTest(); return 0; }
            if(mode=="--switch-once") { int value=args.Length>1?int.Parse(args[1]):17;return SwitchOnce(Load(false),value); }
            if(mode=="--pairing") { Pairing(Load()); return 0; }
            if(mode=="--enable-startup" || mode=="--disable-startup") {
                SetStartup(mode=="--enable-startup");
                Console.WriteLine("Current-user startup setting updated."); return 0;
            }
            if(mode!="" && mode!="--setup" && mode!="--serve" && mode!="--gui" && mode!="--local") throw new Exception("Unknown option");
            bool created;
            using(var mutex=new Mutex(true,@"Local\ScreenPilotBridge",out created)) {
                if(!created) throw new Exception("Bridge already running. 请从系统托盘打开已有窗口，或退出旧程序后再更新。");
                System.Windows.Forms.Application.EnableVisualStyles();
                Settings settings=File.Exists(ConfigFile)?Load(false):SetupLocal();
                if(settings==null) return 0;
                if(mode=="--setup") settings=SetupNetworkWindow(settings);
                if(mode=="--local") ForceLocalOnly=true;
                LoadNonces();Log("ui_started","mode="+mode+" auto="+settings.AutoEnabled);
                StartOptionalNetwork(settings);
                RunPanel(settings,mode=="--serve");
                return 0;
            }
        } catch(Exception e) {
            Console.Error.WriteLine(e.Message);Log("program_error",e.GetType().Name+" "+e.Message);
            string mode=args.Length==0?"":args[0];
            if(mode=="" || mode=="--gui" || mode=="--serve" || mode=="--local" || mode=="--setup") System.Windows.Forms.MessageBox.Show(e.Message,"ScreenPilot",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
            return 1;
        }
    }
}
