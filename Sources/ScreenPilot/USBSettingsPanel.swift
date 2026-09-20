import SwiftUI
import DisplayCore

struct USBSettingsPanel:View {
    @ObservedObject var automation:InputAutomation
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("USB 接入自动切换 · 局域网联动",systemImage:"keyboard").font(.headline)
            Text("键鼠接入 Mac：请 Windows 切到 HDMI 1；接入 Windows：请 Mac 切到 HDMI 2。两端需开启自动切换并完成局域网配对。拔出和启动不切屏。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            picker("共享键盘接口",keyboard:true,selection:$automation.keyboardID)
            picker("共享鼠标接口",keyboard:false,selection:$automation.mouseID)
            Picker("触发条件",selection:$automation.modeRaw) {
                Text("键盘接入").tag("keyboard"); Text("鼠标接入").tag("mouse")
                Text("任一接入").tag("either"); Text("两者都接入").tag("both")
            }.onChange(of:automation.modeRaw) { _ in automation.configure() }
            Toggle("启用 USB 局域网自动切换",isOn:$automation.enabled).disabled(!automation.inventory.watching || (!automation.canEnable && !automation.enabled)).onChange(of:automation.enabled) { _ in automation.configure() }
            Text(automation.inventory.watching ? automation.status : "未能注册设备接入通知，自动切换不可用").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("设备识别说明") {
                Text("只读取设备连接，不读取按键内容。同名接收器按接口位置区分；可先关闭自动切换，再按 USB 转换器观察哪些接口消失和出现。").font(.caption).foregroundStyle(.secondary).padding(.top,6)
            }
            Text("自动切换保持 Mac 布局。网络不可用时暂停切换。").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
    }
    private func picker(_ title:String,keyboard:Bool,selection:Binding<String>)->some View {
        Picker(title,selection:selection) {
            Text("不监控").tag("")
            ForEach(automation.inventory.devices.filter { $0.keyboard==keyboard }) { device in Text(device.label).tag(device.id) }
            if !selection.wrappedValue.isEmpty && !automation.inventory.devices.contains(where: { $0.id==selection.wrappedValue }) {
                Text("已选接口当前未连接").tag(selection.wrappedValue)
            }
        }.onChange(of:selection.wrappedValue) { _ in automation.configure() }
    }
}
