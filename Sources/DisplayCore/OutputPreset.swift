import Foundation
public enum OutputRecoveryMode:String,Codable,CaseIterable,Sendable {
    case preview,manual
    public var automaticallyRestores:Bool { self == .preview }
}
public struct OutputTarget:Codable,Equatable,Sendable {
    public let uuid:String
    public let location:String
    public init(uuid:String,location:String) { self.uuid=uuid;self.location=location }
}
public struct OutputPreset:Codable,Identifiable,Sendable {
    public var id=UUID()
    public var name:String
    public var targets:[OutputTarget]
    public var recovery:OutputRecoveryMode
    public init(name:String,targets:[OutputTarget],recovery:OutputRecoveryMode) { self.name=name;self.targets=targets;self.recovery=recovery }
    public func resolve(among devices:[DeviceKey]) throws -> [DeviceKey] {
        guard !targets.isEmpty else { throw BridgeFailure("请至少选择一块屏幕") }
        var result:[DeviceKey]=[]
        for target in targets {
            let matches=devices.filter { $0.uuid==target.uuid && $0.location==target.location }
            guard matches.count==1,let device=matches.first,ControlPolicy.canWrite(device,among:devices),!result.contains(device) else { throw BridgeFailure("预设中的显示器未连接、接口已改变或身份不唯一，请重新选择") }
            result.append(device)
        }
        guard result.count<devices.count else { throw BridgeFailure("至少需要保留一块正在输出的屏幕") }
        return result
    }
}
public struct BridgePollPolicy {
    public private(set) var delay:Double=2
    public init() {}
    public mutating func failed() { delay=min(30,delay*2) }
    public mutating func succeeded() { delay=2 }
}
