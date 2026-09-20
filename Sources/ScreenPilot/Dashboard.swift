import SwiftUI
import AppKit
import DisplayCore

private let accent=AppPalette.accent
struct Dashboard: View {
    @ObservedObject var store: DisplayStore
    @AppStorage("appearance.mode") private var appearanceMode="light"
    @AppStorage("host.layoutMode") private var hostLayout=HostLayoutMode.keep.rawValue
    @State private var settingsCategory=0
    @ObservedObject var navigation:AppNavigation
    @State private var sceneName=""
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:28) {
                HStack(spacing:10) {
                    BrandMark().frame(width:36,height:36)
                    VStack(alignment:.leading,spacing:2) { Text("屏幕管家").font(.system(size:19,weight:.bold)); Text("SCREEN PILOT").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(2).foregroundStyle(.secondary) }
                }.padding(.top,14)
                VStack(spacing:7) {
                    nav("显示器",icon:"rectangle.on.rectangle",tag:0)
                    nav("预设",icon:"square.stack.3d.up",tag:1)
                    nav("主机切换",icon:"arrow.left.arrow.right",tag:2)
                    nav("设置与诊断",icon:"slider.horizontal.3",tag:3)
                }
                Spacer()
                VStack(alignment:.leading,spacing:10) {
                    Label("\(store.displays.filter { !$0.isDisconnected }.count) 块屏幕在线",systemImage:"circle.fill").font(.system(size:11)).foregroundStyle(accent)
                    Text("显示器控制中心\n亮度 · 输出 · 主机").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5)
                }
                Divider()
                Button { store.restoreAll() } label: { Label("恢复所有屏幕",systemImage:"sun.max") }.buttonStyle(.plain).foregroundStyle(accent)
                Text("⌃⌥⌘ R  紧急恢复").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
            }.padding(22).frame(width:220).background(AppPalette.sidebar)
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:7) {
                        Text(navigation.tab==0 ? "显示器" : navigation.tab==1 ? "预设" : navigation.tab==2 ? "主机切换" : "设置与诊断").font(.system(size:28,weight:.bold))
                        Text(store.banner).font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.scanning { ProgressView().controlSize(.small) }
                    Button { store.identify() } label: { Label("识别屏幕",systemImage:"number.square") }.disabled(store.displays.isEmpty)
                    Button { Task { await store.refresh() } } label: { Image(systemName:"arrow.clockwise") }.help("重新检测显示器").disabled(store.scanning)
                }.padding(.horizontal,28).padding(.top,30).padding(.bottom,22)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        if navigation.tab==0 { overview }
                        else if navigation.tab==1 { OutputPresetPanel(store:store); DisclosureGroup("亮度与黑屏场景") { sceneContent.padding(.top,14) } }
                        else if navigation.tab==2 { hostContent }
                        else { settings }
                    }.padding(.horizontal,28).padding(.bottom,28)
                }
                HStack {
                    Circle().fill(accent).frame(width:5,height:5)
                    Text("本地控制 · 无需账户").font(.system(size:10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("黑屏保持布局 · 软件调暗不改变背光").font(.system(size:10)).foregroundStyle(.secondary)
                }.padding(.horizontal,28).padding(.vertical,12).background(AppPalette.sidebar)
            }.background(AppPalette.canvas)
        }.frame(minWidth:920,minHeight:640).preferredColorScheme(appearanceMode == "system" ? nil : appearanceMode == "dark" ? .dark : .light).tint(accent)
    }
    private func nav(_ name:String,icon:String,tag:Int) -> some View {
        Button { navigation.tab=tag } label: {
            HStack(spacing:10) { Image(systemName:icon).frame(width:20); Text(name).lineLimit(1); Spacer() }
                .font(.system(size:13,weight:navigation.tab==tag ? .semibold : .regular)).padding(12)
                .foregroundStyle(navigation.tab==tag ? accent : .secondary)
                .background(navigation.tab==tag ? accent.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:10))
        }.buttonStyle(.plain)
    }
    private var overview: some View {
        Group {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("屏幕布局").font(.system(size:12,weight:.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("仅用内置屏") { Task { await store.onlyBuiltIn() } }.buttonStyle(.borderless).disabled(store.scanning || store.connectionBusy || store.hostSwitchBusy)

                }
                LayoutMap(displays:store.displays.filter { !$0.isDisconnected })
            }.padding(18).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:16))
            UniformRowsLayout() {
                ForEach(store.displays) { display in DisplayCard(display:display,store:store) }
            }
        }
    }
    private var outputControls:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("停止输出后的恢复",systemImage:"timer").font(.headline)
                Spacer()
                RecoveryPicker(mode:Binding(get:{store.outputRecovery},set:{store.updateStoppedRecovery($0)})).disabled(store.connectionBusy || store.hostSwitchBusy)
            }
            Text(store.connectionUUIDs.isEmpty ? "设置用于下一次停止输出。关闭倒计时后，可通过左侧恢复按钮或快捷键恢复。" : "更改此选项会应用于当前已停止的屏幕。退出应用或应用异常结束时仍会恢复。").font(.caption).foregroundStyle(.secondary)
            if !store.connectionUUIDs.isEmpty {
                HStack { Text("\(store.connectionUUIDs.count) 块已停止 · \(store.connectionPreview ? "倒计时恢复中" : "保持关闭")").font(.callout);Spacer();Button("立即恢复") { store.requestConnectionRestore() } }
            }
        }.padding(18).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
    }
    private var hostContent:some View {
        VStack(alignment:.leading,spacing:22) {
            settingBlock("跨主机切换",icon:"arrow.left.arrow.right") {
                Text("键鼠接入哪台电脑，就通过局域网请当前主机切换显示器输入。自动切换保持 Mac 桌面布局。")
                ForEach(store.displays.filter { !store.verifiedInputs(for:$0).isEmpty }) { d in
                    HStack {
                        Text(d.title).font(.headline);Spacer()
                        Button("切到 Windows") { Task { await store.switchToWindows(d,mode:HostLayoutMode(rawValue:hostLayout) ?? .keep) } }.disabled(store.hostSwitchBusy || store.scanning || d.isDisconnected)
                        Button("切回 Mac") { Task { await store.switchToMac(d) } }.disabled(store.hostSwitchBusy || store.windowsBridge.paused)
                    }
                }
            }
            settingBlock("自动跟随",icon:"keyboard") {
                Text(store.inputAutomation.enabled ? "USB 自动切换已开启" : "USB 自动切换已关闭")
                Text(store.windowsBridge.paused ? "局域网联动已暂停" : store.windowsBridge.status)
                Button("配置 USB 与配对…") { settingsCategory=1;navigation.tab=3 }
            }
        }
    }
    private var sceneContent: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("保存每块屏幕的亮度和黑屏状态。场景不会切换输入源或让显示器休眠。").foregroundStyle(.secondary).font(.callout)
            HStack {
                TextField("场景名称，例如：夜间阅读",text:$sceneName).textFieldStyle(.roundedBorder).frame(maxWidth:360)
                Button("保存当前状态") { store.saveScene(name:sceneName); sceneName="" }.buttonStyle(.borderedProminent).disabled(sceneName.trimmingCharacters(in:.whitespaces).isEmpty || store.scanning || store.displays.isEmpty)
            }
            if store.scenes.isEmpty {
                ContentUnavailableView("还没有场景",systemImage:"square.stack.3d.up",description:Text("先调整屏幕，再保存你常用的组合。"))
            }
            ForEach(store.scenes) { scene in
                HStack {
                    Image(systemName:"rectangle.3.group").font(.title2).foregroundStyle(accent).frame(width:42)
                    VStack(alignment:.leading,spacing:5) { Text(scene.name).font(.headline); Text("\(scene.entries.count) 块屏幕 · 亮度与黑屏").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("应用") { store.apply(scene) }.disabled(store.scanning)
                    Button { store.deleteScene(scene.id) } label: { Image(systemName:"trash") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("删除场景")
                }.padding(20).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:14))
            }
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:22) {
            Picker("设置分类",selection:$settingsCategory) {
                Text("通用").tag(0);Text("USB 与配对").tag(1);Text("诊断").tag(2)
            }.pickerStyle(.segmented)
            if settingsCategory==0 {
                settingBlock("外观",icon:"circle.lefthalf.filled") {
                    Picker("应用外观",selection:$appearanceMode) {
                        Text("浅色").tag("light");Text("深色").tag("dark");Text("跟随系统").tag("system")
                    }.pickerStyle(.segmented).frame(maxWidth:420)
                }
                settingBlock("主机切换与布局",icon:"rectangle.3.group") {
                    Picker("手动切到 Windows 时",selection:$hostLayout) {
                        Text("保持 Mac 布局").tag(HostLayoutMode.keep.rawValue)
                        Text("移出 Mac 桌面").tag(HostLayoutMode.disconnect.rawValue)
                    }.pickerStyle(.segmented).frame(maxWidth:440)
                    Text("此设置应用于显示器卡片的切换按钮。USB 自动切换保持布局；移出桌面的重连兼容性仍需按设备确认。")
                }
                outputControls
                settingBlock("恢复与系统",icon:"arrow.counterclockwise") {
                    Text("⌃⌥⌘ R：恢复黑屏、调暗和本应用停止的输出。关闭倒计时不影响退出应用时的恢复保护。")
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
                    Text("外屏需开启 DDC/CI。输入切换和背光能力取决于显示器、线缆与扩展坞。软件调暗不等于关闭背光。")
                    Text("ScreenPilot \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 设备发现基于 m1ddc（MIT） · 私有显示接口可能随系统更新改变。")
                }
            }
        }
    }
    private func settingBlock<Content:View>(_ title:String,icon:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12) { Label(title,systemImage:icon).font(.headline); content().font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
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
        }.frame(height:100).accessibilityLabel("显示器空间布局")
    }
}
struct DisplayCard: View {
    @ObservedObject var display: DisplayModel
    @ObservedObject var store: DisplayStore
    @State private var rename=false
    @AppStorage("host.layoutMode") private var layoutModeRaw=HostLayoutMode.keep.rawValue
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                ZStack { RoundedRectangle(cornerRadius:10).fill(accent.opacity(0.08)).frame(width:43,height:43); Text("\(display.number)").font(.system(size:21,weight:.semibold,design:.rounded)).foregroundStyle(accent) }
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text(display.title).font(.system(size:16,weight:.semibold)).lineLimit(1); if display.isMain { Text("主屏").font(.system(size:9,weight:.medium)).padding(.horizontal,5).padding(.vertical,2).background(accent.opacity(0.12),in:Capsule()).foregroundStyle(accent) } }
                    Text(display.detail).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Button { rename=true } label: { Image(systemName:"pencil").font(.system(size:11)) }.buttonStyle(.plain).foregroundStyle(.secondary).help("重命名屏幕")
            }
            HStack(spacing:5) {
                Circle().fill(display.shade.blackedOut ? Color.orange : accent).frame(width:5,height:5)
                Text(display.isDisconnected ? (store.connectionPreview ? "已停止输出 · 15 秒预览" : "已停止输出 · 可恢复布局") : display.shade.blackedOut ? (display.preview ? "黑屏预览 · 12 秒自动恢复" : "已黑屏 · 点击屏幕可恢复") : display.note).font(.system(size:12)).lineLimit(2)
                Spacer()
                if display.probing || display.busy { ProgressView().controlSize(.mini) }
            }.foregroundStyle(.secondary)
            HStack {
                Text(display.mode == .hardware ? "硬件亮度" : "软件亮度").font(.system(size:12))
                Spacer()
                Text("\(Int(display.brightness.rounded()))%").font(.system(size:21,weight:.medium,design:.rounded)).monospacedDigit()
            }
            HStack(spacing:10) {
                Image(systemName:"sun.min").foregroundStyle(.secondary)
                Slider(value:Binding(get:{display.brightness},set:{store.setBrightness($0,for:display)}),in:5...100).disabled(display.probing || display.shade.blackedOut || display.isDisconnected)
                Image(systemName:"sun.max.fill").foregroundStyle(accent)
            }.font(.system(size:12))
            HStack(spacing:7) {
                if display.hardwareAvailable {
                    Picker("亮度方式",selection:Binding(get:{display.mode},set:{store.selectMode($0,for:display)})) { Text("背光").tag(BrightnessMode.hardware); Text("软件").tag(BrightnessMode.software) }.labelsHidden().pickerStyle(.segmented).frame(width:128).disabled(display.busy || display.probing || display.isDisconnected)
                } else { Text("软件调暗不降低背光功耗").font(.system(size:10)).foregroundStyle(.secondary) }
                Spacer()
            }
            Divider().opacity(0.5)
            HStack(spacing:10) {
                Button { store.blackout(display) } label: {
                    Label(display.shade.blackedOut ? "恢复画面" : "黑屏",systemImage:display.shade.blackedOut ? "sun.max" : "moon")
                }.disabled(display.isDisconnected)
                if display.preview { Button("保持黑屏") { store.keepBlackout(display) } }
                Spacer(minLength:0)
                if store.supportsDisconnect(display) {
                    if display.isDisconnected {
                        Button("恢复输出") { Task { _=await store.restoreDisconnected(display) } }.disabled(store.connectionBusy)
                    } else {
                        Button("停止输出") { Task { await store.disconnect(display) } }
                            .disabled(store.scanning || store.connectionBusy || store.hostSwitchBusy || store.connectionRecoveryFailed || store.liveKeys.count<=1)
                    }
                }
            }.buttonStyle(.bordered).controlSize(.large)
            HStack {
                Text(display.isDisconnected ? (store.connectionPreview ? "15 秒预览中" : "保持停止输出") : (store.outputRecovery.automaticallyRestores ? "停止输出后 15 秒恢复" : "停止输出后手动恢复"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if display.isDisconnected && store.connectionPreview { Button("不自动恢复") { store.keepDisconnected() }.font(.caption) }
                if display.powerSupported || (display.inputSupported && store.verifiedInputs(for:display).isEmpty) {
                    Menu("更多") {
                        if display.powerSupported { Button("休眠此屏幕…") { confirm("power",value:4) };Button("尝试唤醒") { Task { await store.send("power",value:1,to:display) } } }
                        if display.inputSupported { ForEach([17,18,15,16,27],id:\.self) { value in Button(inputName(value)+"…") { confirm("input",value:value) } } }
                    }.fixedSize().disabled(display.busy || store.scanning)
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
                    }.disabled(display.isDisconnected || display.busy || store.scanning || store.hostSwitchBusy || store.connectionBusy)
                    Button { Task { await store.switchToMac(display) } } label: {
                        Label("Mac · HDMI 1",systemImage:"laptopcomputer").frame(maxWidth:.infinity)
                    }.disabled(!store.windowsBridge.paired || store.windowsBridge.paused || store.hostSwitchBusy || store.connectionBusy)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let error=display.error { Text(error).font(.system(size:10)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
        }.padding(17).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(AppPalette.surface,in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(AppPalette.border,lineWidth:1))
            .sheet(isPresented:$rename) {
                VStack(alignment:.leading,spacing:18) {
                    Text("重命名屏幕 \(display.number)").font(.title2)
                    TextField(display.systemName,text:$display.alias).textFieldStyle(.roundedBorder)
                    Text("名称仅保存在这台 Mac，不修改显示器。留空使用原名称。").font(.caption).foregroundStyle(.secondary)
                    HStack { Spacer(); Button("完成") { display.saveName(); rename=false }.keyboardShortcut(.defaultAction) }
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
