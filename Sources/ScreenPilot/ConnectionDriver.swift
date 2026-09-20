import Foundation
import DisplayCore

@MainActor final class ConnectionDriver {
    private(set) var directory: URL?
    private(set) var lease: URL?
    private var guardProcess: Process?
    private var logHandle: FileHandle?
    private var preparing=false
    private let queue=DispatchQueue(label:"studio.qiushan.screenpilot.connection",qos:.userInitiated)
    private var helper: URL {
        let resource=Bundle.main.resourceURL?.appendingPathComponent("DisplayConnection")
        return resource.flatMap { FileManager.default.isExecutableFile(atPath:$0.path) ? $0 : nil } ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/native/ConnectionProbe")
    }
    private var guardExecutable: URL {
        let resource=Bundle.main.resourceURL?.appendingPathComponent("ConnectionGuard")
        return resource.flatMap { FileManager.default.isExecutableFile(atPath:$0.path) ? $0 : nil } ?? Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("ConnectionGuard")
    }
    private func call(_ args:[String]) async throws -> TopologyReply {
        let exe=helper
        return try await withCheckedThrowingContinuation { c in
            queue.async {
                do {
                    let r=try ProcessRunner.run(executable:exe,arguments:args,timeout:6)
                    let reply=try JSONDecoder().decode(TopologyReply.self,from:r.output)
                    guard !r.timedOut,r.code==0,reply.ok else { throw HardwareFailure(message:reply.error ?? "显示器连接操作超时") }
                    c.resume(returning:reply)
                } catch { c.resume(throwing:error) }
            }
        }
    }
    func prepare() async throws {
        if directory != nil { return }
        guard !preparing else { throw HardwareFailure(message:"正在准备恢复程序") }
        preparing=true; defer { preparing=false }
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScreenPilot/Recovery",isDirectory:true)
        let dir=root.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let snapshot=dir.appendingPathComponent("lease.json")
        _=try await call(["capture",snapshot.path])
        directory=dir; lease=snapshot
        do { try launchGuard() } catch { directory=nil; lease=nil; throw error }
        for _ in 0..<30 {
            if FileManager.default.fileExists(atPath:dir.appendingPathComponent("ready").path) { return }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        requestRestore(); throw HardwareFailure(message:"独立恢复程序未就绪，未关闭屏幕")
    }
    private func launchGuard() throws {
        guard let dir=directory,let lease else { return }
        let p=Process(); p.executableURL=guardExecutable
        p.arguments=[helper.path,lease.path,dir.path,String(ProcessInfo.processInfo.processIdentifier)]
        let log=dir.appendingPathComponent("guard-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])
        logHandle=try FileHandle(forWritingTo:log); p.standardOutput=logHandle; p.standardError=logHandle
        try p.run(); guardProcess=p
    }
    func disable(_ uuid:String) async throws {
        guard let lease else { throw HardwareFailure(message:"没有恢复记录") }
        try refreshLease()
        try armPreview()
        _=try await call(["disable",lease.path,uuid])
    }
    private func refreshLease() throws {
        guard let lease else { return }
        guard var object=try JSONSerialization.jsonObject(with:Data(contentsOf:lease)) as? [String:Any] else { throw HardwareFailure(message:"恢复记录无效") }
        if object["originalCreated"]==nil { object["originalCreated"]=object["created"] }
        object["created"]=Date().timeIntervalSince1970
        try JSONSerialization.data(withJSONObject:object).write(to:lease,options:.atomic)
    }
    private func armPreview() throws {
        guard let directory else { return }
        guard !FileManager.default.fileExists(atPath:directory.appendingPathComponent("restoring").path) else { throw HardwareFailure(message:"正在恢复显示器，请稍后再关闭") }
        try Data(String(Date().timeIntervalSince1970+15).utf8).write(to:directory.appendingPathComponent("deadline"),options:.atomic)
        let keep=directory.appendingPathComponent("keep")
        if FileManager.default.fileExists(atPath:keep.path) { try FileManager.default.removeItem(at:keep) }
    }
    func enable(_ uuid:String) async throws {
        guard let lease else { throw HardwareFailure(message:"没有恢复记录") }
        try refreshLease()
        _=try await call(["enable",lease.path,uuid])
        let result=try await call(["snapshot"])
        guard result.displays?.contains(where: { $0.uuid==uuid && $0.active != 0 }) == true else { throw HardwareFailure(message:"重新连接后尚未检测到此屏幕") }
    }
    func snapshot() async throws -> [TopologyEntry] {
        guard let displays=try await call(["snapshot"]).displays else { throw HardwareFailure(message:"没有显示布局回读") }
        return displays
    }
    func setRecovery(_ mode:OutputRecoveryMode) throws {
        if mode.automaticallyRestores { try armPreview() } else { try keepOff() }
    }
    func keepOff() throws {
        guard let directory else { return }
        guard !FileManager.default.fileExists(atPath:directory.appendingPathComponent("restoring").path) else { throw HardwareFailure(message:"恢复已经开始，请等待后重新关闭") }
        try Data("keep".utf8).write(to:directory.appendingPathComponent("keep"),options:.atomic)
    }
    func requestRestore() {
        guard let directory else { return }
        try? Data("restore".utf8).write(to:directory.appendingPathComponent("restore"),options:.atomic)
    }
    func retryRestore() throws {
        guard let directory else { return }
        if guardProcess?.isRunning != true {
            let result=directory.appendingPathComponent("result.json")
            if FileManager.default.fileExists(atPath:result.path) { try FileManager.default.moveItem(at:result,to:directory.appendingPathComponent("result-\(UUID().uuidString).json")) }
            try launchGuard()
        }
        requestRestore()
    }
    func result() -> (ok:Bool,error:String?)? {
        guard let directory,let data=try? Data(contentsOf:directory.appendingPathComponent("result.json")),
              let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return nil }
        return (object["ok"] as? Bool == true,object["error"] as? String)
    }
    func finish() { directory=nil; lease=nil; guardProcess=nil; try? logHandle?.close(); logHandle=nil }
}
