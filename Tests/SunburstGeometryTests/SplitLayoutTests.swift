import XCTest
@testable import SunburstGeometry

final class SplitLayoutTests: XCTestCase {
    func testWindowMinimumFitsChartAndList() {
        XCTAssertEqual(SplitLayout.minimumSplitWidth, 881)
        XCTAssertGreaterThanOrEqual(SplitLayout.windowMinWidth, SplitLayout.minimumSplitWidth)
    }
    func testInitialWidthUsesSpecRatio() {
        XCTAssertEqual(SplitLayout.initialListWidth(total: 1280), 436)
        XCTAssertEqual(SplitLayout.initialListWidth(total: 1024), 436)          // chart 587 ≥ 520
        XCTAssertEqual(SplitLayout.initialListWidth(total: 960), 436)           // chart 523
        XCTAssertEqual(SplitLayout.initialListWidth(total: 900), 379)           // chart kept at 520
        XCTAssertEqual(SplitLayout.dividerPosition(total: 1024, listWidth: 436), 587)
    }
    func testListNeverCollapses() {
        for total in stride(from: 0.0, through: 3000, by: 37) {
            for proposed in [-50.0, 0, 100, 360, 436, 480, 900] {
                let w = SplitLayout.clampList(proposed, total: total)
                XCTAssertGreaterThanOrEqual(w, SplitLayout.listMin)
                XCTAssertLessThanOrEqual(w, SplitLayout.listMax)
            }
        }
        XCTAssertTrue(SplitLayout.isListTooNarrow(listWidth: 0, collapsed: false))
        XCTAssertTrue(SplitLayout.isListTooNarrow(listWidth: 436, collapsed: true))
        XCTAssertFalse(SplitLayout.isListTooNarrow(listWidth: 360, collapsed: false))
    }
    func testAutosaveNameBumped() {
        XCTAssertEqual(SplitLayout.windowAutosaveName, "DiskRings.MainWindow.v4")
    }
}
