using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

public static partial class ScreenPilotBridge {
    static readonly object SwitchLock=new object(),LogLock=new object();
    static bool Switching;
    static DateTime NextSwitch=DateTime.MinValue;
    static string LastSwitchMessage="No switch sent";
    static volatile string NetworkStatus="网络未启用";
    static void Log(string kind,string detail) {
        lock(LogLock) try {
            Directory.CreateDirectory(ConfigDir);
            string clean=(detail??"").Replace("\r"," ").Replace("\n"," ").Replace("\t"," ");
            File.AppendAllText(Path.Combine(ConfigDir,"events-"+DateTime.UtcNow.ToString("yyyy-MM-dd")+".log"),DateTime.UtcNow.ToString("o")+"\tpid="+Process.GetCurrentProcess().Id+"\t"+kind+"\t"+clean+Environment.NewLine);
        } catch {}
    }
    static void Save(Settings s) {
        Directory.CreateDirectory(ConfigDir);
        if(String.IsNullOrEmpty(s.ProtectedKey) && s.Key.Length==32) s.ProtectedKey=Convert.ToBase64String(System.Security.Cryptography.ProtectedData.Protect(s.Key,null,System.Security.Cryptography.DataProtectionScope.CurrentUser));
        string temp=ConfigFile+".tmp";
        File.WriteAllLines(temp,new string[] { "listen="+(s.ListenIP??""),"mac="+(s.MacIP??""),"device="+Convert.ToBase64String(Encoding.UTF8.GetBytes(s.DeviceID)),"description="+Convert.ToBase64String(Encoding.UTF8.GetBytes(s.Description)),"protectedKey="+s.ProtectedKey,"network="+s.NetworkEnabled,"auto="+s.AutoEnabled,"trigger="+s.TriggerMode,"keyboard="+Convert.ToBase64String(Encoding.UTF8.GetBytes(s.KeyboardID)),"mouse="+Convert.ToBase64String(Encoding.UTF8.GetBytes(s.MouseID)) });
        if(File.Exists(ConfigFile)) File.Replace(temp,ConfigFile,null);else File.Move(temp,ConfigFile);
    }
    static Settings SetupLocal() {
        var screens=Screens();
        try {
            using(var form=new Form { Icon=BrandIcon(), Text="欢迎使用屏幕管家",ClientSize=new Size(580,220),StartPosition=FormStartPosition.CenterScreen,Font=new Font("Segoe UI",10),FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false }) {
                var text=new Label { Text="选择同时连接 Mac HDMI 1 / Windows HDMI 2 的显示器。\nUSB 自动切换无需网络，稍后在主窗口选择共享键鼠。",Left=20,Top=20,Width=540,Height=55 };
                var choice=new ComboBox { Left=20,Top=85,Width=540,DropDownStyle=ComboBoxStyle.DropDownList };
                foreach(var screen in screens) choice.Items.Add(screen.Physical.Description+" · "+screen.Device);
                if(screens.Count>0) choice.SelectedIndex=0;
                var ok=new Button { Text="开始使用",Left=430,Top=160,Width=130,DialogResult=DialogResult.OK,Enabled=screens.Count>0 };
                if(screens.Count==0) text.Text="未找到可控制的显示器。请接好视频线、唤醒显示器后重新打开软件。";
                form.Controls.AddRange(new Control[]{text,choice,ok});form.AcceptButton=ok;
                if(form.ShowDialog()!=DialogResult.OK) return null;
                var selected=screens[choice.SelectedIndex];
                int matches=0;foreach(var item in screens) if(item.ID==selected.ID && item.Physical.Description==selected.Physical.Description) matches++;
                if(matches!=1) throw new Exception("显示器身份不唯一，请检查连接后重试。");
                var settings=new Settings { ListenIP="",MacIP="",DeviceID=selected.ID,Description=selected.Physical.Description,Key=new byte[0],NetworkEnabled=false };
                Save(settings);return settings;
            }
        } finally { Close(screens); }
    }
    sealed class ArrivalGate {
        bool initialized,k,m,pending; double changed,lastFire=-100;
        public void Reset() { initialized=false; pending=false; }
        public bool Observe(bool keyboard,bool mouse,string mode,bool enabled,double now) {
            if(!enabled) { initialized=true;k=keyboard;m=mouse;pending=false;return false; }
            if(!initialized) { initialized=true;k=keyboard;m=mouse;return false; }
            if(k!=keyboard || m!=mouse) {
                bool addedK=!k&&keyboard,addedM=!m&&mouse;
                pending=mode=="keyboard"?addedK:mode=="mouse"?addedM:mode=="both"?(keyboard&&mouse&&(addedK||addedM)):(addedK||addedM);
                k=keyboard;m=mouse;changed=now;return false;
            }
            if(!pending || now-changed<1) return false;
            pending=false;if(now-lastFire<5) return false;lastFire=now;return true;
        }
    }
    [StructLayout(LayoutKind.Sequential)] struct RawDevice { public IntPtr Handle; public uint Type; }
    [DllImport("user32.dll",SetLastError=true)] static extern uint GetRawInputDeviceList([Out] RawDevice[] list,ref uint count,uint size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="GetRawInputDeviceInfoW",SetLastError=true)] static extern uint GetRawInputDeviceInfo(IntPtr device,uint command,IntPtr buffer,ref uint size);
    sealed class InputDevice { public string ID,Label; public bool Keyboard; }
    static List<InputDevice> Inputs() {
        var result=new List<InputDevice>(); uint count=0,size=(uint)Marshal.SizeOf(typeof(RawDevice));
        if(GetRawInputDeviceList(null,ref count,size)==uint.MaxValue || count>256) throw new Exception("Device list unavailable");
        var list=new RawDevice[count]; if(GetRawInputDeviceList(list,ref count,size)==uint.MaxValue) throw new Exception("Device list changed; observe again");
        for(int i=0;i<count;i++) {
            if(list[i].Type>1) continue;
            uint chars=0; GetRawInputDeviceInfo(list[i].Handle,0x20000007,IntPtr.Zero,ref chars);
            if(chars==0 || chars>4096) continue;
            IntPtr buffer=Marshal.AllocHGlobal(((int)chars+1)*2);
            try {
                Marshal.WriteInt16(buffer,(int)chars*2,0);
                if(GetRawInputDeviceInfo(list[i].Handle,0x20000007,buffer,ref chars)==uint.MaxValue) continue;
                string path=Marshal.PtrToStringUni(buffer).ToUpperInvariant();
                int vid=path.IndexOf("VID_"),pid=path.IndexOf("PID_"); if(vid<0||pid<0||vid+8>path.Length||pid+8>path.Length) continue;
                string shortID; using(var hash=System.Security.Cryptography.SHA256.Create()) shortID=Hex(hash.ComputeHash(Encoding.UTF8.GetBytes(path))).Substring(0,8);
                result.Add(new InputDevice { ID=path,Keyboard=list[i].Type==1,Label=path.Substring(vid,8)+" "+path.Substring(pid,8)+" · "+shortID });
            } finally { Marshal.FreeHGlobal(buffer); }
        }
        return result;
    }
    static void TestArrivalRules() {
        var gate=new ArrivalGate();
        if(gate.Observe(true,true,"either",true,0)||gate.Observe(false,false,"either",true,2)||gate.Observe(false,false,"either",true,4)) throw new Exception("Startup/removal triggered a switch");
        if(gate.Observe(true,false,"keyboard",true,5)||!gate.Observe(true,false,"keyboard",true,6.1)||gate.Observe(true,false,"keyboard",true,10)) throw new Exception("Arrival debounce failed");
        gate.Reset();gate.Observe(false,false,"both",true,20);gate.Observe(true,false,"both",true,21);
        if(gate.Observe(true,false,"both",true,23)) throw new Exception("Both-input rule failed");
        gate.Observe(true,true,"both",true,24);if(!gate.Observe(true,true,"both",true,25.1)) throw new Exception("Both-input arrival missed");
    }
    static Icon BrandIcon() {
        using(var stream=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("ScreenPilot.ico")) {
            if(stream==null) return (Icon)SystemIcons.Application.Clone();
            using(var icon=new Icon(stream)) return (Icon)icon.Clone();
        }
    }
    static void RunPanel(Settings settings,bool startHidden) {
        Application.EnableVisualStyles();
        ShowWindow(GetConsoleWindow(),0);
        Application.Run(new ControlPanel(settings,startHidden));
    }
    sealed class ControlPanel:Form {
        readonly Settings settings; readonly NotifyIcon tray=new NotifyIcon(); readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
        readonly Label state=new Label(),netState=new Label(),deviceState=new Label();
        readonly ComboBox keyboard=new ComboBox(),mouse=new ComboBox(),mode=new ComboBox();
        readonly CheckBox automatic=new CheckBox(); readonly ArrivalGate gate=new ArrivalGate(); readonly Stopwatch clock=Stopwatch.StartNew();
        string inventoryKey=""; bool updating,exitRequested; readonly bool startHidden;
        static FlowLayoutPanel Page(TabControl tabs,string title) {
            var page=new TabPage(title) { Padding=new Padding(8),BackColor=Color.White };
            var flow=new FlowLayoutPanel { Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(18) };
            page.Controls.Add(flow);tabs.TabPages.Add(page);return flow;
        }
        public ControlPanel(Settings s,bool hidden) {
            settings=s; startHidden=hidden;
            Icon=BrandIcon();
            Text="ScreenPilot "+ProductVersion+" · 显示器控制"; Size=new Size(750,620); MinimumSize=new Size(710,560); Font=new Font("Segoe UI",10); StartPosition=FormStartPosition.CenterScreen;
            var tabs=new TabControl { Dock=DockStyle.Fill,Padding=new Point(22,10) };Controls.Add(tabs);
            state.Dock=DockStyle.Bottom;state.Height=66;state.Padding=new Padding(20,12,20,8);state.BackColor=Color.FromArgb(237,243,241);Controls.Add(state);
            var layout=Page(tabs,"显示器");
            var brand=new FlowLayoutPanel { AutoSize=true,WrapContents=false,Margin=new Padding(0,0,0,18) };
            brand.Controls.Add(new PictureBox { Image=Icon.ToBitmap(),SizeMode=PictureBoxSizeMode.Zoom,Width=44,Height=44 });
            brand.Controls.Add(new Label { Text="屏幕管家  /  SCREEN PILOT",AutoSize=true,Font=new Font("Segoe UI",15,FontStyle.Bold),Margin=new Padding(12,8,0,0) });layout.Controls.Add(brand);
            layout.Controls.Add(new Label { Text="共享显示器："+s.Description,AutoSize=true });
            layout.Controls.Add(new Label { Text="本机约定：Windows = HDMI 2，Mac = HDMI 1",AutoSize=true });
            var buttons=new FlowLayoutPanel { AutoSize=true,WrapContents=false };
            var mac=new Button { Text="切到 Mac · HDMI 1",AutoSize=true }; mac.Click+=delegate { Request(17,"local-button"); }; buttons.Controls.Add(mac);
            var win=new Button { Text="显示 Windows · HDMI 2",AutoSize=true }; win.Click+=delegate { Request(18,"local-button"); }; buttons.Controls.Add(win); layout.Controls.Add(buttons);
            state.Text="就绪 · 本地按钮直接控制显示器，不使用网络。";
            layout.Controls.Add(new Label { Text="本地按钮用于从当前主机切走；自动跟随键鼠请在 USB 联动页配置。",AutoSize=true,MaximumSize=new Size(620,0),Margin=new Padding(0,18,0,12) });
            layout=Page(tabs,"USB 联动");
            layout.Controls.Add(new Label { Text="USB 局域网联动（接入 Windows 后请 Mac 切到 HDMI 2）",AutoSize=true,Margin=new Padding(0,18,0,3) });
            keyboard.DropDownStyle=mouse.DropDownStyle=mode.DropDownStyle=ComboBoxStyle.DropDownList; keyboard.Width=mouse.Width=600; mode.Width=240;
            layout.Controls.Add(new Label { Text="共享键盘接口",AutoSize=true });layout.Controls.Add(keyboard);
            layout.Controls.Add(new Label { Text="共享鼠标接口",AutoSize=true });layout.Controls.Add(mouse);
            mode.Items.AddRange(new object[]{"键盘接入","鼠标接入","任一接入","两者都接入"});
            mode.SelectedIndex=s.TriggerMode=="keyboard"?0:s.TriggerMode=="mouse"?1:s.TriggerMode=="both"?3:2;layout.Controls.Add(mode);
            automatic.Text="启用 USB 局域网自动切换";automatic.AutoSize=true;automatic.Checked=s.AutoEnabled;layout.Controls.Add(automatic);
            deviceState.AutoSize=true;deviceState.MaximumSize=new Size(620,0);layout.Controls.Add(deviceState);
            layout.Controls.Add(new Label { Text="启动/拔出不切屏；接入需稳定约1秒，并有5秒冷却。只检测连接，不读取按键内容。",AutoSize=true,MaximumSize=new Size(620,0) });
            layout=Page(tabs,"配对与设置");
            var tools=new FlowLayoutPanel { AutoSize=true,WrapContents=false,Margin=new Padding(0,15,0,0) };
            var copy=new Button { Text="复制网络配对码",AutoSize=true }; copy.Click+=delegate { if(ForceLocalOnly || !s.NetworkEnabled || s.Key.Length!=32 || !PrivateIP(s.ListenIP)||!PrivateIP(s.MacIP)) { state.Text="当前是本地模式；请点击“配置可选网络配对”。"; return; } Clipboard.SetText("SP1|"+s.ListenIP+"|"+Port+"|"+Convert.ToBase64String(s.Key)); state.Text="配对码已复制，仅粘贴到你自己的 Mac 软件。"; }; tools.Controls.Add(copy);
            var logs=new Button { Text="导出诊断（无密钥）",AutoSize=true };logs.Click+=delegate { Export(); };tools.Controls.Add(logs);
            var startup=new Button { Text="设置开机启动",AutoSize=true };startup.Click+=delegate { try { SetStartup(true);state.Text="已登记当前用户启动项，没有发送切换命令。"; } catch(Exception ex) { state.Text=ex.Message;Log("startup_error",ex.GetType().Name); } };tools.Controls.Add(startup);layout.Controls.Add(tools);
            var manage=new FlowLayoutPanel { AutoSize=true,WrapContents=false };
            var stopStartup=new Button { Text="取消开机启动",AutoSize=true };stopStartup.Click+=delegate { try { SetStartup(false);state.Text="已取消开机启动。"; } catch(Exception ex) { state.Text=ex.Message; } };manage.Controls.Add(stopStartup);
            var install=new Button { Text="安装到本机并创建桌面入口",AutoSize=true };install.Click+=delegate { try { InstallLocal();state.Text="安装完成。请退出当前窗口后使用桌面入口；下载文件夹可以删除。"; } catch(Exception ex) { state.Text=ex.Message; } };manage.Controls.Add(install);layout.Controls.Add(manage);
            var networkSetup=new Button { Text="配置可选网络配对…",AutoSize=true };networkSetup.Click+=delegate { try { SetupNetworkWindow(settings);state.Text="网络设置保存后请退出并重新打开；USB功能不受影响。"; } catch(Exception ex) { state.Text=ex.Message; } };layout.Controls.Add(networkSetup);
            var diagnostics=new Button { Text="打开只读网络诊断工具",AutoSize=true };
            diagnostics.Click+=delegate { try { var path=Path.Combine(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location),"Network-Diagnostics.cmd");if(!File.Exists(path)) { state.Text="请从新版完整压缩包运行 Network-Diagnostics.cmd，报告保存在桌面。";return; } Process.Start(new ProcessStartInfo(path) { UseShellExecute=true }); } catch(Exception ex) { state.Text=ex.Message; } };layout.Controls.Add(diagnostics);
            layout.Controls.Add(new Label { Text="网络异常时先从托盘退出软件作对照。软件不会更改 DNS、代理、网关或防火墙。",AutoSize=true,MaximumSize=new Size(620,0),Margin=new Padding(0,15,0,0) });
            netState.AutoSize=true;netState.MaximumSize=new Size(620,0);layout.Controls.Add(netState);
            PopulateAbout(Page(tabs,"关于"));
            try { RefreshInputs(); } catch { SetItems(keyboard,new List<InputDevice>(),true,settings.KeyboardID);SetItems(mouse,new List<InputDevice>(),false,settings.MouseID); } keyboard.SelectedIndexChanged+=Changed;mouse.SelectedIndexChanged+=Changed;mode.SelectedIndexChanged+=Changed;automatic.CheckedChanged+=Changed;
            tray.Icon=Icon;tray.Text="ScreenPilot 切屏";tray.Visible=true;
            var menu=new ContextMenuStrip();menu.Items.Add("打开控制窗口",null,delegate { Show();WindowState=FormWindowState.Normal;Activate(); });
            menu.Items.Add("切到 Mac（本地）",null,delegate { Request(17,"tray"); });menu.Items.Add("显示 Windows（本地）",null,delegate { Request(18,"tray"); });
            menu.Items.Add("关于屏幕管家",null,delegate { ShowAbout(this); });
            menu.Items.Add("退出",null,delegate { exitRequested=true;Close(); });tray.ContextMenuStrip=menu;tray.DoubleClick+=delegate { Show();WindowState=FormWindowState.Normal;Activate(); };
            timer.Interval=500;timer.Tick+=delegate { TickInputs(); };timer.Start();
            Shown+=delegate { if(startHidden) Hide(); };
            FormClosing+=delegate(object sender,FormClosingEventArgs e) { if(!exitRequested && e.CloseReason==CloseReason.UserClosing) { e.Cancel=true;Hide(); } };
            FormClosed+=delegate { timer.Stop();tray.Dispose(); };
        }
        void Request(int value,string source) {
            if(source=="usb-local") {
                if(ForceLocalOnly || !settings.NetworkEnabled) { state.Text="USB 联动需要启用网络配对；未发送切屏命令。";return; }
                lock(ArrivalLock) { ArrivalID=Guid.NewGuid().ToString("N");ArrivalTime=Now(); }
                state.Text="已记录接入，等待配对 Mac 通过局域网切到 HDMI 2。";
                Log("usb_lan_arrival","input=18; waiting for paired Mac");return;
            }
            state.Text="正在发送本机控制命令…";
            System.Threading.ThreadPool.QueueUserWorkItem(delegate {
                bool ok=ExecuteWorker(value,source);
                try { BeginInvoke((Action)delegate { state.Text=ok?"命令已发送，实际画面请确认。":LastSwitchMessage; }); } catch {}
            });
        }
        void SetItems(ComboBox box,List<InputDevice> devices,bool isKeyboard,string selected) {
            var pairs=new List<KeyValuePair<string,string>>();pairs.Add(new KeyValuePair<string,string>("","不监控"));
            bool found=String.IsNullOrEmpty(selected);
            foreach(var d in devices) if(d.Keyboard==isKeyboard) { pairs.Add(new KeyValuePair<string,string>(d.ID,d.Label)); if(d.ID==selected) found=true; }
            if(!found) pairs.Add(new KeyValuePair<string,string>(selected,"已选接口当前未连接"));
            box.DisplayMember="Value";box.ValueMember="Key";box.DataSource=pairs;box.SelectedValue=selected;
        }
        List<InputDevice> RefreshInputs() {
            var devices=Inputs();var ids=new List<string>();foreach(var d in devices) ids.Add(d.ID+":"+d.Keyboard);ids.Sort();string identity=String.Join("|",ids.ToArray());
            if(identity!=inventoryKey || keyboard.DataSource==null) { updating=true;SetItems(keyboard,devices,true,settings.KeyboardID);SetItems(mouse,devices,false,settings.MouseID);updating=false;inventoryKey=identity;Log("usb_inventory","interfaces="+devices.Count); }
            return devices;
        }
        void Changed(object sender,EventArgs e) {
            if(updating) return;
            settings.KeyboardID=keyboard.SelectedValue as string ?? "";settings.MouseID=mouse.SelectedValue as string ?? "";
            settings.TriggerMode=mode.SelectedIndex==0?"keyboard":mode.SelectedIndex==1?"mouse":mode.SelectedIndex==3?"both":"either";
            bool valid=settings.TriggerMode=="keyboard"?settings.KeyboardID!="":settings.TriggerMode=="mouse"?settings.MouseID!="":settings.TriggerMode=="both"?(settings.KeyboardID!=""&&settings.MouseID!=""):(settings.KeyboardID!=""||settings.MouseID!="");
            if(automatic.Checked&&!valid) { updating=true;automatic.Checked=false;updating=false;state.Text="请先选择要监控的共享接口。"; }
            settings.AutoEnabled=automatic.Checked;Save(settings);gate.Reset();Log("usb_settings","enabled="+settings.AutoEnabled+" mode="+settings.TriggerMode);
        }
        void TickInputs() {
            if(!Visible && !settings.AutoEnabled) return;
            try {
                var devices=RefreshInputs();bool k=false,m=false;foreach(var d in devices) { if(d.Keyboard&&d.ID==settings.KeyboardID) k=true;if(!d.Keyboard&&d.ID==settings.MouseID) m=true; }
                deviceState.Text="键盘接口："+(k?"已连接":"未连接")+"  鼠标接口："+(m?"已连接":"未连接");netState.Text=NetworkStatus+"（USB联动需要此服务；手动按钮本地执行）";
                if(clock.Elapsed.TotalSeconds<3) { gate.Reset();gate.Observe(k,m,settings.TriggerMode,settings.AutoEnabled,clock.Elapsed.TotalSeconds); }
                else if(gate.Observe(k,m,settings.TriggerMode,settings.AutoEnabled,clock.Elapsed.TotalSeconds)) Request(18,"usb-local");
            } catch(Exception ex) { deviceState.Text="设备检测失败："+ex.GetType().Name; }
        }
        void Export() {
            using(var dialog=new SaveFileDialog { FileName="ScreenPilot-diagnostics.txt",Filter="文本文件|*.txt" }) if(dialog.ShowDialog()==DialogResult.OK) {
                var lines=new List<string>();lines.Add("ScreenPilot "+ProductVersion+"; startup registration never sends a display command.");
                using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run")) lines.Add("Startup="+(key==null?"":Convert.ToString(key.GetValue("ScreenPilotBridge",""))));
                foreach(var p in Process.GetProcessesByName("ScreenPilotBridge")) { lines.Add("Process PID="+p.Id+" (workers can temporarily add a second process)");p.Dispose(); }
                foreach(string file in Directory.GetFiles(ConfigDir,"events-*.log")) { lines.Add("--- "+Path.GetFileName(file));lines.AddRange(File.ReadAllLines(file)); }
                File.WriteAllLines(dialog.FileName,lines.ToArray());state.Text="诊断已导出，不包含配对密钥或按键内容。";
            }
        }
    }
}
