using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

public static partial class ScreenPilotBridge {
    static string ProductVersion {
        get { var version=Assembly.GetExecutingAssembly().GetName().Version;return version.Major+"."+version.Minor+"."+version.Build; }
    }
    static string ThirdPartyNotices() {
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("ScreenPilot.ThirdPartyNotices.txt")) {
            if(stream==null) return "许可信息未包含在此构建中。";
            using(var reader=new StreamReader(stream)) return reader.ReadToEnd();
        }
    }
    static void PopulateAbout(FlowLayoutPanel panel) {
        panel.Controls.Add(new Label { Text="屏幕管家 · ScreenPilot",AutoSize=true,Font=new Font("Segoe UI",18,FontStyle.Bold),Margin=new Padding(0,0,0,12) });
        panel.Controls.Add(new Label { Text="Windows 版  "+ProductVersion,AutoSize=true });
        panel.Controls.Add(new Label { Text="共享显示器输入切换 · USB 接入联动 · 局域网配对",AutoSize=true,MaximumSize=new Size(580,0),Margin=new Padding(0,12,0,12) });
        panel.Controls.Add(new Label { Text="开发与版权：QiushanHuang\n© 2026 QiushanHuang",AutoSize=true,Margin=new Padding(0,0,0,8) });
        var link=new LinkLabel { Text="github.com/QiushanHuang",AutoSize=true,LinkColor=Color.FromArgb(13,110,87),Margin=new Padding(0,0,0,18) };
        link.LinkClicked+=delegate {
            try { Process.Start(new ProcessStartInfo("https://github.com/QiushanHuang") { UseShellExecute=true }); }
            catch { MessageBox.Show("无法打开浏览器。请访问 https://github.com/QiushanHuang", "屏幕管家",MessageBoxButtons.OK,MessageBoxIcon.Information); }
        };
        panel.Controls.Add(link);
        panel.Controls.Add(new Label { Text="第三方说明与许可",AutoSize=true,Font=new Font("Segoe UI",11,FontStyle.Bold) });
        panel.Controls.Add(new TextBox { Text=ThirdPartyNotices(),Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,Width=580,Height=180,BorderStyle=BorderStyle.FixedSingle,BackColor=Color.White,WordWrap=true });
        panel.Controls.Add(new Label { Text="配对密钥保存在当前用户配置中。关于页面不会发送显示器命令。",AutoSize=true,MaximumSize=new Size(580,0),ForeColor=Color.DimGray,Margin=new Padding(0,12,0,0) });
    }
    static void ShowAbout(IWin32Window owner) {
        using(var icon=BrandIcon())
        using(var form=new Form { Text="关于屏幕管家",Icon=icon,ClientSize=new Size(650,560),MinimumSize=new Size(650,560),StartPosition=FormStartPosition.CenterParent,Font=new Font("Segoe UI",10),MinimizeBox=false,ShowInTaskbar=false,BackColor=Color.White,AutoScaleMode=AutoScaleMode.Dpi }) {
            var panel=new FlowLayoutPanel { Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(24) };
            PopulateAbout(panel);
            var close=new Button { Text="关闭",Dock=DockStyle.Bottom,Height=38,DialogResult=DialogResult.Cancel };
            form.Controls.Add(panel);form.Controls.Add(close);form.CancelButton=close;form.ShowDialog(owner);
        }
    }
}
