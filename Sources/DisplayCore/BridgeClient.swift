import Foundation
import Network

public struct BridgeFailure: LocalizedError {
    public let message:String
    public var errorDescription:String? { message }
    public init(_ message:String) { self.message=message }
}
public struct BridgeResponse: Decodable, Sendable {
    public let ok:Bool
    public let ready:Bool?
    public let sent:Bool?
    public let error:String?
    public let arrivalID:String?
    public let arrivalTime:Double?
}
public enum BridgeAction: Equatable,Sendable {
    case health, switchToMac, arrivals
    var method:String { self == .switchToMac ? "POST" : "GET" }
    var path:String { self == .health ? "/health" : self == .arrivals ? "/usb-arrival" : "/switch-to-mac" }
    var timeout:TimeInterval { 8 }
}
public enum BridgeClient {
    public static func send(host:String,port:Int,key:Data,action:BridgeAction) async throws -> BridgeResponse {
        guard BridgeProtocol.isPrivateIPv4(host),(1024...65535).contains(port),key.count==32 else { throw BridgeFailure("配对地址、端口或密钥无效") }
        let permit=OperationPermit()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let exchange=BridgeExchange(host:host,port:port,key:key,action:action,permit:permit,continuation:continuation)
                exchange.start()
            }
        } onCancel: { permit.cancel() }
    }
}
private final class BridgeExchange: @unchecked Sendable {
    let queue=DispatchQueue(label:"studio.qiushan.screenpilot.bridge")
    let connection:NWConnection
    let key:Data,action:BridgeAction,permit:OperationPermit,nonce:String
    let host:String,port:Int
    var continuation:CheckedContinuation<BridgeResponse,Error>?
    var data=Data()
    var timer:DispatchSourceTimer?
    init(host:String,port:Int,key:Data,action:BridgeAction,permit:OperationPermit,continuation:CheckedContinuation<BridgeResponse,Error>) {
        self.host=host; self.port=port; self.key=key; self.action=action; self.permit=permit; self.continuation=continuation
        nonce=UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        connection=NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:UInt16(port))!,using:.tcp)
    }
    func start() {
        queue.async {
            let began=Date()
            let timer=DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now()+0.25,repeating:0.25)
            timer.setEventHandler {
                if self.permit.isCancelled { self.finish(.failure(CancellationError())) }
                else if Date().timeIntervalSince(began)>self.action.timeout { self.finish(.failure(BridgeFailure("Windows 请求超时；可能已执行，请观察屏幕后再试"))) }
            }
            self.timer=timer; timer.resume()
            self.connection.stateUpdateHandler={ state in
                switch state {
                case .ready:self.sendRequest()
                case .failed(let error):self.finish(.failure(BridgeFailure("无法连接 Windows："+error.localizedDescription)))
                default:break
                }
            }
            self.connection.start(queue:self.queue)
        }
    }
    func sendRequest() {
        let stamp=String(Int(Date().timeIntervalSince1970))
        let signature=BridgeProtocol.signature(key:key,timestamp:stamp,nonce:nonce,method:action.method,path:action.path)
        let request="\(action.method) \(action.path) HTTP/1.1\r\nHost: \(host):\(port)\r\nContent-Length: 0\r\nX-SP-Time: \(stamp)\r\nX-SP-Nonce: \(nonce)\r\nX-SP-Signature: \(signature)\r\nConnection: close\r\n\r\n"
        connection.send(content:Data(request.utf8),completion:.contentProcessed { error in
            if let error { self.finish(.failure(error)) } else { self.receive() }
        })
    }
    func receive() {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) { bytes,_,complete,error in
            if let bytes { self.data.append(bytes) }
            if self.data.count>8192 { self.finish(.failure(BridgeFailure("Windows 返回数据超出限制"))); return }
            if self.parse() { return }
            if let error { self.finish(.failure(error)) }
            else if complete { self.finish(.failure(BridgeFailure("Windows 提前关闭连接，请检查配对 Mac 地址和程序状态"))) }
            else { self.receive() }
        }
    }
    func parse() -> Bool {
        guard let separator=data.range(of:Data("\r\n\r\n".utf8)) else { return false }
        guard let text=String(data:data[..<separator.lowerBound],encoding:.utf8) else { finish(.failure(BridgeFailure("响应头无效"))); return true }
        let lines=text.components(separatedBy:"\r\n"), first=lines[0].split(separator:" ")
        guard first.count>=2,first[0].hasPrefix("HTTP/1."),let status=Int(first[1]) else { finish(.failure(BridgeFailure("响应状态无效"))); return true }
        var headers:[String:String]=[:]
        for line in lines.dropFirst() {
            guard let colon=line.firstIndex(of:":") else { finish(.failure(BridgeFailure("响应头无效"))); return true }
            let name=line[..<colon].lowercased()
            guard headers[name]==nil else { finish(.failure(BridgeFailure("响应头重复"))); return true }
            headers[name]=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
        }
        guard headers["transfer-encoding"]==nil,let raw=headers["content-length"],let length=Int(raw),(0...4096).contains(length) else { finish(.failure(BridgeFailure("响应长度无效"))); return true }
        guard data.count>=separator.upperBound+length else { return false }
        let body=Data(data[separator.upperBound..<(separator.upperBound+length)])
        let expected=BridgeProtocol.responseSignature(key:key,nonce:nonce,status:status,body:body)
        guard let signature=headers["x-sp-response"],constantTimeEqual(expected,signature) else { finish(.failure(BridgeFailure("Windows 响应校验失败，请重新配对"))); return true }
        do {
            let reply=try JSONDecoder().decode(BridgeResponse.self,from:body)
            guard status==200,reply.ok else {
                let reason=reply.error=="unknown_action" ? "Windows 程序需要升级" : reply.error=="authentication_failed" ? "请求认证失败，请检查配对及两台电脑的时间" : "Windows 未能控制选定显示器，请检查连接及程序输出"
                throw BridgeFailure(reason)
            }
            guard action.method == "GET" ? reply.ready==true : reply.sent==true else { throw BridgeFailure("Windows 返回了不完整的执行状态") }
            finish(.success(reply))
        } catch { finish(.failure(error)) }
        return true
    }
    func constantTimeEqual(_ a:String,_ b:String)->Bool {
        let x=Array(a.utf8),y=Array(b.utf8); guard x.count==y.count else { return false }
        return zip(x,y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }==0
    }
    func finish(_ result:Result<BridgeResponse,Error>) {
        guard let c=continuation else { return }
        continuation=nil; timer?.setEventHandler {}; timer?.cancel(); timer=nil
        connection.stateUpdateHandler=nil; connection.cancel(); c.resume(with:result)
    }
}
