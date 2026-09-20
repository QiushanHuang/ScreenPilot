import Foundation
import Security
import DisplayCore

@MainActor final class WindowsBridgeControl: ObservableObject {
    @Published private(set) var host=UserDefaults.standard.string(forKey:"bridge.host") ?? ""
    @Published private(set) var port=UserDefaults.standard.integer(forKey:"bridge.port")
    @Published var status="尚未连接 Windows"
    @Published var busy=false
    @Published var paused=UserDefaults.standard.bool(forKey:"bridge.paused") {
        didSet { UserDefaults.standard.set(paused,forKey:"bridge.paused"); if paused { inFlight?.cancel();status="局域网联动已暂停" } else { status="局域网联动已恢复" } }
    }
    private var inFlight:Task<BridgeResponse,Error>?
    @Published private(set) var paired=false
    private let service="studio.qiushan.ScreenPilot.WindowsBridge"
    init() { paired=BridgeProtocol.isPrivateIPv4(host) && (1024...65535).contains(port) }
    private var query:[String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"paired-windows"] }
    private func readKey()->Data? {
        var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data,data.count==32 else { return nil }; return data
    }
    func save(code:String) {
        do {
            let pair=try BridgePairing(code:code)
            var result=SecItemUpdate(query as CFDictionary,[kSecValueData as String:pair.key] as CFDictionary)
            if result==errSecItemNotFound {
                var attributes=query; attributes[kSecValueData as String]=pair.key
                result=SecItemAdd(attributes as CFDictionary,nil)
            }
            guard result==errSecSuccess else { throw BridgeFailure("无法将配对密钥保存到钥匙串（\(result)）") }
            host=pair.host; port=pair.port; paired=true
            UserDefaults.standard.set(host,forKey:"bridge.host"); UserDefaults.standard.set(port,forKey:"bridge.port")
            status="配对已保存，点击测试连接"
        } catch { status=error.localizedDescription }
    }
    func check() async {
        do { _=try await perform(.health); status="Windows 程序已连接，签名校验通过" }
        catch { status=error.localizedDescription }
    }
    func returnToMac() async throws {
        for _ in 0..<90 where busy { try await Task.sleep(nanoseconds:100_000_000) }
        _=try await perform(.switchToMac)
        status="Windows 已发送切回 HDMI 1 的命令；请观察屏幕"
    }
    func arrival() async throws -> BridgeResponse { try await perform(.arrivals) }
    private func perform(_ action:BridgeAction) async throws -> BridgeResponse {
        guard !paused else { throw BridgeFailure("局域网联动已暂停") }
        guard !busy,paired,let key=readKey() else { throw BridgeFailure("请先在设置中配对 Windows 程序") }
        busy=true; defer { busy=false }
        let host=self.host,port=self.port
        let task=Task { try await BridgeClient.send(host:host,port:port,key:key,action:action) }
        inFlight=task;defer { inFlight=nil }
        return try await task.value
    }
}
