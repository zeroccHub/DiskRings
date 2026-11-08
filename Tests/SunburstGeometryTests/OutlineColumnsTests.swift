import XCTest
@testable import SunburstGeometry

final class OutlineColumnsTests: XCTestCase {
    typealias C = OutlineColumns
    func testNarrowestPaneShowsWidestSizeAndNameTakesTheRest() {
        let pane = SplitLayout.listMin                    // 360
        XCTAssertEqual(pane, 360)
        let w = C.widths(pane: pane)
        XCTAssertGreaterThanOrEqual(w.size, 72)
        XCTAssertGreaterThanOrEqual(w.size, C.estimatedWidestSizeText + C.sizePadding)   // "999.9 GB" fits
        XCTAssertEqual(w.name, (pane - w.size - w.share - 3 * C.intercellSpacing - C.styleInset).rounded(.down))
        XCTAssertLessThanOrEqual(w.total, pane, "no horizontal overflow at 360")
        XCTAssertGreaterThanOrEqual(w.name, C.nameMinimum)
    }
    func testSizeUsesRealMeasurementWhenWider() {
        XCTAssertEqual(C.sizeWidth(measuredText: 70), 82)
        XCTAssertEqual(C.sizeWidth(measuredText: 30), max(72, (C.estimatedWidestSizeText + 12).rounded(.up)))
    }
    func testNameAbsorbsResizeFixedColumnsDont() {
        let a = C.widths(pane: 360), b = C.widths(pane: 480)
        XCTAssertEqual(b.name - a.name, 120); XCTAssertEqual(a.size, b.size); XCTAssertEqual(a.share, b.share)
        for p in stride(from: 360.0, through: 480, by: 7) { XCTAssertLessThanOrEqual(C.widths(pane: p).total, p) }
    }
    func testOldConfigOverflowedThePane() {
        // The shipped config (name 300 fixed + 68 + 56 + inset/spacing) needed more than 360/436.
        XCTAssertGreaterThan(300 + 68 + 56 + 3 * 3 + C.styleInset, 436.0)
    }
    func testTruncationByNameKind() {
        XCTAssertEqual(C.truncation(forName: "Profiles › 5C7E08F54B22E3A3A59CD66FD0000"), .middle)
        XCTAssertEqual(C.truncation(forName: "cefcache"), .tail)
    }
}
