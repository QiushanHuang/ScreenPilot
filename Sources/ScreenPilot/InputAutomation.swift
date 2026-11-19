import Foundation
import Combine
import DisplayCore

@MainActor final class InputAutomation:ObservableObject {
    let inventory=USBInventory()
    @Published var enabled=UserDefaults.standard.bool(forKey:"usb.auto.enabled")
    @Published var anyPort=UserDefaults.standard.bool(forKey:"usb.anyPort")
    @Published var keyboardID=UserDefaults.standard.string(forKey:"usb.keyboard") ?? ""
    @Published var mouseID=UserDefaults.standard.string(forKey:"usb.mouse") ?? ""
    @Published var modeRaw=UserDefaults.standard.string(forKey:"usb.mode") ?? "either"
    @Published var status="只检测设备接入，不读取按键或鼠标内容"
    var onMac:((String)->Void)?
    private var gate=InputArrivalGate()
    private var delayed:Task<Void,Never>?
    private var inventoryObserver:AnyCancellable?
    private var startupUntil=ProcessInfo.processInfo.systemUptime+3
    private var lastAuto:TimeInterval = -100
    init() {
        inventory.changed={ [weak self] in self?.devicesChanged() }
        inventoryObserver=inventory.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        _=observe(inventory.devices,at:ProcessInfo.processInfo.systemUptime)
    }
    var mode:InputTriggerMode { InputTriggerMode(rawValue:modeRaw) ?? .either }
    var canEnable:Bool {
        switch mode { case .keyboard:return !keyboardID.isEmpty; case .mouse:return !mouseID.isEmpty; case .either:return !keyboardID.isEmpty || !mouseID.isEmpty; case .both:return !keyboardID.isEmpty && !mouseID.isEmpty }
    }
    func configure() {
        if enabled && !canEnable { enabled=false; status="请先选择共享键盘或鼠标接口" }
        UserDefaults.standard.set(anyPort,forKey:"usb.anyPort"); UserDefaults.standard.set(enabled,forKey:"usb.auto.enabled"); UserDefaults.standard.set(keyboardID,forKey:"usb.keyboard"); UserDefaults.standard.set(mouseID,forKey:"usb.mouse"); UserDefaults.standard.set(modeRaw,forKey:"usb.mode")
        gate.reset(); delayed?.cancel(); startupUntil=ProcessInfo.processInfo.systemUptime+3
        _=observe(inventory.devices,at:ProcessInfo.processInfo.systemUptime)
        status=enabled ? "已启用；等待下一次接入，拔出不会切换" : "自动切换关闭；可观察设备列表变化"
    }
    private func observe(_ devices:[USBInputDevice],at time:TimeInterval)->Bool {
        let keys=devices.filter { $0.keyboard && InputArrivalGate.matches($0.id,selection:keyboardID,anyPort:anyPort) }
        let mice=devices.filter { !$0.keyboard && InputArrivalGate.matches($0.id,selection:mouseID,anyPort:anyPort) }
        return gate.observe(keyboards:Set(keys.map(\.id)),mice:Set(mice.map(\.id)),mode:mode,enabled:enabled,time:time)
    }
    private func devicesChanged() {
        let now=ProcessInfo.processInfo.systemUptime
        ControlTrace.log("usb_inventory_changed",operation:"usb",fields:["devices":inventory.devices.map(\.id)])
        delayed?.cancel()
        if now<startupUntil { gate.reset(); _=observe(inventory.devices,at:now); return }
        if observe(inventory.devices,at:now) { dispatchArrival() }
        delayed=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:1_100_000_000) } catch { return }
            guard let self,let devices=USBInventory.scan() else { return }
            if self.observe(devices,at:ProcessInfo.processInfo.systemUptime) { self.dispatchArrival() }
        }
    }
    private func dispatchArrival() {
        guard enabled else { return }
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastAuto>=5 else { status="自动切换冷却中，已忽略重复接入"; return }
        lastAuto=now
        status="设备接入 Mac，已请求Windows 切回 HDMI 1（局域网）"
        ControlTrace.log("usb_local_request",operation:"usb",fields:["target":"hdmi1","network":true])
        onMac?("usb_mac_lan")
    }
}
