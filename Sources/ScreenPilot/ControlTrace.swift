import Foundation

enum ControlTrace {
    private static let queue=DispatchQueue(label:"studio.qiushan.screenpilot.trace")
    static func log(_ event:String,operation:String,fields:[String:Any]=[:]) {
        var record=fields; record["event"]=event; record["operation"]=operation
        record["time"]=ISO8601DateFormatter().string(from:Date()); record["pid"]=ProcessInfo.processInfo.processIdentifier
        guard JSONSerialization.isValidJSONObject(record),let data=try? JSONSerialization.data(withJSONObject:record,options:.sortedKeys) else { return }
        queue.async {
            let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScreenPilot/Logs")
            do {
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let date=String(ISO8601DateFormatter().string(from:Date()).prefix(10))
                let file=root.appendingPathComponent("control-\(date).jsonl")
                if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil,attributes:[.posixPermissions:0o600]) }
                let handle=try FileHandle(forWritingTo:file); defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf:data); try handle.write(contentsOf:Data([10]))
            } catch { /* Logging failure must not issue or repeat a display command. */ }
        }
    }
}
