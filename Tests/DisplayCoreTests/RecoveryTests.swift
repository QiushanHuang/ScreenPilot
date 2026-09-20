import XCTest
@testable import DisplayCore
final class RecoveryTests: XCTestCase {
    func testPreviewExpiresButKeepRequiresLivingController() {
        XCTAssertFalse(RecoveryPolicy.shouldRestore(parentAlive:true,requested:false,kept:false,now:1,deadline:15))
        XCTAssertTrue(RecoveryPolicy.shouldRestore(parentAlive:true,requested:false,kept:false,now:15,deadline:15))
        XCTAssertFalse(RecoveryPolicy.shouldRestore(parentAlive:true,requested:false,kept:true,now:60,deadline:15))
        XCTAssertTrue(RecoveryPolicy.shouldRestore(parentAlive:false,requested:false,kept:true,now:2,deadline:15))
        XCTAssertTrue(RecoveryPolicy.shouldRestore(parentAlive:true,requested:true,kept:true,now:2,deadline:15))
    }
    func testTopologyVerificationDetectsLostRotationAndMainDisplay() throws {
        let a=Data(#"{"id":3,"uuid":"Q","active":1,"main":0,"x":2560,"y":-721,"width":1440,"height":2560,"rotation":90,"mode":43,"mirrors":0}"#.utf8)
        let b=Data(String(decoding:a,as:UTF8.self).replacingOccurrences(of:"\"rotation\":90",with:"\"rotation\":0").utf8)
        XCTAssertNotEqual(try JSONDecoder().decode(TopologyEntry.self,from:a),try JSONDecoder().decode(TopologyEntry.self,from:b))
    }
}
