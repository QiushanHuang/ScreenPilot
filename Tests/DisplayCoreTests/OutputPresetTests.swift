import XCTest
@testable import DisplayCore
final class OutputPresetTests:XCTestCase {
 let a=DeviceKey(id:1,uuid:"A",location:"portA")
 let b=DeviceKey(id:2,uuid:"B",location:"portB")
 func testResolvesExactIdentityAndRejectsLastScreen() throws {
  let preset=OutputPreset(name:"External",targets:[OutputTarget(uuid:"B",location:"portB")],recovery:.manual)
  XCTAssertEqual(try preset.resolve(among:[a,b]),[b])
  XCTAssertThrowsError(try preset.resolve(among:[b]))
  XCTAssertThrowsError(try preset.resolve(among:[a,DeviceKey(id:3,uuid:"B",location:"other")]))
  XCTAssertThrowsError(try preset.resolve(among:[a,b,b]))
 }
 func testRoundTripAndNoTimeoutForManual() throws {
  let preset=OutputPreset(name:"Work",targets:[OutputTarget(uuid:"B",location:"portB")],recovery:.manual)
  let copy=try JSONDecoder().decode(OutputPreset.self,from:JSONEncoder().encode(preset))
  XCTAssertEqual(copy.targets,preset.targets)
  XCTAssertEqual(copy.recovery,.manual)
  XCTAssertTrue(OutputRecoveryMode.preview.automaticallyRestores)
  XCTAssertFalse(OutputRecoveryMode.manual.automaticallyRestores)
 }
 func testBackoffCapsAndResets() {
  var policy=BridgePollPolicy()
  XCTAssertEqual(policy.delay,2)
  for _ in 0..<10 { policy.failed() }
  XCTAssertEqual(policy.delay,30)
  policy.succeeded(); XCTAssertEqual(policy.delay,2)
 }
}
