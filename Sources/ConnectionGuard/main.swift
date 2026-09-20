import Foundation
import Darwin
import DisplayCore

// This process outlives the UI and restores on preview timeout, an explicit
// request, or loss of its parent. It has no DDC or network control path.
let args=CommandLine.arguments
if args.count != 5 { fputs("Expected helper lease controlDirectory parentPID\n",stderr); exit(2) }
let helper=URL(fileURLWithPath:args[1]), leaseURL=URL(fileURLWithPath:args[2]), control=URL(fileURLWithPath:args[3])
guard let parent=Int32(args[4]), parent>1, let original=try? Data(contentsOf:leaseURL),
      let lease=try? JSONDecoder().decode(TopologyLease.self,from:original) else { exit(2) }
let initialDeadline=Date().timeIntervalSince1970+15
let ready=control.appendingPathComponent("ready"), keep=control.appendingPathComponent("keep"), restore=control.appendingPathComponent("restore")
let resultURL=control.appendingPathComponent("result.json")
func refreshLeaseTimestamp() throws {
    var object=try JSONSerialization.jsonObject(with:Data(contentsOf:leaseURL)) as! [String:Any]
    if object["originalCreated"]==nil { object["originalCreated"]=object["created"] }
    // The same guard created for this lease renews it; native code separately
    // verifies boot identity and refuses a different live display UUID.
    object["created"]=Date().timeIntervalSince1970
    try JSONSerialization.data(withJSONObject:object,options:.sortedKeys).write(to:leaseURL,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:leaseURL.path)
}
func call(_ command: String) throws -> TopologyReply {
    let arguments=command=="snapshot" ? [command] : [command,leaseURL.path]
    let r=try ProcessRunner.run(executable:helper,arguments:arguments,timeout:6)
    let reply=try JSONDecoder().decode(TopologyReply.self,from:r.output)
    if r.timedOut || r.code != 0 || !reply.ok { throw NSError(domain:"ConnectionGuard",code:1,userInfo:[NSLocalizedDescriptionKey:reply.error ?? "恢复请求失败或超时"]) }
    return reply
}
func same(_ list:[TopologyEntry]?) -> Bool {
    guard let list else { return false }
    return list.sorted { $0.uuid<$1.uuid } == lease.displays.sorted { $0.uuid<$1.uuid }
}
try Data("armed".utf8).write(to:ready,options:.atomic)
while true {
    let deadline=(try? String(contentsOf:control.appendingPathComponent("deadline"),encoding:.utf8)).flatMap(Double.init) ?? initialDeadline
    let alive=kill(parent,0)==0 || errno==EPERM
    if RecoveryPolicy.shouldRestore(parentAlive:alive,requested:FileManager.default.fileExists(atPath:restore.path),kept:FileManager.default.fileExists(atPath:keep.path),now:Date().timeIntervalSince1970,deadline:deadline) { break }
    Thread.sleep(forTimeInterval:0.5)
}
try Data("restoring".utf8).write(to:control.appendingPathComponent("restoring"),options:.atomic)
var result:[String:Any]
do {
    try refreshLeaseTimestamp()
    // Reconnection and layout restoration must be separate transactions.
    var current=try call("snapshot")
    if !same(current.displays) { _=try call("restore"); Thread.sleep(forTimeInterval:0.6); current=try call("snapshot") }
    if !same(current.displays) { _=try call("restore"); Thread.sleep(forTimeInterval:0.3); current=try call("snapshot") }
    result=["ok":same(current.displays),"layoutRestored":same(current.displays)]
    if !same(current.displays) { result["error"]="屏幕已尝试连接，但布局尚未完全恢复" }
} catch { result=["ok":false,"layoutRestored":false,"error":error.localizedDescription] }
try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(to:resultURL,options:.atomic)
exit(result["ok"] as? Bool == true ? 0 : 1)
