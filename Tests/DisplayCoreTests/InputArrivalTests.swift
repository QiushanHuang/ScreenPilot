import XCTest
@testable import DisplayCore
final class InputArrivalTests:XCTestCase {
    let none=InputPresence(keyboard:false,mouse:false)
    let keyboard=InputPresence(keyboard:true,mouse:false)
    let both=InputPresence(keyboard:true,mouse:true)
    func testStartupAndRemovalNeverTrigger() {
        var gate=InputArrivalGate()
        XCTAssertFalse(gate.observe(both,mode:.either,enabled:true,time:0))
        XCTAssertFalse(gate.observe(both,mode:.either,enabled:true,time:10))
        XCTAssertFalse(gate.observe(none,mode:.either,enabled:true,time:11))
        XCTAssertFalse(gate.observe(none,mode:.either,enabled:true,time:13))
    }
    func testArrivalDebouncesAndOnlyFiresOnce() {
        var gate=InputArrivalGate()
        _=gate.observe(none,mode:.keyboard,enabled:true,time:0)
        XCTAssertFalse(gate.observe(keyboard,mode:.keyboard,enabled:true,time:1))
        XCTAssertFalse(gate.observe(keyboard,mode:.keyboard,enabled:true,time:1.5))
        XCTAssertTrue(gate.observe(keyboard,mode:.keyboard,enabled:true,time:2.1))
        XCTAssertFalse(gate.observe(keyboard,mode:.keyboard,enabled:true,time:10))
    }
    func testBothNeedsBothAndEitherRecognizesSecondDeviceArrival() {
        var gate=InputArrivalGate()
        _=gate.observe(none,mode:.both,enabled:true,time:0)
        _=gate.observe(keyboard,mode:.both,enabled:true,time:1)
        XCTAssertFalse(gate.observe(keyboard,mode:.both,enabled:true,time:3))
        _=gate.observe(both,mode:.both,enabled:true,time:4)
        XCTAssertTrue(gate.observe(both,mode:.both,enabled:true,time:5.1))
        gate.reset()
        _=gate.observe(keyboard,mode:.either,enabled:true,time:10)
        _=gate.observe(both,mode:.either,enabled:true,time:11)
        XCTAssertTrue(gate.observe(both,mode:.either,enabled:true,time:12.1))
    }
}

extension InputArrivalTests {
    func testPortMoveAndSecondIdenticalReceiver() {
        let saved="1234:5678:00000011:6", current="1234:5678:00000022:6"
        XCTAssertFalse(InputArrivalGate.matches(current,selection:saved,anyPort:false))
        XCTAssertTrue(InputArrivalGate.matches(current,selection:saved,anyPort:true))
        XCTAssertFalse(InputArrivalGate.matches(current,selection:"1234:5678:00000011:2",anyPort:true))
        var gate=InputArrivalGate()
        XCTAssertFalse(gate.observe(keyboards:[saved],mice:[],mode:.either,enabled:true,time:0))
        XCTAssertFalse(gate.observe(keyboards:[saved,current],mice:[],mode:.either,enabled:true,time:3))
        XCTAssertTrue(gate.observe(keyboards:[saved,current],mice:[],mode:.either,enabled:true,time:4.1))
        XCTAssertFalse(gate.observe(keyboards:[saved],mice:[],mode:.either,enabled:true,time:8))
    }
}
