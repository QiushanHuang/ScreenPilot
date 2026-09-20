import Foundation
import Darwin
public struct ProcessResult: Sendable { public var code: Int32; public var output: Data; public var timedOut: Bool }
public enum ProcessRunner {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval = 4) throws -> ProcessResult {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("screenpilot-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let process = Process(), ended = DispatchSemaphore(value: 0)
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        let expired = ended.wait(timeout: .now() + max(0.05, timeout)) == .timedOut
        if expired {
            if process.isRunning { process.terminate() }
            if ended.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 0.2)
            }
        }
        try? handle.synchronize()
        let data = (try? Data(contentsOf: file)) ?? Data()
        return ProcessResult(code: expired ? -1 : process.terminationStatus, output: data, timedOut: expired)
    }
}

public final class OperationPermit: @unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled=true; lock.unlock() }
}
