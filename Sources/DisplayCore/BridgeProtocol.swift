import Foundation
import CryptoKit
public enum BridgeProtocol {
    public static func isPrivateIPv4(_ host:String) -> Bool {
        let parts=host.split(separator:".",omittingEmptySubsequences:false)
        guard parts.count==4 else { return false }
        var octets:[Int]=[]
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n=Int(part), (0...255).contains(n), String(n)==part else { return false }
            octets.append(n)
        }
        return octets[0]==10 || (octets[0]==172 && (16...31).contains(octets[1])) || (octets[0]==192 && octets[1]==168)
    }
    public static func signature(key:Data,timestamp:String,nonce:String,method:String,path:String) -> String {
        let bytes=Data("\(timestamp)\n\(nonce)\n\(method)\n\(path)".utf8)
        return HMAC<SHA256>.authenticationCode(for:bytes,using:SymmetricKey(data:key)).map { String(format:"%02x",$0) }.joined()
    }
    public static func responseSignature(key:Data,nonce:String,status:Int,body:Data) -> String {
        var message=Data("\(nonce)\n\(status)\n".utf8); message.append(body)
        return HMAC<SHA256>.authenticationCode(for:message,using:SymmetricKey(data:key)).map { String(format:"%02x",$0) }.joined()
    }
    public static func token(_ base64:String) -> Data? {
        guard let data=Data(base64Encoded:base64),data.count==32 else { return nil }; return data
    }
}
public enum HostLayoutMode: String, Codable, CaseIterable { case keep, disconnect }

public struct BridgePairing {
    public let host:String
    public let port:Int
    public let key:Data
    public init(code:String) throws {
        let parts=code.trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:"|")
        guard parts.count==4,parts[0]=="SP1",BridgeProtocol.isPrivateIPv4(parts[1]),
              let port=Int(parts[2]),(1024...65535).contains(port),String(port)==parts[2],
              let key=BridgeProtocol.token(parts[3]) else { throw BridgeFailure("配对码无效，请复制 Windows 程序显示的完整 SP1 配对码") }
        self.host=parts[1]; self.port=port; self.key=key
    }
}
