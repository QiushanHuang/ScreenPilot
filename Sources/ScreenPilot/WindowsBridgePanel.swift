import SwiftUI
import AppKit
import DisplayCore

struct WindowsBridgePanel:View {
    @ObservedObject var bridge:WindowsBridgeControl
    @State private var code=""
    @State private var confirmingReplacement=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label("Windows 配对",systemImage:"desktopcomputer").font(.headline)
                InfoTip(title:"Windows 配对",message:"在 Windows 工具中配置网络配对并复制 SP1 配对码。密钥保存在 Mac 钥匙串；请勿分享配对码。")
            }
            VStack(alignment:.leading,spacing:6) {
                Text("配对码").font(.callout.weight(.medium))
                SecureField("粘贴 Windows 的 SP1 配对码",text:$code).textFieldStyle(.roundedBorder).accessibilityLabel("Windows 配对码")
            }
            HStack {
                Button("保存配对") {
                    if bridge.paired {
                        do { _=try BridgePairing(code:code);confirmingReplacement=true }
                        catch { bridge.status=error.localizedDescription }
                    } else { savePairing() }
                }.buttonStyle(.borderedProminent).disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || bridge.busy)
                Button("测试连接") { Task { await bridge.check() } }.disabled(!bridge.paired || bridge.paused || bridge.busy)
                Button("导出 Windows 工具包…") { exportPackage() }
                if bridge.busy { ProgressView().controlSize(.small) }
            }
            if bridge.paired { Text("已配置 Windows：\(bridge.host):\(bridge.port)").font(.caption).foregroundStyle(.secondary) }
            Text(bridge.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
        .alert("替换 Windows 配对？",isPresented:$confirmingReplacement) {
            Button("替换配对",role:.destructive) { savePairing() }
            Button("取消",role:.cancel) { }
        } message: {
            Text("当前保存的配对密钥将被替换，无法撤销。替换后请测试连接。")
        }
    }
    private func savePairing() { if bridge.save(code:code) { code="" } }
    private func exportPackage() {
        guard let source=Bundle.main.resourceURL?.appendingPathComponent("WindowsBridge.zip"),FileManager.default.fileExists(atPath:source.path) else { bridge.status="当前构建未包含 Windows 工具包"; return }
        let panel=NSSavePanel(); panel.nameFieldStringValue="ScreenPilot-WindowsBridge.zip"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try Data(contentsOf:source).write(to:url,options:.atomic); bridge.status="工具包已导出，请在 Windows 解压并打开 ScreenPilotBridge.exe" }
        catch { bridge.status="导出失败："+error.localizedDescription }
    }
}
