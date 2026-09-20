import XCTest
@testable import DisplayCore
final class CardGridMetricsTests:XCTestCase {
    func testUnboundedSwiftUIProposalsAreFinite() {
        for width:Double? in [nil,.infinity,.nan,-.infinity,0,Double.greatestFiniteMagnitude] {
            let m=CardGridMetrics(proposedWidth:width,itemCount:4)
            XCTAssertTrue(m.width.isFinite)
            XCTAssertTrue(m.cellWidth.isFinite)
            XCTAssertTrue((1...4).contains(m.columns))
        }
    }
    func testNarrowAndWideRows() {
        XCTAssertEqual(CardGridMetrics(proposedWidth:644,itemCount:4).columns,1)
        XCTAssertEqual(CardGridMetrics(proposedWidth:904,itemCount:4).columns,2)
        XCTAssertEqual(CardGridMetrics(proposedWidth:904,itemCount:4).cellWidth,444)
        XCTAssertEqual(CardGridMetrics(proposedWidth:nil,itemCount:0).columns,1)
    }
}
