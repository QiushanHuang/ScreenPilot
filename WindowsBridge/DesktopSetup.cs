using System;
using System.IO;
using System.Reflection;
using System.Drawing;
using System.Windows.Forms;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;

public static partial class ScreenPilotBridge {
    static void InstallLocal() {
        string folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ScreenPilotBridge");
        Directory.CreateDirectory(folder);
        string target=Path.Combine(folder,"ScreenPilotBridge.exe"),source=Assembly.GetExecutingAssembly().Location;
        if(!String.Equals(Path.GetFullPath(source),Path.GetFullPath(target),StringComparison.OrdinalIgnoreCase)) File.Copy(source,target,true);
        foreach(string name in new string[]{"Network-Diagnostics.cmd","Network-Diagnostics.ps1"}) {
            string origin=Path.Combine(Path.GetDirectoryName(source),name),destination=Path.Combine(folder,name);
            if(File.Exists(origin) && !String.Equals(Path.GetFullPath(origin),Path.GetFullPath(destination),StringComparison.OrdinalIgnoreCase)) File.Copy(origin,destination,true);
        }
        Type shellType=Type.GetTypeFromProgID("WScript.Shell");object shell=Activator.CreateInstance(shellType);
        object shortcut=shellType.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"屏幕管家.lnk")});
        try {
            var type=shortcut.GetType();type.InvokeMember("TargetPath",BindingFlags.SetProperty,null,shortcut,new object[]{target});
            type.InvokeMember("WorkingDirectory",BindingFlags.SetProperty,null,shortcut,new object[]{folder});
            type.InvokeMember("Save",BindingFlags.InvokeMethod,null,shortcut,null);
        } finally { System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shortcut);System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell); }
    }
    static Settings SetupNetworkWindow(Settings current) {
        using(var form=new Form { Icon=BrandIcon(), Text="可选：Mac 网络按钮配对",ClientSize=new Size(560,270),StartPosition=FormStartPosition.CenterScreen,Font=new Font("Segoe UI",10) }) {
            var info=new Label { Left=20,Top=15,Width=520,Height=60,Text="此设置只用于 Mac 上的网络切回按钮。\\nUSB 自动切换不需要配对。保存后请重新打开软件。".Replace("\\n","\n") };
            var ip=new ComboBox { Left=20,Top=85,Width=520,DropDownStyle=ComboBoxStyle.DropDownList };
            foreach(var ni in NetworkInterface.GetAllNetworkInterfaces()) if(ni.OperationalStatus==OperationalStatus.Up) foreach(var addr in ni.GetIPProperties().UnicastAddresses) if(addr.Address.AddressFamily==AddressFamily.InterNetwork && PrivateIP(addr.Address.ToString()) && !ip.Items.Contains(addr.Address.ToString())) ip.Items.Add(addr.Address.ToString());
            if(ip.Items.Count>0) ip.SelectedIndex=0;
            var label=new Label { Text="允许连接的 Mac 局域网 IPv4 地址",Left=20,Top=130,Width=520 };
            var mac=new TextBox { Left=20,Top=155,Width=520,Text=current.MacIP??"" };
            var save=new Button { Text="保存配对",Left=400,Top=215,Width=140 };
            save.Click+=delegate {
                if(ip.SelectedItem==null || !PrivateIP(mac.Text.Trim())) { MessageBox.Show("请选择 Windows 地址并填写正确的 Mac 局域网 IPv4。");return; }
                current.ListenIP=(string)ip.SelectedItem;current.MacIP=mac.Text.Trim();current.Key=new byte[32];using(var rng=RandomNumberGenerator.Create()) rng.GetBytes(current.Key);
                current.ProtectedKey="";current.NetworkEnabled=true;Save(current);form.DialogResult=DialogResult.OK;form.Close();
            };
            form.Controls.AddRange(new Control[]{info,ip,label,mac,save});form.ShowDialog();return current;
        }
    }
}
