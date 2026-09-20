import XCTest
@testable import DisplayCore
final class PolicyTests: XCTestCase {
    let a = DeviceKey(id: 1, uuid: "same-model-A", location: "/port/A")
    let b = DeviceKey(id: 2, uuid: "same-model-B", location: "/port/B")
    func testWriteRequiresExactLiveIdentity() {
        XCTAssertTrue(ControlPolicy.canWrite(a, among: [a,b]))
        XCTAssertFalse(ControlPolicy.canWrite(a, among: [b]))
        XCTAssertFalse(ControlPolicy.canWrite(a, among: [DeviceKey(id: 1, uuid: "replacement", location: "/port/A")]))
        XCTAssertFalse(ControlPolicy.canWrite(a, among: [a,a]))
        XCTAssertFalse(ControlPolicy.canWrite(a, among: [a,DeviceKey(id: 3, uuid: a.uuid, location: "/port/C")]))
        XCTAssertFalse(ControlPolicy.canWrite(DeviceKey(id: 4, uuid: "", location: ""), among: []))
    }
    func testBrightnessUsesDeviceMaximumAndRejectsInvalidReadback() {
        XCTAssertEqual(ControlPolicy.rawBrightness(percent: 25, maximum: 255), 64)
        XCTAssertEqual(ControlPolicy.rawBrightness(percent: 120, maximum: 100), 100)
        XCTAssertEqual(ControlPolicy.rawBrightness(percent: -10, maximum: 100), 0)
        XCTAssertNil(ControlPolicy.rawBrightness(percent: .nan, maximum: 100))
        XCTAssertNil(ControlPolicy.rawBrightness(percent: 50, maximum: 0))
        XCTAssertEqual(ControlPolicy.brightnessPercent(current: 128, maximum: 256), 50)
        XCTAssertNil(ControlPolicy.brightnessPercent(current: 101, maximum: 100))
        XCTAssertNil(ControlPolicy.brightnessPercent(current: -1, maximum: 100))
    }
}
