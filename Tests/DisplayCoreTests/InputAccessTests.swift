import XCTest
@testable import DisplayCore
final class InputAccessTests: XCTestCase {
    let target=DeviceKey(id:4,uuid:"monitor-a",location:"port-a")
    let verified=[VerifiedInput(uuid:"monitor-a",location:"port-a",value:18,label:"另一台主机")]
    func testManuallyVerifiedInputRemainsAvailableWithoutReadback() {
        XCTAssertTrue(InputAccess.allows(target:target,live:[target],readable:false,verified:verified,value:18))
        XCTAssertFalse(InputAccess.allows(target:target,live:[target],readable:false,verified:verified,value:17))
    }
    func testVerificationCannotLeakToAnotherDeviceOrAmbiguousIdentity() {
        let other=DeviceKey(id:5,uuid:"monitor-b",location:"port-b")
        XCTAssertFalse(InputAccess.allows(target:other,live:[target,other],readable:false,verified:verified,value:18))
        XCTAssertFalse(InputAccess.allows(target:target,live:[target,target],readable:false,verified:verified,value:18))
        XCTAssertFalse(InputAccess.allows(target:target,live:[],readable:true,verified:verified,value:18))
    }
    func testReadableDeviceStillRestrictsCommandsToKnownInputs() {
        XCTAssertTrue(InputAccess.allows(target:target,live:[target],readable:true,verified:[],value:17))
        XCTAssertFalse(InputAccess.allows(target:target,live:[target],readable:true,verified:[],value:255))
    }
}

extension InputAccessTests {
    func testRelocationRequiresHardwareFingerprintAndUniqueLiveUUID() {
        var rule=verified[0]
        let moved=DeviceKey(id:9,uuid:target.uuid,location:"port-b")
        XCTAssertNil(rule.bound(to:moved,vendor:1,model:2,live:[moved]))
        rule.vendor=1;rule.model=2
        XCTAssertEqual(rule.bound(to:moved,vendor:1,model:2,live:[moved])?.location,moved.location)
        XCTAssertNil(rule.bound(to:moved,vendor:1,model:3,live:[moved]))
        XCTAssertNil(rule.bound(to:moved,vendor:1,model:2,live:[target,moved]))
    }
}
