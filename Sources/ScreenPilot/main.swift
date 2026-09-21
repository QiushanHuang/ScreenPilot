import AppKit
import SwiftUI
import Carbon
import DisplayCore

@MainActor final class AppNavigation:ObservableObject {
    @Published var tab=0
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store=DisplayStore()
    let navigation=AppNavigation()
    var window: NSWindow?
    var statusItem: NSStatusItem?
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults:["appearance.showDockIcon":true])
        applyDockAppearance()
        NotificationCenter.default.addObserver(self,selector:#selector(applyDockAppearance),name:UserDefaults.didChangeNotification,object:UserDefaults.standard)
        buildMenu(); registerRecoveryHotKey(); showWindow()
        Task { await store.refresh() }
        if CommandLine.arguments.contains("--ui-smoke") { Task { await smoke() } }
        if CommandLine.arguments.contains("--connection-smoke") { Task { await connectionSmoke() } }
        if CommandLine.arguments.contains("--connection-group-smoke") { Task { await connectionGroupSmoke() } }
    }
    @objc func applyDockAppearance() {
        let policy: NSApplication.ActivationPolicy = UserDefaults.standard.bool(forKey:"appearance.showDockIcon") ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        if let url=Bundle.main.url(forResource:"ScreenPilotBrand-v2",withExtension:"icns"),let icon=NSImage(contentsOf:url) {
            NSApp.applicationIconImage=icon
        }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        store.restoreAll()
        if let hotKey { UnregisterEventHotKey(hotKey) }; if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    @objc func showWindow() {
        if window == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:min(900,(NSScreen.main?.visibleFrame.height ?? 1080)-40)),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            w.title="屏幕管家"; w.titlebarAppearsTransparent=true; w.titleVisibility = .hidden
            w.minSize=NSSize(width:920,height:680); w.isReleasedWhenClosed=false
            w.contentView=NSHostingView(rootView:Dashboard(store:store,navigation:navigation)); w.center(); window=w
            // SwiftUI appearance preference owns the light/dark theme.
        }
        if let w=window,let screen=NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),!screen.frame.contains(NSPoint(x:w.frame.midX,y:w.frame.midY)) {
            let area=screen.visibleFrame
            let size=NSSize(width:min(w.frame.width,area.width-32),height:min(w.frame.height,area.height-32))
            w.setFrame(NSRect(x:area.midX-size.width/2,y:area.midY-size.height/2,width:size.width,height:size.height),display:true)
        }
        NSApp.unhide(nil)
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showSettings() {
        navigation.tab=3
        showWindow()
    }
    @objc func showAbout() {
        let credits=NSMutableAttributedString(string:"显示器控制、关屏预设与跨主机 USB 联动。\n\n开发与版权：QiushanHuang\n")
        credits.append(NSAttributedString(string:"github.com/QiushanHuang\n",attributes:[.link:URL(string:"https://github.com/QiushanHuang")!]))
        credits.append(NSAttributedString(string:"\n第三方组件\nm1ddc · MIT License\nCopyright (c) 2021 waydabber\n"))
        if let url=Bundle.main.url(forResource:"m1ddc-LICENSE",withExtension:"txt"),let license=try? String(contentsOf:url,encoding:.utf8) {
            credits.append(NSAttributedString(string:"\n完整第三方许可\n"+license))
        }
        credits.addAttribute(.font,value:NSFont.systemFont(ofSize:11),range:NSRange(location:0,length:credits.length))
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"屏幕管家 · ScreenPilot",.credits:credits])
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc func restoreAll() { store.restoreAll() }
    @objc func internalOnlyMenu() { Task { await store.onlyBuiltIn() } }
    @objc func outputPresetMenu(_ item:NSMenuItem) {
        guard let raw=item.representedObject as? String,let id=UUID(uuidString:raw),let preset=store.outputPresets.first(where: { $0.id==id }) else { return }
        Task { await store.applyOutputPreset(preset) }
    }
    @objc func identify() { store.identify() }
    @objc func blackoutMenu(_ item:NSMenuItem) { if let d=store.displays.first(where: { Int($0.id)==item.tag }) { if d.isDisconnected { Task { _=await store.restoreDisconnected(d) } } else { store.blackout(d) } } }
    @objc func switchWindowsMenu(_ item:NSMenuItem) {
        guard let d=store.displays.first(where: { Int($0.id)==item.tag }) else { return }
        let mode=HostLayoutMode(rawValue:UserDefaults.standard.string(forKey:"host.layoutMode") ?? "keep") ?? .keep
        Task { await store.switchToWindows(d,mode:mode) }
    }
    @objc func switchMacMenu(_ item:NSMenuItem) {
        guard let d=store.displays.first(where: { Int($0.id)==item.tag }) else { return }
        Task { await store.switchToMac(d) }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func buildMenu() {
        let main=NSMenu(), appItem=NSMenuItem(), appMenu=NSMenu()
        appMenu.addItem(withTitle:"关于屏幕管家",action:#selector(showAbout),keyEquivalent:"").target=self
        appMenu.addItem(.separator())
        let settingsItem=appMenu.addItem(withTitle:"设置…",action:#selector(showSettings),keyEquivalent:",")
        settingsItem.target=self;settingsItem.keyEquivalentModifierMask=[.command]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"显示屏幕管家",action:#selector(showWindow),keyEquivalent:"0").target=self
        let recovery=appMenu.addItem(withTitle:"恢复所有屏幕",action:#selector(restoreAll),keyEquivalent:"r")
        recovery.target=self; recovery.keyEquivalentModifierMask=[.control,.option,.command]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"隐藏屏幕管家",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h").target=NSApp
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"退出屏幕管家",action:#selector(quit),keyEquivalent:"q").target=self
        main.addItem(appItem); main.setSubmenu(appMenu,for:appItem)
        let editItem=NSMenuItem(title:"编辑",action:nil,keyEquivalent:""); let edit=NSMenu(title:"编辑")
        edit.addItem(withTitle:"撤销",action:Selector(("undo:")),keyEquivalent:"z")
        edit.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        edit.addItem(withTitle:"复制",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        main.addItem(editItem); main.setSubmenu(edit,for:editItem)
        let windowItem=NSMenuItem(title:"窗口",action:nil,keyEquivalent:""); let windowMenu=NSMenu(title:"窗口")
        windowMenu.addItem(withTitle:"显示控制台",action:#selector(showWindow),keyEquivalent:"n").target=self
        windowMenu.addItem(withTitle:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        main.addItem(windowItem); main.setSubmenu(windowMenu,for:windowItem); NSApp.windowsMenu=windowMenu; NSApp.mainMenu=main
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem?.button?.image=NSImage(systemSymbolName:"display.2",accessibilityDescription:"屏幕管家")
        let menu=NSMenu(); menu.autoenablesItems=false; menu.delegate=self; statusItem?.menu=menu
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle:"打开屏幕管家",action:#selector(showWindow),keyEquivalent:"").target=self
        menu.addItem(withTitle:"恢复全部屏幕（含已断开屏幕）",action:#selector(restoreAll),keyEquivalent:"").target=self
        menu.addItem(withTitle:"识别屏幕",action:#selector(identify),keyEquivalent:"").target=self
        let internalOnly=menu.addItem(withTitle:"仅用内置屏 · 停止外屏输出",action:#selector(internalOnlyMenu),keyEquivalent:"")
        internalOnly.target=self;internalOnly.isEnabled = !store.scanning && !store.connectionBusy && !store.hostSwitchBusy && store.displays.contains { $0.builtIn && !$0.isDisconnected }
        if !store.outputPresets.isEmpty {
            let item=NSMenuItem(title:"关屏预设",action:nil,keyEquivalent:"");let submenu=NSMenu();submenu.autoenablesItems=false
            for preset in store.outputPresets {
                let entry=submenu.addItem(withTitle:preset.name,action:#selector(outputPresetMenu(_:)),keyEquivalent:"")
                entry.target=self;entry.representedObject=preset.id.uuidString;entry.isEnabled = !store.scanning && !store.connectionBusy && !store.hostSwitchBusy
            }
            item.submenu=submenu;menu.addItem(item)
        }
        menu.addItem(.separator())
        for d in store.displays {
            let item=menu.addItem(withTitle:"\(d.number) · \(d.title) — \(d.isDisconnected ? "恢复显示连接" : d.shade.blackedOut ? "恢复" : "黑屏")",action:#selector(blackoutMenu(_:)),keyEquivalent:"")
            item.target=self; item.tag=Int(d.id)
        }
        for d in store.displays where !store.verifiedInputs(for:d).isEmpty {
            menu.addItem(.separator())
            let toWindows=menu.addItem(withTitle:"\(d.title) → Windows",action:#selector(switchWindowsMenu(_:)),keyEquivalent:"")
            toWindows.target=self; toWindows.tag=Int(d.id); toWindows.isEnabled = !d.isDisconnected && !store.hostSwitchBusy && !store.connectionBusy
            let toMac=menu.addItem(withTitle:"\(d.title) → 切回 Mac",action:#selector(switchMacMenu(_:)),keyEquivalent:"")
            toMac.target=self; toMac.tag=Int(d.id); toMac.isEnabled=store.windowsBridge.paired && !store.hostSwitchBusy && !store.connectionBusy
        }
        menu.addItem(.separator()); menu.addItem(withTitle:"退出并恢复屏幕",action:#selector(quit),keyEquivalent:"q").target=self
    }
    func registerRecoveryHotKey() {
        var event=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let context=Unmanaged.passUnretained(self).toOpaque()
        let installed=InstallEventHandler(GetApplicationEventTarget(), { _,_,context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app=Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in app.restoreAll() }
            return noErr
        },1,&event,context,&eventHandler)
        let keyID=EventHotKeyID(signature:0x5350494c,id:1)
        let registered=RegisterEventHotKey(UInt32(kVK_ANSI_R),UInt32(controlKey|optionKey|cmdKey),keyID,GetApplicationEventTarget(),0,&hotKey)
        store.recoveryShortcutAvailable=installed==noErr && registered==noErr
    }
    func connectionGroupSmoke() async {
        while store.scanning || store.displays.isEmpty { try? await Task.sleep(nanoseconds:100_000_000) }
        let targets=(ProcessInfo.processInfo.environment["SCREENPILOT_SMOKE_TARGETS"] ?? "").split(separator:",").map(String.init)
        guard targets.count==3 else { exit(2) }
        for uuid in targets {
            for _ in 0..<60 where store.scanning { try? await Task.sleep(nanoseconds:100_000_000) }
            guard let d=store.displays.first(where: { $0.key.uuid==uuid }) else { exit(2) }
            await store.disconnect(d); store.keepDisconnected()
        }
        for _ in 0..<60 where store.scanning { try? await Task.sleep(nanoseconds:100_000_000) }
        var activeCount:UInt32=0; CGGetActiveDisplayList(0,nil,&activeCount)
        let allThreeOff=store.connectionUUIDs.count==3 && activeCount==1 && store.displays.filter { !$0.isDisconnected }.count==1
        let directory=store.connection.directory?.path ?? ""
        if let last=store.displays.first(where: { !$0.isDisconnected }) { await store.disconnect(last) }
        let protectedLast=store.displays.contains(where: { !$0.isDisconnected && $0.builtIn })
        var oneRestored=false
        if let d=store.displays.first(where: { $0.key.uuid==targets[1] }) { oneRestored=await store.restoreDisconnected(d) }
        let twoRemain=store.connectionUUIDs.count==2 && store.displays.filter { store.connectionUUIDs.contains($0.key.uuid) }.allSatisfy { CGDisplayIsActive($0.id)==0 }
        let record:[String:Any]=["directory":directory,"allThreeOff":allThreeOff,"protectedLast":protectedLast,"oneRestored":oneRestored,"twoRemain":twoRemain]
        if let dest=ProcessInfo.processInfo.environment["SCREENPILOT_SMOKE_REPORT"],let data=try? JSONSerialization.data(withJSONObject:record,options:.prettyPrinted) { try? data.write(to:URL(fileURLWithPath:dest),options:.atomic) }
        exit(0) // independent guard must restore the remaining displays and original layout.
    }
    func connectionSmoke() async {
        while store.scanning || store.displays.isEmpty { try? await Task.sleep(nanoseconds:100_000_000) }
        guard let display=store.displays.first(where: { $0.key.uuid == ProcessInfo.processInfo.environment["SCREENPILOT_SMOKE_TARGET"] && !$0.isMain }) else { exit(2) }
        await store.disconnect(display)
        guard store.connectionUUID==display.key.uuid,let directory=store.connection.directory else { exit(3) }
        store.keepDisconnected()
        let destination=ProcessInfo.processInfo.environment["SCREENPILOT_SMOKE_REPORT"]
        func report(_ data:[String:Any]) {
            if let destination,let bytes=try? JSONSerialization.data(withJSONObject:data,options:.prettyPrinted) {
                try? bytes.write(to:URL(fileURLWithPath:destination),options:.atomic)
            }
        }
        report(["stage":"held","directory":directory.path])
        try? await Task.sleep(nanoseconds:30_000_000_000)
        report(["stage":"exitingWithoutTerminationCallback","directory":directory.path,
                "heldBeyondPreview":CGDisplayIsActive(display.id)==0,
                "cardRetained":store.displays.contains(where: { $0.key==display.key }),
                "previewCleared":!store.connectionPreview])
        // Intentionally omit applicationWillTerminate to exercise guardian recovery.
        exit(0)
    }
    func smoke() async {
        while store.scanning || store.displays.isEmpty { try? await Task.sleep(nanoseconds:100_000_000) }
        let count=store.displays.count
        let keys=Set(store.displays.map(\.key))
        let originalWindow=window
        showWindow(); showWindow()
        let single=window===originalWindow
        // Exercise real covering windows briefly on one non-main screen, then restore.
        if let d=store.displays.first(where: { !$0.isMain }) {
            store.selectMode(.software,for:d); store.setBrightness(75,for:d)
            try? await Task.sleep(nanoseconds:200_000_000)
            store.blackout(d)
            try? await Task.sleep(nanoseconds:350_000_000)
            let created=store.overlays.count>0
            store.restoreAll()
            let restored=store.overlays.count==0 && store.displays.allSatisfy { !$0.shade.blackedOut && $0.shade.dimPercent==100 }
            let report="screens=\(count) unique=\(keys.count) singleWindow=\(single) overlayCreated=\(created) restored=\(restored) hotkey=\(store.recoveryShortcutAvailable)\n"
            print(report)
            if let dest=ProcessInfo.processInfo.environment["SCREENPILOT_SMOKE_REPORT"] { try? report.write(toFile:dest,atomically:true,encoding:.utf8) }
        }
        NSApp.terminate(nil)
    }
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate()
    app.delegate=delegate
    app.run()
}
