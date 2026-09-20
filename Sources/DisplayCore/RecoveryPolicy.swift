import Foundation
public enum RecoveryPolicy {
    public static func shouldRestore(parentAlive: Bool, requested: Bool, kept: Bool, now: TimeInterval, deadline: TimeInterval) -> Bool { !parentAlive || requested || (!kept && now >= deadline) }
}
public struct TopologyEntry: Codable, Equatable, Sendable {
    public let id: UInt32
    public let uuid: String
    public let active: Int
    public let main: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let rotation: Double
    public let mode: UInt32
    public let mirrors: UInt32
}
public struct TopologyLease: Decodable { public let displays: [TopologyEntry] }
public struct TopologyReply: Decodable { public let ok: Bool; public let error: String?; public let displays: [TopologyEntry]? }
