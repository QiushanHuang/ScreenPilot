import SwiftUI
import AppKit

struct WindowsBridgePanel:View {
    @ObservedObject var bridge:WindowsBridgeControl
    @State private var code=""
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Mac 一键切回 · Windows 配对",systemImage:"desktopcomputer").font(.headline)
            Text("Windows 程序首次选定小米显示器后，把它显示的 SP1 配对码粘贴到这里。之后只需在 Mac 点击切回。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            SecureField("SP1|Windows地址|端口|配对密钥",text:$code).textFieldStyle(.roundedBorder)
            HStack {
                Button("保存配对") { bridge.save(code:code); code="" }.disabled(code.isEmpty || bridge.busy)
                Button("测试连接") { Task { await bridge.check() } }.disabled(!bridge.paired || bridge.busy)
                Button("导出 Windows 工具包…") { exportPackage() }
                if bridge.busy { ProgressView().controlSize(.small) }
            }
            if bridge.paired { Text("已配置 Windows：\(bridge.host):\(bridge.port)").font(.caption).foregroundStyle(.secondary) }
            Text(bridge.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("密钥保存在 Mac 钥匙串。Windows 程序支持单独启用开机启动；两台电脑需在同一局域网。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
    }
    private func exportPackage() {
        guard let source=Bundle.main.resourceURL?.appendingPathComponent("WindowsBridge.zip"),FileManager.default.fileExists(atPath:source.path) else { bridge.status="当前构建未包含 Windows 工具包"; return }
        let panel=NSSavePanel(); panel.nameFieldStringValue="ScreenPilot-WindowsBridge.zip"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try Data(contentsOf:source).write(to:url,options:.atomic); bridge.status="工具包已导出，请在 Windows 解压并打开 ScreenPilotBridge.exe" }
        catch { bridge.status="导出失败："+error.localizedDescription }
    }
}
