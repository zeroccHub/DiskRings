import XCTest
@testable import SunburstGeometry

final class ResultRowLayoutTests: XCTestCase {
    typealias L = ResultRowLayout
    let longPath = "Users/mac387/Library/Containers/com.tencent.WeWorkMac/Data/Library/Application Support/WXWork/Data/" + String(repeating: "deep/", count: 200)

    func testLongPathRowNeverExceedsRowHeight() {
        for search in [true, false] {
            for text in ["a", longPath, String(repeating: "其他很长的中文名字", count: 100)] {
                XCTAssertLessThanOrEqual(L.contentHeight(isSearchHit: search, text: text), L.rowHeight(isSearchHit: search))
            }
        }
        XCTAssertEqual(L.contentHeight(isSearchHit: true, text: longPath), L.contentHeight(isSearchHit: true, text: "x"))
    }

    func testEveryLineSingleLineAndTruncated() {
        for search in [true, false] {
            for line in L.lines(isSearchHit: search) {
                XCTAssertEqual(line.maxLines, 1); XCTAssertFalse(line.wraps); XCTAssertTrue(line.singleLineMode)
            }
        }
        XCTAssertEqual(L.name.truncation, .tail)
        XCTAssertEqual(L.path.truncation, .middle)
        XCTAssertLessThan(L.path.fontSize, L.name.fontSize)
        XCTAssertEqual(L.lines(isSearchHit: true).count, 2)
        XCTAssertEqual(L.lines(isSearchHit: false).count, 1)
    }

    func testBadgeReservesItsOwnSlot() {
        let without = L.nameWidth(cellWidth: 300, leading: 40, badgeWidth: 0)
        let with = L.nameWidth(cellWidth: 300, leading: 40, badgeWidth: 50)
        XCTAssertEqual(without - with, 50 + L.badgeGap)
        XCTAssertEqual(L.nameWidth(cellWidth: 60, leading: 40, badgeWidth: 50), 0)
    }

    func testTooltipIsFullPath() {
        XCTAssertEqual(L.tooltip(name: "backup", relativePath: "Users/mac387/Downloads"), "Users/mac387/Downloads/backup")
        XCTAssertEqual(L.tooltip(name: "x", relativePath: "/"), "x")
    }
}
