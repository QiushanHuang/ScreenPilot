import Foundation
public struct DeviceKey: Codable, Hashable, Sendable {
    public var id: UInt32
    public var uuid: String
    public var location: String
    public init(id: UInt32, uuid: String, location: String) { self.id = id; self.uuid = uuid; self.location = location }
}
public enum ControlPolicy {
    public static func canWrite(_ target: DeviceKey, among devices: [DeviceKey]) -> Bool {
        !target.uuid.isEmpty && !target.location.isEmpty &&
        devices.filter { $0.id == target.id }.count == 1 &&
        devices.filter { $0.uuid == target.uuid }.count == 1 &&
        devices.filter { $0.location == target.location }.count == 1 && devices.contains(target)
    }
    public static func rawBrightness(percent: Double, maximum: Int) -> Int? {
        guard percent.isFinite, maximum > 0, maximum <= 65535 else { return nil }
        return Int((min(100, max(0, percent)) * Double(maximum) / 100).rounded())
    }
    public static func brightnessPercent(current: Int, maximum: Int) -> Double? {
        guard maximum > 0, maximum <= 65535, current >= 0, current <= maximum else { return nil }
        return Double(current) / Double(maximum) * 100
    }
}
