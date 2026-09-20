import XCTest
@testable import DisplayCore
final class BridgeTests: XCTestCase {
    func testSignedReplyMatchesIndependentVector() {
        XCTAssertEqual(BridgeProtocol.responseSignature(key:Data((0..<32).map(UInt8.init)),nonce:"0123456789abcdef0123456789abcdef",status:200,body:Data(#"{"ok":true,"sent":true}"#.utf8)),"0b227e04e974972854f9c1858aa20f89149e0bb44ef045bbef78a222fea90c01")
    }
    func testEndpointStaysOnPrivateIPv4() {
        for host in ["192.168.31.10","10.0.0.2","172.16.0.1","172.31.255.254"] { XCTAssertTrue(BridgeProtocol.isPrivateIPv4(host)) }
        for host in ["8.8.8.8","127.0.0.1","172.32.0.1","192.168.1.999","192.168.1","example.com","192.168.1.1/path","010.0.0.1"] { XCTAssertFalse(BridgeProtocol.isPrivateIPv4(host)) }
    }
    func testCanonicalSignatureMatchesIndependentPythonVector() {
        let key=Data((0..<32).map(UInt8.init))
        let signature=BridgeProtocol.signature(key:key,timestamp:"1700000000",nonce:"0123456789abcdef0123456789abcdef",method:"POST",path:"/switch-to-mac")
        XCTAssertEqual(signature,"afedb0a5017bbcfc714de465e6b5d83a855364090768e96ef463607293a61372")
        XCTAssertNotEqual(signature,BridgeProtocol.signature(key:key,timestamp:"1700000000",nonce:"0123456789abcdef0123456789abcdef",method:"GET",path:"/health"))
        XCTAssertNil(BridgeProtocol.token("bad")); XCTAssertNil(BridgeProtocol.token(Data([1,2]).base64EncodedString()))
    }
}

final class PairingTests:XCTestCase {
    func testPairingRequiresPrivateAddressValidPortAndFullKey() throws {
        let key=Data(repeating:1,count:32).base64EncodedString()
        let pairing=try BridgePairing(code:"SP1|192.168.31.10|43871|"+key)
        XCTAssertEqual(pairing.host,"192.168.31.10"); XCTAssertEqual(pairing.port,43871)
        for code in ["SP1|8.8.8.8|43871|"+key,"SP1|192.168.31.10|70000|"+key,"SP1|192.168.31.10|43871|bad","SP1|192.168.31.10|43871|"+key+"|extra"] {
            XCTAssertThrowsError(try BridgePairing(code:code))
        }
    }
}
