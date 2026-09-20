import XCTest
@testable import DisplayCore
final class RemoteArrivalTests:XCTestCase {
 func testBaselineReplayAndExpiry() {
  var gate=RemoteArrivalGate()
  XCTAssertFalse(gate.accept(id:"boot",timestamp:0,now:100))
  XCTAssertTrue(gate.accept(id:"arrival",timestamp:101,now:102))
  XCTAssertFalse(gate.accept(id:"arrival",timestamp:101,now:103))
  XCTAssertFalse(gate.accept(id:"old",timestamp:102,now:120))
  XCTAssertFalse(gate.accept(id:"future",timestamp:150,now:120))
 }
}
