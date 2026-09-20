import XCTest
@testable import DisplayCore
final class SessionTests: XCTestCase {
    func testBlackoutPreservesDimButEmergencyRestoreRemovesBoth() {
        var s = ShadeState(); s.dimPercent=40
        XCTAssertEqual(s.opacity, 0.6, accuracy: 0.001)
        s.blackedOut=true; XCTAssertEqual(s.opacity, 1)
        s.blackedOut=false; XCTAssertEqual(s.opacity, 0.6, accuracy: 0.001)
        s.blackedOut=true; s.restore()
        XCTAssertEqual(s.opacity, 0); XCTAssertFalse(s.blackedOut)
    }
    func testSceneCannotApplyToReplacedPortOrAmbiguousUUID() throws {
        let e = SceneEntry(uuid: "A", location: "port1", brightness: 50, mode: .software, blackedOut: true)
        let device = DeviceKey(id: 99, uuid: "A", location: "port1")
        XCTAssertEqual(e.applies(to: [device]), device)
        XCTAssertNil(e.applies(to: [DeviceKey(id: 99, uuid: "B", location: "port1")]))
        XCTAssertNil(e.applies(to: [device,DeviceKey(id: 100, uuid: "A", location: "port2")]))
        var invalid=e; invalid.brightness=500
        XCTAssertNil(invalid.applies(to: [device]))
        let scene = DisplayScene(name: "阅读", entries: [e])
        let data = try JSONEncoder().encode(scene)
        XCTAssertEqual(try JSONDecoder().decode(DisplayScene.self, from: data).entries,[e])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("power")); XCTAssertFalse(json.contains("input"))
    }
    func testProcessExitStatusAndTimeoutAreNotReportedAsSuccess() throws {
        let result = try ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo device-error; exit 7"])
        XCTAssertEqual(result.code,7)
        XCTAssertTrue(String(decoding:result.output,as:UTF8.self).contains("device-error"))
        let start=Date()
        let hung = try ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.15)
        XCTAssertTrue(hung.timedOut); XCTAssertNotEqual(hung.code,0)
        XCTAssertLessThan(Date().timeIntervalSince(start),2)
    }
}

final class CancellationTests: XCTestCase {
    func testCancellationRemainsSetAcrossQueueBoundary() {
        let permit=OperationPermit()
        XCTAssertFalse(permit.isCancelled)
        permit.cancel()
        let finished=expectation(description:"queue sees cancellation")
        DispatchQueue.global().async { XCTAssertTrue(permit.isCancelled); finished.fulfill() }
        wait(for:[finished],timeout:1)
        permit.cancel(); XCTAssertTrue(permit.isCancelled)
    }
}
