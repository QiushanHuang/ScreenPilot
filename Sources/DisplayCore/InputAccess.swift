import Foundation
public struct VerifiedInput: Codable, Equatable, Sendable {
    public var uuid: String
    public var location: String
    public var value: Int
    public var label: String
    public init(uuid: String, location: String, value: Int, label: String) {
        self.uuid=uuid; self.location=location; self.value=value; self.label=label
    }
    public func matches(_ key: DeviceKey) -> Bool { uuid==key.uuid && location==key.location }
}
public enum InputAccess {
    public static func allows(target: DeviceKey, live: [DeviceKey], readable: Bool, verified: [VerifiedInput], value: Int) -> Bool {
        guard ControlPolicy.canWrite(target, among: live), [15,16,17,18,27].contains(value) else { return false }
        return readable || verified.contains { $0.matches(target) && $0.value == value }
    }
}
