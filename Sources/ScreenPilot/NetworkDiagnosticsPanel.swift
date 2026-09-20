import SwiftUI
import AppKit
import DisplayCore
struct NetworkDiagnosticsPanel:View {
    @ObservedObject var bridge:WindowsBridgeControl
    @State private var running=false
    @State private var result=""
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Label("局域网与网络诊断",systemImage:"network").font(.headline);Spacer();Toggle("暂停联动",isOn:$bridge.paused).toggleStyle(.switch).fixedSize() }
            Text(bridge.paused ? "已停止新的联动请求；显示器亮度、黑屏和停止输出仍可使用。" : bridge.status).font(.callout).foregroundStyle(.secondary)
            Text("联动只访问配对电脑，不修改 DNS、代理、网关或防火墙。连接失败时自动降低重试频率。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(running ? "检查中…" : "检查此 Mac 网络") { run() }.disabled(running)
                if !result.isEmpty { Button("导出结果…") { export() } }
                Spacer()
                Text("只读检查，不切换显示器").font(.caption).foregroundStyle(.secondary)
            }
            if !result.isEmpty { DisclosureGroup("查看诊断结果") { Text(result).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) } }
        }.padding(20).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
    }
    func run() {
        running=true
        Task {
            let text=await Task.detached { () -> String in
                var sections=["ScreenPilot network diagnostics \(Date())"]
                let commands:[(String,String,[String])]=[
                    ("Network","/usr/sbin/scutil",["--nwi"]),
                    ("Default route","/sbin/route",["-n","get","default"]),
                    ("Direct HTTPS","/usr/bin/curl",["--noproxy","*","-I","--connect-timeout","4","--max-time","7","https://www.apple.com"])
                ]
                for (name,path,args) in commands {
                    do { let response=try ProcessRunner.run(executable:URL(fileURLWithPath:path),arguments:args,timeout:8);sections.append("\n[\(name)] exit=\(response.code) timeout=\(response.timedOut)\n"+String(decoding:response.output,as:UTF8.self)) }
                    catch { sections.append(name+": "+error.localizedDescription) }
                }
                return sections.joined(separator:"\n")
            }.value
            result=text;running=false
        }
    }
    func export() {
        let panel=NSSavePanel();panel.nameFieldStringValue="ScreenPilot-Mac-network.txt"
        if panel.runModal() == .OK,let url=panel.url { do { try result.write(to:url,atomically:true,encoding:.utf8) } catch { result += "\n导出失败："+error.localizedDescription } }
    }
}
