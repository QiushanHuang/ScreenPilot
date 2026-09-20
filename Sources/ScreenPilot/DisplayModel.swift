import AppKit
import SwiftUI
import Combine
import DisplayCore

@MainActor final class DisplayModel: ObservableObject, Identifiable {
    let id: CGDirectDisplayID
    let key: DeviceKey
    let systemName: String
    let builtIn: Bool
    @Published var alias: String
    @Published var number: Int
    @Published var frame: CGRect
    @Published var detail: String
    @Published var isMain: Bool
    @Published var isDisconnected = false
    @Published var mode: BrightnessMode = .software
    @Published var brightness: Double = 100
    @Published var hardwarePercent: Double?
    @Published var maximum: Int?
    @Published var input: Int?
    @Published var power: Int?
    @Published var inputSupported = false
    @Published var powerSupported = false
    @Published var probing = true
    @Published var busy = false
    @Published var shade = ShadeState()
    @Published var preview = false
    @Published var note = "正在检测控制能力…"
    @Published var error: String?
    @Published var probeDetail = ""
    var title: String { alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? systemName : alias }
    var hardwareAvailable: Bool { maximum != nil && hardwarePercent != nil }
    var storageKey: String { key.uuid + "|" + key.location }
    init(screen: NSScreen, key: DeviceKey, number: Int) {
        id=key.id; self.key=key; self.number=number; frame=screen.frame
        builtIn=CGDisplayIsBuiltin(key.id) != 0
        systemName=builtIn ? "内置显示屏" : screen.localizedName
        alias=UserDefaults.standard.string(forKey: "name."+key.uuid+"|"+key.location) ?? ""
        isMain=key.id == CGMainDisplayID()
        let displayMode=CGDisplayCopyDisplayMode(key.id)
        let rate=displayMode?.refreshRate ?? 0
        detail="\(displayMode?.pixelWidth ?? CGDisplayPixelsWide(key.id)) × \(displayMode?.pixelHeight ?? CGDisplayPixelsHigh(key.id))" + (rate > 0 ? " · \(Int(rate.rounded())) Hz" : "")
    }
    func saveName() { UserDefaults.standard.set(alias, forKey: "name."+storageKey) }
}

