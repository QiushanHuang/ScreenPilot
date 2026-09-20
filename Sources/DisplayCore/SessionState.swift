import Foundation
public struct ShadeState: Equatable {
    public var dimPercent: Double = 100
    public var blackedOut = false
    public init() {}
    public var opacity: Double { blackedOut ? 1 : 1 - min(100, max(5, dimPercent.isFinite ? dimPercent : 100)) / 100 }
    public mutating func restore() { dimPercent=100; blackedOut=false }
}
public enum BrightnessMode: String, Codable, Sendable { case hardware, software }
public struct SceneEntry: Codable, Equatable, Sendable {
    public var uuid: String
    public var location: String
    public var brightness: Double
    public var mode: BrightnessMode
    public var blackedOut: Bool
    public init(uuid: String, location: String, brightness: Double, mode: BrightnessMode, blackedOut: Bool) {
        self.uuid=uuid; self.location=location; self.brightness=brightness; self.mode=mode; self.blackedOut=blackedOut
    }
    public func applies(to devices: [DeviceKey]) -> DeviceKey? {
        guard brightness.isFinite, (0...100).contains(brightness),
              let match = devices.first(where: { $0.uuid == uuid && $0.location == location }),
              ControlPolicy.canWrite(match, among: devices) else { return nil }
        return match
    }
}
public struct DisplayScene: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var entries: [SceneEntry]
    public init(name: String, entries: [SceneEntry]) { self.name=name; self.entries=entries }
}
