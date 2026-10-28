import SwiftUI
import AppKit
import DisplayCore

private let accent=AppPalette.accent
struct Dashboard: View {
    @ObservedObject var store: DisplayStore
    @AppStorage("appearance.showDockIcon") private var showDockIcon=true
    @AppStorage("appearance.mode") private var appearanceMode="light"
    @AppStorage("host.layoutMode") private var hostLayout=HostLayoutMode.keep.rawValue
    @State private var settingsCategory=0
    @ObservedObject var navigation:AppNavigation
    @State private var sceneName=""
    @State private var sceneToDelete:DisplayScene?
    @State private var confirmingSceneDelete=false
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:32) {
                HStack(spacing:10) {
                    BrandMark().frame(width:32,height:32).accessibilityHidden(true)
                    Text("屏幕管家").font(.system(size:18,weight:.bold))
                }.padding(.top,14)
                VStack(spacing:7) {
                    nav("显示器",icon:"rectangle.on.rectangle",tag:0)
                    nav("预设",icon:"square.stack.3d.up",tag:1)
                    nav("主机切换",icon:"arrow.left.arrow.right",tag:2)
                    nav("设置与诊断",icon:"slider.horizontal.3",tag:3)
                }
                Spacer()
                Divider()
                VStack(alignment:.leading,spacing:8) {
                    Button { store.restoreAll() } label: { Label("恢复所有屏幕",systemImage:"arrow.counterclockwise") }
                        .buttonStyle(.plain).foregroundStyle(accent)
                        .help("恢复软件黑屏、调暗和已停止的输出")
                    if store.recoveryShortcutAvailable {
                        Text("⌃⌥⌘ R").font(.caption.monospaced()).foregroundStyle(.secondary)
                            .accessibilityLabel("恢复快捷键 Control Option Command R")
                    }
                }
            }.padding(22).frame(width:210).background(AppPalette.sidebar)
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:7) {
                        Text(navigation.tab==0 ? "显示器" : navigation.tab==1 ? "预设" : navigation.tab==2 ? "主机切换" : "设置与诊断").font(.system(size:28,weight:.bold))
                        Text(store.banner).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    if store.scanning { ProgressView().controlSize(.small) }
                    if navigation.tab==0 {
                        Button { store.identify() } label: { Label("识别屏幕",systemImage:"number.square") }.disabled(store.displays.isEmpty)
                        Button { Task { await store.refresh() } } label: { Image(systemName:"arrow.clockwise") }
                            .accessibilityLabel("重新检测显示器").help("重新检测显示器").disabled(store.scanning)
                    }
                }.padding(.horizontal,28).padding(.top,30).padding(.bottom,22)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        if navigation.tab==0 { overview }
                        else if navigation.tab==1 { OutputPresetPanel(store:store); DisclosureGroup("亮度与黑屏场景") { sceneContent.padding(.top,14) } }
                        else if navigation.tab==2 { hostContent }
                        else { settings }
                    }.padding(.horizontal,28).padding(.bottom,28)
                }
            }.background(AppPalette.canvas)
        }.frame(minWidth:920,minHeight:640).preferredColorScheme(appearanceMode == "system" ? nil : appearanceMode == "dark" ? .dark : .light).tint(accent)
        .alert("删除场景？",isPresented:$confirmingSceneDelete,presenting:sceneToDelete) { scene in
            Button("删除",role:.destructive) { store.deleteScene(scene.id) }
            Button("取消",role:.cancel) { }
        } message: { scene in
            Text("“\(scene.name)”将永久删除，无法撤销。当前屏幕状态不会改变。")
        }
    }
    private func nav(_ name:String,icon:String,tag:Int) -> some View {
        Button { navigation.tab=tag } label: {
            HStack(spacing:10) { Image(systemName:icon).frame(width:20); Text(name).lineLimit(1); Spacer() }
                .font(.system(size:13,weight:navigation.tab==tag ? .semibold : .regular)).padding(12)
                .foregroundStyle(navigation.tab==tag ? accent : .secondary)
                .background(navigation.tab==tag ? accent.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:10))
        }.buttonStyle(.plain).accessibilityAddTraits(navigation.tab==tag ? .isSelected : [])
    }
    private var overview: some View {
        Group {
            if store.displays.isEmpty {
                if store.scanning {
                    ProgressView("正在查找显示器…").frame(maxWidth:.infinity,minHeight:180)
                } else {
                    ContentUnavailableView("没有检测到显示器",systemImage:"display",description:Text("检查连接后重新检测。"))
                }
            } else {
                VStack(alignment:.leading,spacing:12) {
                    HStack {
                        Text("屏幕布局").font(.headline)
                        Spacer()
                        Button {
                            settingsCategory=0;navigation.tab=3
                        } label: {
                            Label(store.outputRecovery.automaticallyRestores ? "停止输出 · 15 秒后恢复" : "停止输出 · 手动恢复",systemImage:"timer")
                        }.buttonStyle(.bordered).help("更改停止输出后的恢复方式")
                        Button("仅用内置屏") { Task { await store.onlyBuiltIn() } }
                            .buttonStyle(.bordered)
                            .disabled(store.scanning || store.connectionBusy || store.hostSwitchBusy || store.connectionRecoveryFailed || !store.displays.contains { $0.builtIn && !$0.isDisconnected })
                            .help("停止外接显示器的 Mac 输出；桌面可能重新排列")
                    }
                    LayoutMap(displays:store.displays.filter { !$0.isDisconnected })
                }.padding(18).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:16))
                UniformRowsLayout() {
                    ForEach(store.displays) { display in DisplayCard(display:display,store:store) }
                }
            }
        }
    }
    private var outputControls:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("停止输出后",systemImage:"timer").font(.headline)
                InfoTip(title:"恢复方式",message:"更改会应用于当前已停止输出的屏幕。手动恢复可使用左侧按钮或快捷键；退出应用时仍会尝试恢复。")
                Spacer()
                RecoveryPicker(mode:Binding(get:{store.outputRecovery},set:{store.updateStoppedRecovery($0)})).disabled(store.connectionBusy || store.hostSwitchBusy)
            }
            if !store.connectionUUIDs.isEmpty {
                HStack { Text("\(store.connectionUUIDs.count) 块已停止 · \(store.connectionPreview ? "倒计时恢复中" : "保持关闭")").font(.callout);Spacer();Button("立即恢复") { store.requestConnectionRestore() } }
            }
        }.padding(18).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
    }
    private var hostContent:some View {
        VStack(alignment:.leading,spacing:22) {
            let shared=store.displays.filter { !store.verifiedInputs(for:$0).isEmpty }
            settingBlock("共享显示器",icon:"arrow.left.arrow.right") {
                if shared.isEmpty {
                    Text("尚未配置共享显示器").foregroundStyle(.secondary)
                    Button("查看显示器配置指南…") {
                        NSWorkspace.shared.open(URL(string:"https://github.com/QiushanHuang/ScreenPilot/blob/main/docs/hardware-setup.md")!)
                    }
                }
                ForEach(shared) { d in
                    VStack(alignment:.leading,spacing:8) {
                        HStack {
                            VStack(alignment:.leading,spacing:4) {
                                Text(d.title).font(.headline)
                                Text(hostLayout==HostLayoutMode.disconnect.rawValue ? "切到 Windows 时移出 Mac 桌面" : "切到 Windows 时保持 Mac 布局")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if d.busy { ProgressView().controlSize(.small) }
                            Button("切到 Windows") { Task { await store.switchToWindows(d,mode:HostLayoutMode(rawValue:hostLayout) ?? .keep) } }
                                .accessibilityLabel("将 \(d.title) 切到 Windows")
                                .disabled(store.hostSwitchBusy || store.connectionBusy || store.scanning || d.isDisconnected || d.busy)
                            Button("切回 Mac") { Task { await store.switchToMac(d) } }
                                .accessibilityLabel("将 \(d.title) 切回 Mac")
                                .disabled(store.hostSwitchBusy || store.connectionBusy || !store.windowsBridge.paired || store.windowsBridge.paused)
                        }
                        if let error=d.error {
                            Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        } else if d.note.contains("命令") || d.note.contains("发送") || d.note.contains("等待显示布局") {
                            Text(d.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            settingBlock("USB 与配对",icon:"keyboard") {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text(store.inputAutomation.enabled ? "USB 自动切换已开启" : "USB 自动切换已关闭")
                        Text(store.windowsBridge.paused ? "局域网联动已暂停" : store.windowsBridge.paired ? store.windowsBridge.status : "尚未配对 Windows")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("配置 USB 与配对…") { settingsCategory=1;navigation.tab=3 }
                }
            }
        }
    }
    private var sceneContent: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.bottom,spacing:12) {
                VStack(alignment:.leading,spacing:6) {
                    HStack {
                        Text("场景名称").font(.callout.weight(.medium))
                        InfoTip(title:"亮度与黑屏场景",message:"场景保存当前亮度和黑屏状态，不切换输入源或控制显示器休眠。")
                    }
                    TextField("例如：夜间阅读",text:$sceneName).textFieldStyle(.roundedBorder).accessibilityLabel("场景名称")
                }.frame(maxWidth:360)
                Button("保存当前状态") { store.saveScene(name:sceneName); sceneName="" }
                    .buttonStyle(.borderedProminent).disabled(sceneName.trimmingCharacters(in:.whitespaces).isEmpty || store.scanning || store.displays.isEmpty)
            }
            if store.scenes.isEmpty {
                ContentUnavailableView("还没有场景",systemImage:"square.stack.3d.up")
            }
            ForEach(store.scenes) { scene in
                HStack {
                    Image(systemName:"rectangle.3.group").font(.title2).foregroundStyle(accent).frame(width:42)
                    VStack(alignment:.leading,spacing:5) { Text(scene.name).font(.headline); Text("\(scene.entries.count) 块屏幕 · 亮度与黑屏").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("应用") { store.apply(scene) }.accessibilityLabel("应用场景 \(scene.name)").disabled(store.scanning)
                    Button { sceneToDelete=scene;confirmingSceneDelete=true } label: { Image(systemName:"trash") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .accessibilityLabel("删除场景 \(scene.name)").help("删除场景")
                }.padding(20).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
            }
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:22) {
            Picker("设置分类",selection:$settingsCategory) {
                Text("通用").tag(0);Text("USB 与配对").tag(1);Text("诊断").tag(2)
            }.labelsHidden().pickerStyle(.segmented)
            if settingsCategory==0 {
                settingBlock("外观",icon:"circle.lefthalf.filled") {
                    Picker("应用外观",selection:$appearanceMode) {
                        Text("浅色").tag("light");Text("深色").tag("dark");Text("跟随系统").tag("system")
                    }.labelsHidden().pickerStyle(.segmented).frame(maxWidth:420)
                }
                settingBlock("Dock 与窗口",icon:"dock.rectangle") {
                    Toggle("在 Dock 中显示应用",isOn:$showDockIcon)
                        .help("关闭后仍可从菜单栏打开；⌘H 隐藏窗口，不退出屏幕控制")
                }
                settingBlock("主机切换与布局",icon:"rectangle.3.group") {
                    HStack {
                        Text("手动切到 Windows 时")
                        InfoTip(title:"主机切换与布局",message:"USB 自动切换始终保持 Mac 布局。移出桌面可能重新排列窗口，切回前需要重连；兼容性取决于设备。")
                        Spacer()
                        Picker("手动切到 Windows 时",selection:$hostLayout) {
                            Text("保持 Mac 布局").tag(HostLayoutMode.keep.rawValue)
                            Text("移出 Mac 桌面").tag(HostLayoutMode.disconnect.rawValue)
                        }.labelsHidden().pickerStyle(.segmented).frame(maxWidth:320)
                    }
                }
                outputControls
                settingBlock("恢复与系统",icon:"arrow.counterclockwise") {
                    HStack {
                        Button("系统显示器设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
                        Button("让所有显示器休眠…") { confirmSystemSleep() }
                    }
                }
            } else if settingsCategory==1 {
                USBSettingsPanel(automation:store.inputAutomation)
                WindowsBridgePanel(bridge:store.windowsBridge)
            } else {
                NetworkDiagnosticsPanel(bridge:store.windowsBridge)
                ForEach(store.displays) { display in DiagnosticRow(display:display) }
                settingBlock("关于硬件控制",icon:"info.circle") {
                    Text("外屏需开启 DDC/CI；控制能力取决于显示器、线缆与扩展坞。")
                    Text("ScreenPilot \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · m1ddc（MIT）")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    private func settingBlock<Content:View>(_ title:String,icon:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12) { Label(title,systemImage:icon).font(.headline); content().font(.callout).fixedSize(horizontal:false,vertical:true) }
            .frame(maxWidth:.infinity,alignment:.leading).padding(20).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
    }
    private func confirmSystemSleep() {
        let alert=NSAlert(); alert.messageText="让所有显示器休眠？"; alert.informativeText="Mac 会继续运行。移动鼠标或按键可以唤醒屏幕。"; alert.addButton(withTitle:"全部休眠"); alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let result = try await Task.detached {
                    try ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/pmset"),arguments:["displaysleepnow"])
                }.value
                store.banner = result.code == 0 && !result.timedOut ? "已请求系统显示器休眠" : "系统显示器休眠请求失败"
            } catch { store.banner = "系统休眠请求失败：" + error.localizedDescription }
        }
    }
}
struct LayoutMap: View {
    let displays: [DisplayModel]
    var body: some View {
        GeometryReader { geo in
            let union=displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            let scale=min((geo.size.width-30)/max(union.width,1),(geo.size.height-10)/max(union.height,1))
            ForEach(displays) { d in
                let w=max(24,d.frame.width*scale), h=max(22,d.frame.height*scale)
                ZStack {
                    RoundedRectangle(cornerRadius:7).fill(d.isMain ? accent.opacity(0.15) : AppPalette.sidebar)
                    RoundedRectangle(cornerRadius:7).strokeBorder(d.isMain ? accent.opacity(0.7) : AppPalette.border,lineWidth:1)
                    VStack(spacing:3) { Text("\(d.number)").font(.system(size:18,weight:.semibold,design:.rounded)); if h>52 { Text(d.isMain ? "主屏" : d.builtIn ? "内置" : d.systemName).font(.system(size:9)).lineLimit(1) } }.foregroundStyle(d.isMain ? accent : Color.primary)
                }.frame(width:w-4,height:h-4).position(x:(geo.size.width-union.width*scale)/2+(d.frame.midX-union.minX)*scale,y:(geo.size.height-union.height*scale)/2+(union.maxY-d.frame.midY)*scale)
            }
        }.frame(height:100).accessibilityElement(children:.ignore)
            .accessibilityLabel("显示器空间布局")
            .accessibilityValue(displays.map { "屏幕 \($0.number)，\($0.title)" + ($0.isMain ? "，主屏" : "") }.joined(separator:"；"))
    }
}
struct DisplayCard: View {
    @ObservedObject var display: DisplayModel
    @ObservedObject var store: DisplayStore
    @State private var rename=false
    @State private var nameDraft=""
    @AppStorage("host.layoutMode") private var layoutModeRaw=HostLayoutMode.keep.rawValue
    private var status:String? {
        if display.isDisconnected { return store.connectionPreview ? "已停止输出 · 15 秒后恢复" : "已停止输出 · 手动恢复" }
        if display.shade.blackedOut { return display.preview ? "黑屏预览 · 12 秒后恢复" : "已黑屏 · 点击屏幕可恢复" }
        if display.probing { return "正在检测控制能力…" }
        if display.busy { return "正在发送命令…" }
        if display.note.contains("命令") || display.note.contains("发送") || display.note.contains("等待显示布局") { return display.note }
        return nil
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:12) {
                ZStack { RoundedRectangle(cornerRadius:10).fill(accent.opacity(0.08)).frame(width:43,height:43); Text("\(display.number)").font(.system(size:21,weight:.semibold,design:.rounded)).foregroundStyle(accent) }
                    .accessibilityLabel("屏幕 \(display.number)")
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text(display.title).font(.system(size:16,weight:.semibold)).lineLimit(1).help(display.title); if display.isMain { Text("主屏").font(.caption2.weight(.medium)).padding(.horizontal,6).padding(.vertical,2).background(accent.opacity(0.12),in:Capsule()).foregroundStyle(accent) } }
                    Text(display.detail).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Button { nameDraft=display.alias;rename=true } label: { Image(systemName:"pencil").frame(width:24,height:24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("重命名屏幕 \(display.title)").help("重命名屏幕")
            }
            if let status {
                HStack(spacing:8) {
                    if display.probing || display.busy { ProgressView().controlSize(.mini) }
                    else { Image(systemName:display.isDisconnected || display.shade.blackedOut ? "pause.circle" : "info.circle") }
                    Text(status).fixedSize(horizontal:false,vertical:true)
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(display.mode == .hardware ? "背光亮度" : "软件亮度").font(.callout.weight(.medium))
                if display.mode == .software {
                    InfoTip(title:"软件亮度",message:"软件调暗只改变画面，不降低显示器背光功耗。硬件亮度需显示器和连接方式支持。")
                }
                Spacer()
                Text("\(Int(display.brightness.rounded()))%").font(.system(size:21,weight:.medium,design:.rounded)).monospacedDigit()
            }
            HStack(spacing:10) {
                Image(systemName:"sun.min").foregroundStyle(.secondary)
                Slider(value:Binding(get:{display.brightness},set:{store.setBrightness($0,for:display)}),in:5...100)
                    .accessibilityLabel("\(display.title)亮度")
                    .accessibilityValue("\(Int(display.brightness.rounded()))%")
                    .disabled(display.probing || display.shade.blackedOut || display.isDisconnected)
                Image(systemName:"sun.max.fill").foregroundStyle(accent)
            }.font(.system(size:12))
            if display.hardwareAvailable {
                Picker("\(display.title)亮度方式",selection:Binding(get:{display.mode},set:{store.selectMode($0,for:display)})) { Text("背光").tag(BrightnessMode.hardware); Text("软件").tag(BrightnessMode.software) }
                    .labelsHidden().pickerStyle(.segmented).frame(width:140)
                    .disabled(display.busy || display.probing || display.isDisconnected)
            }
            Spacer(minLength:0)
            Divider().opacity(0.5)
            HStack(spacing:10) {
                Button { store.blackout(display) } label: {
                    Label(display.shade.blackedOut ? "恢复画面" : "黑屏",systemImage:display.shade.blackedOut ? "sun.max" : "moon")
                }.accessibilityLabel("\(display.shade.blackedOut ? "恢复画面" : "黑屏")：\(display.title)")
                    .help("黑屏保留桌面布局；12 秒后自动恢复，也可点击黑屏恢复")
                    .disabled(display.isDisconnected)
                Spacer(minLength:0)
                if store.supportsDisconnect(display) {
                    if display.isDisconnected {
                        Button("恢复输出") { Task { _=await store.restoreDisconnected(display) } }
                            .accessibilityLabel("恢复 \(display.title) 的输出").disabled(store.connectionBusy)
                    } else {
                        Button("停止输出") { Task { await store.disconnect(display) } }
                            .accessibilityLabel("停止 \(display.title) 的输出")
                            .help("停止 Mac 输出可能重新排列桌面；\(store.outputRecovery.automaticallyRestores ? "15 秒后自动恢复" : "需手动恢复")")
                            .disabled(store.scanning || store.connectionBusy || store.hostSwitchBusy || store.connectionRecoveryFailed || store.liveKeys.count<=1)
                    }
                }
            }.buttonStyle(.bordered).controlSize(.large)
            if display.preview || (display.isDisconnected && store.connectionPreview) || display.powerSupported || (display.inputSupported && store.verifiedInputs(for:display).isEmpty) {
              HStack {
                if display.preview { Button("保持黑屏") { store.keepBlackout(display) } }
                if display.isDisconnected && store.connectionPreview { Button("不自动恢复") { store.keepDisconnected() }.font(.caption) }
                Spacer()
                if display.powerSupported || (display.inputSupported && store.verifiedInputs(for:display).isEmpty) {
                    Menu("更多") {
                        if display.powerSupported { Button("休眠此屏幕…") { confirm("power",value:4) };Button("尝试唤醒") { Task { await store.send("power",value:1,to:display) } } }
                        if display.inputSupported { ForEach([17,18,15,16,27],id:\.self) { value in Button(inputName(value)+"…") { confirm("input",value:value) } } }
                    }.fixedSize().disabled(display.busy || store.scanning).accessibilityLabel("\(display.title)更多操作")
                }
              }
            }
            if !store.verifiedInputs(for:display).isEmpty {
                Divider().opacity(0.5)
                HStack {
                    Text("主机切换").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(layoutModeRaw==HostLayoutMode.disconnect.rawValue ? "移出 Mac 桌面" : "保持 Mac 布局").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing:10) {
                    Button { Task { await store.switchToWindows(display,mode:HostLayoutMode(rawValue:layoutModeRaw) ?? .keep) } } label: {
                        Label("Windows · HDMI 2",systemImage:"desktopcomputer").frame(maxWidth:.infinity)
                    }.accessibilityLabel("将 \(display.title) 切到 Windows HDMI 2")
                        .disabled(display.isDisconnected || display.busy || store.scanning || store.hostSwitchBusy || store.connectionBusy)
                    Button { Task { await store.switchToMac(display) } } label: {
                        Label("Mac · HDMI 1",systemImage:"laptopcomputer").frame(maxWidth:.infinity)
                    }.accessibilityLabel("将 \(display.title) 切回 Mac HDMI 1")
                        .disabled(!store.windowsBridge.paired || store.windowsBridge.paused || store.hostSwitchBusy || store.connectionBusy)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let error=display.error { Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
        }.padding(17).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(AppPalette.surface,in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(AppPalette.border,lineWidth:1))
            .sheet(isPresented:$rename) {
                VStack(alignment:.leading,spacing:18) {
                    Text("重命名屏幕 \(display.number)").font(.title2)
                    Text("屏幕名称").font(.callout.weight(.medium))
                    TextField(display.systemName,text:$nameDraft).textFieldStyle(.roundedBorder).accessibilityLabel("屏幕名称")
                        .help("留空使用系统名称；名称只保存在这台 Mac")
                    HStack {
                        Spacer()
                        Button("取消") { rename=false }.keyboardShortcut(.cancelAction)
                        Button("保存") { display.alias=nameDraft;display.saveName();rename=false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    }
                }.padding(28).frame(width:380)
            }
    }
    private func confirm(_ feature:String,value:Int) {
        let alert=NSAlert()
        alert.messageText=feature=="input" ? "将「\(display.title)」切换到 \(inputName(value))？" : "让「\(display.title)」休眠？"
        alert.informativeText=feature=="input" ? "切换后 Mac 可能失去这块屏幕的控制通道。目标接口需已连接信号；必要时用显示器按键切回。" : "这会发送硬件电源命令。部分显示器需要实体按键唤醒，软件恢复黑屏不能唤醒硬件。"
        alert.addButton(withTitle:feature=="input" ? "切换输入" : "休眠此屏幕"); alert.addButton(withTitle:"取消")
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.send(feature,value:value,to:display) } }
    }
}
struct DiagnosticRow: View {
    @ObservedObject var display: DisplayModel
    var body: some View {
        DisclosureGroup("\(display.number) · \(display.title)") {
            VStack(alignment:.leading,spacing:8) {
                Text(display.probeDetail.isEmpty ? display.note : display.probeDetail)
                Text("UUID：\(display.key.uuid)\n连接位置：\(display.key.location)").font(.system(size:10,design:.monospaced)).textSelection(.enabled)
            }.font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)
        }.padding(16).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:12))
    }
}
