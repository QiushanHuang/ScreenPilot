import XCTest
@testable import DisplayCore
final class BridgeIntegrationTests:XCTestCase {
    func testSignedRequestAndResponseAgainstPythonFixture() async throws {
        guard let host=ProcessInfo.processInfo.environment["SCREENPILOT_BRIDGE_TEST_HOST"] else { throw XCTSkip("Run with the local signed bridge fixture") }
        let key=Data((0..<32).map(UInt8.init))
        let health=try await BridgeClient.send(host:host,port:43872,key:key,action:.health)
        XCTAssertEqual(health.ready,true)
        let command=try await BridgeClient.send(host:host,port:43872,key:key,action:.switchToMac)
        XCTAssertEqual(command.sent,true)
        do { _=try await BridgeClient.send(host:host,port:43872,key:Data(repeating:255,count:32),action:.switchToMac); XCTFail("Unpaired key was accepted") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        do { _=try await BridgeClient.send(host:host,port:43872,key:key,action:.health); XCTFail("Forged response was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("校验失败")) }
        let arrival=try await BridgeClient.send(host:host,port:43872,key:key,action:.arrivals)
        XCTAssertEqual(arrival.arrivalID,"test-event")
        XCTAssertEqual(arrival.arrivalTime,123)
    }
}