@MainActor final class DisplayStore: ObservableObject {
    @Published var displays: [DisplayModel] = []
    @Published var scanning = false
    @Published var banner = "正在查找显示器…"
    @Published var scenes: [DisplayScene] = []
    @Published var recoveryShortcutAvailable = false
    let verifiedInputs: [VerifiedInput] = {
        let resource=Bundle.main.resourceURL?.appendingPathComponent("VerifiedInputs.json")
        let source=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Config/VerifiedInputs.json")
        guard let data=try? Data(contentsOf:resource.flatMap { FileManager.default.fileExists(atPath:$0.path) ? $0 : nil } ?? source),
              let entries=try? JSONDecoder().decode([VerifiedInput].self,from:data) else { return [] }
        return entries
    }()
    func verifiedInputs(for display: DisplayModel) -> [VerifiedInput] {
        verifiedInputs.filter { $0.matches(display.key) }
    }
    let connection=ConnectionDriver()
    @Published var connectionUUIDs=Set<String>()
    var connectionUUID:String? { connectionUUIDs.first }
    @Published var outputRecovery=OutputRecoveryMode(rawValue:UserDefaults.standard.string(forKey:"output.recovery") ?? "preview") ?? .preview {
        didSet { UserDefaults.standard.set(outputRecovery.rawValue,forKey:"output.recovery") }
    }
    @Published var outputPresets:[OutputPreset]=[]
    @Published var connectionPreview = false
    @Published var connectionBusy = false
    @Published var hostSwitchBusy = false
    private var disconnectedDisplays:[String:DisplayModel]=[:]
    @Published var connectionRecoveryFailed=false
    let windowsBridge=WindowsBridgeControl()
    let inputAutomation=InputAutomation()
    private var inputObserver:AnyCancellable?
    private var bridgeObserver:AnyCancellable?
    private var connectionMonitor: Task<Void,Never>?
    func supportsDisconnect(_ display: DisplayModel) -> Bool {
        UUID(uuidString:display.key.uuid) != nil && !display.key.location.isEmpty
    }
    let hardware=HardwareClient()
    let overlays=OverlayController()
    private var refreshQueued=false
    private var generation=UUID()
    private var brightnessTasks: [UInt32: Task<Void,Never>] = [:]
    private var remoteArrivalTask:Task<Void,Never>?
    private var previewTasks: [UInt32: Task<Void,Never>] = [:]
    private var observed: NSObjectProtocol?
    var liveKeys: [DeviceKey] { displays.filter { !$0.isDisconnected }.map(\.key) }
    init() {
        bridgeObserver=windowsBridge.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        inputObserver=inputAutomation.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        inputAutomation.onMac={ [weak self] source in
            guard let self else { return }
            guard let display=self.displays.first(where: { !self.verifiedInputs(for:$0).isEmpty }) else { self.inputAutomation.status="未找到共享显示器，未发送命令"; return }
            Task { await self.switchToMac(display,source:source) }
        }
        remoteArrivalTask=Task { [weak self] in
            var gate=RemoteArrivalGate()
            var pollPolicy=BridgePollPolicy()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds:UInt64(pollPolicy.delay*1_000_000_000)) } catch { return }
                guard let self else { return }
                guard self.inputAutomation.enabled,self.windowsBridge.paired,!self.windowsBridge.paused else { gate=RemoteArrivalGate(); continue }
                if self.windowsBridge.busy || self.hostSwitchBusy { continue }
                do {
                    let reply=try await self.windowsBridge.arrival()
                    pollPolicy.succeeded()
                    self.windowsBridge.status="局域网已连接 · 等待键鼠接入"
                    if gate.accept(id:reply.arrivalID,timestamp:reply.arrivalTime,now:Date().timeIntervalSince1970),
                       let display=self.displays.first(where:{ !self.verifiedInputs(for:$0).isEmpty }) {
                        self.inputAutomation.status="Windows 检测到键鼠接入，Mac 请求切到 HDMI 2"
                        await self.switchToWindows(display,mode:.keep)
                    }
                } catch { pollPolicy.failed(); self.inputAutomation.status="联动暂不可用："+error.localizedDescription+"（稍后重试）" }
            }
        }
        if let data=UserDefaults.standard.data(forKey:"output.presets"),let saved=try? JSONDecoder().decode([OutputPreset].self,from:data) { outputPresets=saved }
        if let data=UserDefaults.standard.data(forKey: "scenes"), let saved=try? JSONDecoder().decode([DisplayScene].self,from:data) { scenes=saved }
        observed=NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.topologyChanged() }
        }
    }
    func topologyChanged() {
        // Remove all covering windows immediately; stale queued hardware writes are cancelled.
        restoreAll(restoreDisconnected:false); generation=UUID()
        Task { await refresh() }
    }
    func refresh() async {
        guard !scanning else { refreshQueued=true; return }
        scanning=true; generation=UUID(); let epoch=generation
        brightnessTasks.values.forEach { $0.cancel() }; brightnessTasks.removeAll()
        let previous=displays
        do {
            let reply=try await hardware.call("list")
            guard epoch==generation else { scanning=false; await refresh(); return }
            let devices=reply.displays ?? []
            let screens=NSScreen.screens.sorted { a,b in
                let aID=(a.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                let bID=(b.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                if aID==CGMainDisplayID() { return true }; if bID==CGMainDisplayID() { return false }
                return a.frame.minX < b.frame.minX
            }
            displays=screens.enumerated().map { index,screen in
                let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                let matches=devices.filter { $0.id==id }
                let key=matches.count==1 ? matches[0].key : DeviceKey(id:id,uuid:"unmapped-\(id)",location:"")
                if let old=previous.first(where: { $0.key==key }) {
                    old.number=index+1; old.frame=screen.frame; old.isMain=id==CGMainDisplayID(); old.probing=true; old.isDisconnected=false
                    return old
                }
                return DisplayModel(screen:screen,key:key,number:index+1)
            }
            for retained in disconnectedDisplays.values where !displays.contains(where: { $0.key.uuid==retained.key.uuid }) {
                retained.isDisconnected=true; retained.isMain=false; retained.probing=false; retained.number=displays.count+1
                displays.append(retained)
            }
            overlays.removeMissing(Set(displays.filter { !$0.isDisconnected }.map(\.id)))
            for display in displays {
                guard epoch==generation else { break }
                if !display.isDisconnected { await probe(display, epoch:epoch) }
            }
            banner="已连接 \(displays.filter { !$0.isDisconnected }.count) 块屏幕 · \(displays.filter(\.hardwareAvailable).count) 块可读取硬件亮度"
        } catch {
            if displays.isEmpty {
                displays=NSScreen.screens.enumerated().map { i,screen in
                    let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                    return DisplayModel(screen:screen,key:DeviceKey(id:id,uuid:"unmapped-\(id)",location:""),number:i+1)
                }
            }
            for d in displays {
                d.probing=false; d.maximum=nil; d.hardwarePercent=nil; d.inputSupported=false; d.powerSupported=false
                d.mode = .software; d.brightness=d.shade.dimPercent
                d.note="软件调暗可用"; d.error=error.localizedDescription
            }
            banner="硬件检测失败；黑屏和软件调暗仍可使用"
        }
        scanning=false
        if refreshQueued { refreshQueued=false; await refresh() }
    }
    private func probe(_ display: DisplayModel, epoch: UUID) async {
        display.error=nil; display.probing=true
        defer { display.probing=false }
        guard ControlPolicy.canWrite(display.key,among:liveKeys) else {
            display.maximum=nil; display.hardwarePercent=nil; display.mode = .software
            display.note="软件调暗 · 硬件标识不可用"; return
        }
        do {
            let result=try await hardware.call("probe",key:display.key)
            guard epoch==generation, displays.contains(where: { $0 === display }) else { return }
            let wasHardware=display.hardwareAvailable
            display.hardwarePercent=result.brightness?.percent
            display.maximum=display.hardwarePercent == nil ? nil : result.brightness?.maximum
            display.inputSupported=result.input?.ok == true
            display.powerSupported=result.power?.ok == true
            display.input=display.inputSupported ? result.input?.current : nil
            display.power=display.powerSupported ? result.power?.current : nil
            if display.hardwareAvailable {
                if !wasHardware && display.shade.dimPercent==100 { display.mode = .hardware }
                if display.mode == .hardware { display.brightness=display.hardwarePercent ?? 100 }
                display.note=display.builtIn ? "原生背光 · 已读取" : "DDC 背光 · 已读取"
            } else {
                display.mode = .software; display.brightness=display.shade.dimPercent
                display.note="软件调暗 · 硬件亮度未验证"
            }
            display.probeDetail=["亮度："+(result.brightness?.ok == true ? "读回正常" : result.brightness?.error ?? "不支持"),
                "输入："+(result.input?.ok == true ? inputName(display.input) : result.input?.error ?? "不适用"),
                "电源："+(result.power?.ok == true ? "读回正常，实际控制待验证" : result.power?.error ?? "不适用")].joined(separator:"\n")
        } catch {
            display.maximum=nil; display.hardwarePercent=nil; display.inputSupported=false; display.powerSupported=false
            display.mode = .software; display.brightness=display.shade.dimPercent
            display.note="软件调暗可用"; display.probeDetail=error.localizedDescription
        }
    }
    func selectMode(_ mode: BrightnessMode, for display: DisplayModel) {
        brightnessTasks[display.id]?.cancel()
        guard mode != .hardware || display.hardwareAvailable else { return }
        display.mode=mode
        if mode == .hardware {
            display.shade.dimPercent=100; display.brightness=display.hardwarePercent ?? 100; updateOverlay(display)
        } else { display.brightness=display.shade.dimPercent }
    }
    func setBrightness(_ percent: Double, for display: DisplayModel) {
        display.brightness=percent; display.error=nil
        if display.mode == .software {
            display.shade.dimPercent=percent; updateOverlay(display); return
        }
        brightnessTasks[display.id]?.cancel()
        let epoch=generation
        brightnessTasks[display.id]=Task { [weak self, weak display] in
            do { try await Task.sleep(nanoseconds:250_000_000) } catch { return }
            guard let self,let display,!Task.isCancelled,epoch==self.generation,
                  display.mode == .hardware,ControlPolicy.canWrite(display.key,among:self.liveKeys),
                  let maximum=display.maximum,let raw=ControlPolicy.rawBrightness(percent:percent,maximum:maximum) else { return }
            display.busy=true
            defer { display.busy=false }
            do {
                let result=try await self.hardware.call("set",key:display.key,feature:"brightness",value:raw)
                guard !Task.isCancelled,epoch==self.generation else { return }
                if let current=result.current,let max=result.maximum,let actual=ControlPolicy.brightnessPercent(current:current,maximum:max) {
                    display.hardwarePercent=actual; display.brightness=actual
                }
                guard result.verified == true else { throw HardwareFailure(message:"亮度回读与目标不一致，请观察屏幕后重新检测") }
                display.note=display.builtIn ? "原生背光 · 已验证" : "DDC 背光 · 已验证"
            } catch {
                guard !Task.isCancelled else { return }
                display.error=error.localizedDescription
                display.brightness=display.hardwarePercent ?? display.brightness
            }
        }
    }
    func blackout(_ display: DisplayModel) {
        if display.shade.blackedOut { restore(display); return }
        display.shade.blackedOut=true; display.preview=true; updateOverlay(display)
        previewTasks[display.id]?.cancel()
        previewTasks[display.id]=Task { [weak self,weak display] in
            do { try await Task.sleep(nanoseconds:12_000_000_000) } catch { return }
            guard let self,let display,display.preview else { return }; self.restore(display)
        }
    }
    func keepBlackout(_ display: DisplayModel) {
        previewTasks[display.id]?.cancel(); display.preview=false; updateOverlay(display)
    }
    func restore(_ display: DisplayModel) {
        previewTasks[display.id]?.cancel(); display.preview=false; display.shade.blackedOut=false; updateOverlay(display)
    }
    func restoreAll(restoreDisconnected: Bool = true) {
        if restoreDisconnected { requestConnectionRestore() }
        brightnessTasks.values.forEach { $0.cancel() }; brightnessTasks.removeAll()
        previewTasks.values.forEach { $0.cancel() }; previewTasks.removeAll()
        for d in displays {
            d.shade.restore(); d.preview=false
            if d.mode == .software { d.brightness=100 }
        }
        overlays.removeAll()
        banner=connectionUUID == nil ? "已恢复所有软件黑屏与调暗" : "正在恢复显示连接；软件遮罩已清除"
    }
    func onlyMain() { for d in displays where !d.isDisconnected { if d.isMain { restore(d) } else if !d.shade.blackedOut { blackout(d) } } }
    func updateOverlay(_ display: DisplayModel) {
        overlays.update(display,restore:{ [weak self,weak display] in if let display { self?.restore(display) } },keep:{ [weak self,weak display] in if let display { self?.keepBlackout(display) } })
    }
    func identify() { overlays.identify(displays.filter { !$0.isDisconnected }) }
    @discardableResult func send(_ feature: String,value: Int,to display: DisplayModel) async -> Bool {
        guard !display.busy,!scanning,ControlPolicy.canWrite(display.key,among:liveKeys),
              (feature == "power" && display.powerSupported) || (feature == "input" && InputAccess.allows(target:display.key,live:liveKeys,readable:display.inputSupported,verified:verifiedInputs,value:value)) else { return false }
        display.busy=true; display.error=nil
        defer { display.busy=false }
        do {
            _ = try await hardware.call("set",key:display.key,feature:feature,value:value)
            display.note="命令已发送 · 请观察显示器确认"
            // A successful write is not a physical-result confirmation.
            return true
        } catch { display.error=error.localizedDescription; return false }
    }

    func disconnect(_ display: DisplayModel,fromHost:Bool=false,recovery:OutputRecoveryMode?=nil) async {
        guard supportsDisconnect(display),!scanning,!connectionBusy,!connectionRecoveryFailed,(!hostSwitchBusy || fromHost),
              ControlPolicy.canWrite(display.key,among:liveKeys),liveKeys.count>1 else { return }
        connectionBusy=true; display.error=nil
        do {
            try await connection.prepare()
            disconnectedDisplays[display.key.uuid]=display; connectionUUIDs.insert(display.key.uuid); connectionPreview=true
            display.isDisconnected=true; restore(display)
            try await connection.disable(display.key.uuid)
            let mode=recovery ?? (fromHost ? .manual : outputRecovery)
            try connection.setRecovery(mode)
            connectionPreview=mode.automaticallyRestores
            banner=mode.automaticallyRestores ? "已停止输出 · 15 秒后恢复" : "已停止输出 · 保持至手动恢复"

            monitorConnection()
        } catch {
            display.error=error.localizedDescription
            if connection.directory != nil {
                disconnectedDisplays[display.key.uuid]=display; connectionUUIDs.insert(display.key.uuid)
                connection.requestRestore(); monitorConnection()
            }
        }
        connectionBusy=false
    }
    func updateStoppedRecovery(_ mode:OutputRecoveryMode) {
        outputRecovery=mode
        guard !connectionUUIDs.isEmpty,!connectionBusy else { return }
        do { try connection.setRecovery(mode);connectionPreview=mode.automaticallyRestores;banner=mode.automaticallyRestores ? "将在 15 秒后恢复已停止的屏幕" : "已关闭倒计时 · 保持至手动恢复" }
        catch { banner=error.localizedDescription }
    }
    @discardableResult func saveOutputPreset(name:String,uuids:Set<String>,recovery:OutputRecoveryMode,replacing id:UUID?=nil) -> Bool {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty,!uuids.isEmpty else { return false }
        let selected=displays.filter { uuids.contains($0.key.uuid) }
        guard selected.count==uuids.count else { banner="部分屏幕已不在列表中，请重新选择";return false }
        var preset=OutputPreset(name:trimmed,targets:selected.map { OutputTarget(uuid:$0.key.uuid,location:$0.key.location) },recovery:recovery)
        if let id {
            guard let index=outputPresets.firstIndex(where: { $0.id==id }) else { banner="预设已被删除，请重新新建";return false }
            preset.id=id;outputPresets[index]=preset
        } else { outputPresets.append(preset) }
        persistOutputPresets();return true
    }
    func deleteOutputPreset(_ id:UUID) { outputPresets.removeAll { $0.id==id };persistOutputPresets() }
    private func persistOutputPresets() { if let data=try? JSONEncoder().encode(outputPresets) { UserDefaults.standard.set(data,forKey:"output.presets") } }
    func onlyBuiltIn() async {
        guard displays.contains(where: { $0.builtIn && !$0.isDisconnected }) else { banner="内置屏未在输出，请先打开内置屏";return }
        let external=displays.filter { !$0.builtIn && !$0.isDisconnected }
        guard !external.isEmpty else { banner="当前已仅使用内置屏";return }
        await applyOutputPreset(OutputPreset(name:"仅用内置屏",targets:external.map { OutputTarget(uuid:$0.key.uuid,location:$0.key.location) },recovery:outputRecovery))
    }
    func applyOutputPreset(_ preset:OutputPreset) async {
        guard !scanning,!connectionBusy,!hostSwitchBusy,!connectionRecoveryFailed else { banner="显示器操作进行中，请稍后执行预设";return }
        do {
            // Already-stopped members need no write, but still validate their saved identity.
            for target in preset.targets {
                guard displays.filter({ $0.key.uuid==target.uuid && $0.key.location==target.location }).count==1 else { throw BridgeFailure("预设中的屏幕缺失或接口改变，请重新选择") }
            }
            let remaining=preset.targets.filter { !connectionUUIDs.contains($0.uuid) }
            guard !remaining.isEmpty else { banner="预设中的屏幕已经停止输出";return }
            let keys=try OutputPreset(name:preset.name,targets:remaining,recovery:preset.recovery).resolve(among:liveKeys)
            hostSwitchBusy=true;defer { hostSwitchBusy=false }
            var done=0
            for key in keys {
                for _ in 0..<100 where scanning { try await Task.sleep(nanoseconds:100_000_000) }
                guard !scanning,let display=displays.first(where: { $0.key.uuid==key.uuid && $0.key.location==key.location }),!display.isDisconnected else { throw BridgeFailure("屏幕状态发生变化，已停止继续执行") }
                await disconnect(display,fromHost:true,recovery:.manual)
                guard connectionUUIDs.contains(key.uuid),display.error==nil else { throw BridgeFailure(display.error ?? "停止输出未完成") }
                done+=1
                banner="正在执行预设：已停止 \(done) / \(keys.count) 块屏幕"
            }
            try connection.setRecovery(preset.recovery);connectionPreview=preset.recovery.automaticallyRestores
            banner="预设「\(preset.name)」已执行 · \(done) 块屏幕停止输出"+(connectionPreview ? " · 15 秒后恢复" : " · 手动恢复")
        } catch { banner="预设未全部完成："+error.localizedDescription }
    }
    func keepDisconnected() {
        do { try connection.keepOff(); connectionPreview=false; banner="已保持关闭 · 可逐屏恢复或恢复全部" }
        catch { disconnectedDisplays.values.forEach { $0.error=error.localizedDescription }; requestConnectionRestore() }
    }
    func restoreDisconnected(_ display:DisplayModel) async -> Bool {
        guard connectionUUIDs.contains(display.key.uuid),!connectionBusy else { return !display.isDisconnected }
        connectionBusy=true; display.error=nil
        defer { connectionBusy=false }
        do {
            try await connection.enable(display.key.uuid)
            display.isDisconnected=false; connectionUUIDs.remove(display.key.uuid); disconnectedDisplays.removeValue(forKey:display.key.uuid)
            if connectionUUIDs.isEmpty { connection.requestRestore() }
            await refresh(); banner="已重新连接 \(display.title)"
            return true
        } catch { display.error=error.localizedDescription; return false }
    }
    func requestConnectionRestore() {
        guard connection.directory != nil else { return }
        do {
            try connection.retryRestore(); connectionPreview=false; connectionBusy=true; connectionRecoveryFailed=false
            monitorConnection()
        } catch { disconnectedDisplays.values.forEach { $0.error=error.localizedDescription }; connectionBusy=false }
    }
    private func monitorConnection() {
        connectionMonitor?.cancel()
        connectionMonitor=Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let result=self.connection.result() {
                    self.connectionBusy=false; self.connectionPreview=false
                    if result.ok {
                        self.disconnectedDisplays.values.forEach { $0.isDisconnected=false }
                        self.connection.finish(); self.connectionUUIDs.removeAll(); self.disconnectedDisplays.removeAll(); self.connectionRecoveryFailed=false
                        await self.refresh(); self.banner="屏幕已恢复 · 原布局已验证"
                    } else {
                        self.connectionRecoveryFailed=true
                        self.disconnectedDisplays.values.forEach { $0.error=result.error ?? "恢复失败，请重试恢复或重新插拔线缆" }
                        self.banner="屏幕恢复未完成，请重试恢复"
                    }
                    return
                }
                do { try await Task.sleep(nanoseconds:250_000_000) } catch { return }
            }
        }
    }
    func switchToWindows(_ display:DisplayModel,mode:HostLayoutMode) async {
        guard !display.isDisconnected,!connectionBusy,!scanning,!hostSwitchBusy else { return }
        hostSwitchBusy=true; defer { hostSwitchBusy=false }
        if mode == .disconnect {
            do { try await connection.prepare() }
            catch { display.error=error.localizedDescription; return }
        }
        guard await send("input",value:18,to:display) else {
            if mode == .disconnect { connection.requestRestore(); monitorConnection() }
            return
        }
        if mode == .disconnect {
            // Allow the display-change notification to finish before taking it offline.
            for _ in 0..<40 where scanning { try? await Task.sleep(nanoseconds:100_000_000) }
            await disconnect(display,fromHost:true)
        }
    }
    func waitForStableLayout(_ display:DisplayModel,operation:String) async throws {
        var readiness=LayoutReadiness()
        let deadline=ProcessInfo.processInfo.systemUptime+25
        ControlTrace.log("layout_wait_begin",operation:operation,fields:["target":display.key.uuid])
        while ProcessInfo.processInfo.systemUptime<deadline {
            try Task.checkCancellation()
            if connectionRecoveryFailed { throw HardwareFailure(message:"显示布局恢复失败，未发送切回命令") }
            let snapshots=try await connection.snapshot()
            let recovering=connectionBusy || scanning || connectionPreview || (connection.directory != nil && connectionUUIDs.isEmpty)
            if readiness.observe(snapshots,target:display.key.uuid,busy:recovering,uptime:ProcessInfo.processInfo.systemUptime) {
                ControlTrace.log("layout_ready",operation:operation,fields:["target":display.key.uuid,"onlineCount":snapshots.count])
                return
            }
            try await Task.sleep(nanoseconds:250_000_000)
        }
        throw HardwareFailure(message:"显示连接尚未稳定，未发送切回命令。请先恢复显示布局")
    }
    func switchToMac(_ display:DisplayModel,source:String="manual") async {
        guard !hostSwitchBusy,!connectionBusy else { return }
        hostSwitchBusy=true; defer { hostSwitchBusy=false }
        let operation=UUID().uuidString
        ControlTrace.log("return_requested",operation:operation,fields:["source":source,"target":display.key.uuid,"disconnected":display.isDisconnected,"mode":UserDefaults.standard.string(forKey:"host.layoutMode") ?? "keep"])
        guard windowsBridge.paired else { display.error="请先在设置中配对 Windows 常驻程序"; return }
        if display.isDisconnected || connectionUUIDs.contains(display.key.uuid) {
            ControlTrace.log("reconnect_begin",operation:operation)
            guard await restoreDisconnected(display) else { ControlTrace.log("reconnect_failed",operation:operation); return }
        }
        display.busy=true; display.error=nil; defer { display.busy=false }
        do {
            display.note="等待显示布局稳定…"
            try await waitForStableLayout(display,operation:operation)
            ControlTrace.log("bridge_send_begin",operation:operation)
            try await windowsBridge.returnToMac()
            ControlTrace.log("bridge_command_sent",operation:operation)
            display.note="Windows 已发送切回 Mac 的命令 · 请观察屏幕"
        } catch {
            display.error=error.localizedDescription
            ControlTrace.log("return_failed",operation:operation,fields:["error":error.localizedDescription])
        }
    }

    func switchToMacOffline(_ display:DisplayModel,source:String) async {
        guard !hostSwitchBusy,!connectionBusy,!verifiedInputs(for:display).isEmpty else {
            inputAutomation.status="本地切换忙，已忽略本次接入"; return
        }
        hostSwitchBusy=true; defer { hostSwitchBusy=false }
        let operation=UUID().uuidString
        ControlTrace.log("offline_return_requested",operation:operation,fields:["source":source,"network":false,"target":display.key.uuid])
        if display.isDisconnected || connectionUUIDs.contains(display.key.uuid) {
            guard await restoreDisconnected(display) else { return }
        }
        display.busy=true; defer { display.busy=false }
        do {
            try await waitForStableLayout(display,operation:operation)
            guard ControlPolicy.canWrite(display.key,among:liveKeys) else { throw HardwareFailure(message:"目标显示器标识已改变") }
            // Explicit local-only route. No WindowsBridge or network fallback.
            _=try await hardware.call("set",key:display.key,feature:"input",value:17)
            display.note="已从本机发送 HDMI 1 · 实际切回待观察"
            inputAutomation.status="离线请求已发送；若画面未切回，表示该硬件路径仍不兼容"
            ControlTrace.log("offline_command_sent",operation:operation,fields:["network":false])
        } catch { display.error=error.localizedDescription;inputAutomation.status=error.localizedDescription;ControlTrace.log("offline_return_failed",operation:operation,fields:["error":error.localizedDescription]) }
    }

    func saveScene(name: String) {
        let cleaned=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let entries=displays.filter { ControlPolicy.canWrite($0.key,among:liveKeys) }.map {
            SceneEntry(uuid:$0.key.uuid,location:$0.key.location,brightness:$0.brightness,mode:$0.mode,blackedOut:$0.shade.blackedOut)
        }
        scenes.append(DisplayScene(name:String(cleaned.prefix(40)),entries:entries)); persistScenes()
    }
    func deleteScene(_ id: UUID) { scenes.removeAll { $0.id==id }; persistScenes() }
    private func persistScenes() { if let data=try? JSONEncoder().encode(scenes) { UserDefaults.standard.set(data,forKey:"scenes") } }
    func apply(_ scene: DisplayScene) {
        var skipped=0
        for entry in scene.entries {
            guard let key=entry.applies(to:liveKeys),let d=displays.first(where: { $0.key==key }),entry.mode != .hardware || d.hardwareAvailable else { skipped+=1; continue }
            selectMode(entry.mode,for:d); setBrightness(entry.brightness,for:d)
            if entry.blackedOut && !d.shade.blackedOut { blackout(d) }
            else if !entry.blackedOut { restore(d) }
        }
        banner="已应用「\(scene.name)」"+(skipped>0 ? " · \(skipped) 块屏幕因标识或能力变化而跳过" : "")
    }
}
func inputName(_ value: Int?) -> String {
    switch value { case 15:return "DisplayPort 1"; case 16:return "DisplayPort 2"; case 17:return "HDMI 1"; case 18:return "HDMI 2"; case 27:return "USB-C"; case .some(let n):return "输入 \(n)"; case nil:return "未读取" }
}
