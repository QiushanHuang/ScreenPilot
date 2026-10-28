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
    static bool SetupNetworkWindow(Settings current) {
        using(var form=new Form { Icon=BrandIcon(), Text="Windows 与 Mac 配对",ClientSize=new Size(560,260),StartPosition=FormStartPosition.CenterScreen,Font=new Font("Segoe UI",10),FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false }) {
            var ipLabel=new Label { Text="Windows 局域网地址",Left=20,Top=20,Width=520 };
            var ip=new ComboBox { Left=20,Top=45,Width=520,DropDownStyle=ComboBoxStyle.DropDownList,AccessibleName="Windows 局域网地址" };
            foreach(var ni in NetworkInterface.GetAllNetworkInterfaces()) if(ni.OperationalStatus==OperationalStatus.Up) foreach(var addr in ni.GetIPProperties().UnicastAddresses) if(addr.Address.AddressFamily==AddressFamily.InterNetwork && PrivateIP(addr.Address.ToString()) && !ip.Items.Contains(addr.Address.ToString())) ip.Items.Add(addr.Address.ToString());
            if(ip.Items.Contains(current.ListenIP)) ip.SelectedItem=current.ListenIP; else if(ip.Items.Count>0) ip.SelectedIndex=0;
            var label=new Label { Text="允许连接的 Mac 局域网 IPv4 地址",Left=20,Top=90,Width=520 };
            var mac=new TextBox { Left=20,Top=115,Width=520,Text=current.MacIP??"",AccessibleName="允许连接的 Mac 局域网 IPv4 地址" };
            var note=new Label { Left=20,Top=155,Width=520,Height=35,Text="USB 自动切换也需要此配对。保存后重新打开 Windows 程序。",ForeColor=Color.DimGray };
            var cancel=new Button { Text="取消",Left=310,Top=205,Width=105,DialogResult=DialogResult.Cancel };
            var save=new Button { Text="保存配对",Left=425,Top=205,Width=115 };
            save.Click+=delegate {
                if(ip.SelectedItem==null || !PrivateIP(mac.Text.Trim())) { MessageBox.Show("请选择 Windows 地址并填写正确的 Mac 局域网 IPv4。");return; }
                if(current.NetworkEnabled && MessageBox.Show(form,"保存将生成新密钥，现有 Mac 配对会失效且无法撤销。请在重新打开 Windows 程序后，用新配对码重新配对 Mac。","替换现有配对？",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)!=DialogResult.Yes) return;
                current.ListenIP=(string)ip.SelectedItem;current.MacIP=mac.Text.Trim();current.Key=new byte[32];using(var rng=RandomNumberGenerator.Create()) rng.GetBytes(current.Key);
                current.ProtectedKey="";current.NetworkEnabled=true;Save(current);form.DialogResult=DialogResult.OK;form.Close();
            };
            form.Controls.AddRange(new Control[]{ipLabel,ip,label,mac,note,cancel,save});form.AcceptButton=save;form.CancelButton=cancel;
            return form.ShowDialog()==DialogResult.OK;
        }
    }
}
