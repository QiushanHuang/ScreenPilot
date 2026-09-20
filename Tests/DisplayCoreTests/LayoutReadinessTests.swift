import XCTest
@testable import DisplayCore
final class LayoutReadinessTests:XCTestCase {
    func display(active:Int=1,mode:UInt32=73)->TopologyEntry {
        TopologyEntry(id:4,uuid:"target",active:active,main:1,x:0,y:0,width:2560,height:1440,rotation:0,mode:mode,mirrors:0)
    }
    func testPendingRecoveryAndChangingModesPreventSwitching() {
        var gate=LayoutReadiness()
        XCTAssertFalse(gate.observe([display()],target:"target",busy:true,uptime:0))
        XCTAssertFalse(gate.observe([display()],target:"target",busy:false,uptime:1))
        XCTAssertFalse(gate.observe([display(mode:74)],target:"target",busy:false,uptime:2))
        XCTAssertTrue(gate.observe([display(mode:74)],target:"target",busy:false,uptime:3.1))
        XCTAssertFalse(gate.observe([display(mode:74)],target:"target",busy:true,uptime:4))
    }
    func testMissingOrInactiveTargetNeverBecomesReady() {
        var gate=LayoutReadiness()
        XCTAssertFalse(gate.observe([],target:"target",busy:false,uptime:0))
        XCTAssertFalse(gate.observe([display(active:0)],target:"target",busy:false,uptime:10))
        XCTAssertFalse(gate.observe([display(active:0)],target:"target",busy:false,uptime:20))
    }
}
