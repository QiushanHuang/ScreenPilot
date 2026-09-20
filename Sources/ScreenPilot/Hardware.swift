import Foundation
import DisplayCore

struct BridgeDevice: Decodable {
    let id: UInt32
    let uuid: String
    let location: String
    let name: String
    let builtIn: Int
    var key: DeviceKey { DeviceKey(id: id, uuid: uuid, location: location) }
}
struct FeatureRead: Decodable {
    let ok: Bool
    let current: Int?
    let maximum: Int?
    let error: String?
    var percent: Double? {
        guard ok, let current, let maximum else { return nil }
        return ControlPolicy.brightnessPercent(current: current, maximum: maximum)
    }
}
struct BridgeReply: Decodable {
    let ok: Bool
    let error: String?
    let displays: [BridgeDevice]?
    let brightness: FeatureRead?
    let input: FeatureRead?
    let power: FeatureRead?
    let current: Int?
    let maximum: Int?
    let verified: Bool?
}
struct HardwareFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
final class HardwareClient {
    private let queue = DispatchQueue(label: "studio.qiushan.screenpilot.hardware", qos: .userInitiated)
    private let executable: URL
    init() {
        if let resources=Bundle.main.resourceURL, FileManager.default.isExecutableFile(atPath: resources.appendingPathComponent("DisplayBridge").path) {
            executable=resources.appendingPathComponent("DisplayBridge")
        } else {
            executable=URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/native/DisplayBridge")
        }
    }
    func call(_ command: String, key: DeviceKey? = nil, feature: String? = nil, value: Int? = nil) async throws -> BridgeReply {
        var arguments=[command]
        if let key { arguments += [String(key.id),key.uuid,key.location] }
        if let feature { arguments.append(feature) }
        if let value { arguments.append(String(value)) }
        let args=arguments, path=executable
        let permit=OperationPermit()
        return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !permit.isCancelled else { throw CancellationError() }
                    let result=try ProcessRunner.run(executable: path, arguments: args, timeout: 4)
                    guard !permit.isCancelled else { throw CancellationError() }
                    guard !result.timedOut else { throw HardwareFailure(message: "显示器响应超时，请检查连接后重新检测") }
                    let reply: BridgeReply
                    do { reply=try JSONDecoder().decode(BridgeReply.self, from: result.output) }
                    catch { throw HardwareFailure(message: "控制组件返回无效数据") }
                    guard result.code == 0, reply.ok else { throw HardwareFailure(message: reply.error ?? "显示器操作失败") }
                    continuation.resume(returning: reply)
                } catch { continuation.resume(throwing: error) }
            }
        }
        } onCancel: { permit.cancel() }
    }
}
