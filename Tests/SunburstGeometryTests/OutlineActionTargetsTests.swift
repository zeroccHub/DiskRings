import XCTest
@testable import SunburstGeometry

final class OutlineActionTargetsTests: XCTestCase {
    typealias T = OutlineActionTargets

    /// First context-menu invoke: selection empty, clickedRow set → act on that row.
    func testFirstMenuInvokeUsesClickedRowWhenSelectionEmpty() {
        let rows = T.rowIndexes(selected: IndexSet(), clickedRow: 3, rowCount: 10)
        XCTAssertEqual(rows, IndexSet(integer: 3))
        XCTAssertTrue(T.shouldSelectClickedRow(selected: IndexSet(), clickedRow: 3, rowCount: 10))
    }

    /// Subsequent invoke / button path: non-empty selection wins (even if clickedRow differs).
    func testSelectionPreferredOverClickedRow() {
        var sel = IndexSet(); sel.insert(1); sel.insert(2)
        XCTAssertEqual(T.rowIndexes(selected: sel, clickedRow: 7, rowCount: 10), sel)
        XCTAssertFalse(T.shouldSelectClickedRow(selected: sel, clickedRow: 1, rowCount: 10),
                       "already selected — no promote")
        XCTAssertTrue(T.shouldSelectClickedRow(selected: sel, clickedRow: 7, rowCount: 10),
                      "right-click another row should promote")
    }

    /// Bottom button: clickedRow is typically -1; empty selection → nothing to add.
    func testButtonPathEmptySelectionAddsNothing() {
        XCTAssertTrue(T.rowIndexes(selected: IndexSet(), clickedRow: -1, rowCount: 5).isEmpty)
        XCTAssertFalse(T.shouldSelectClickedRow(selected: IndexSet(), clickedRow: -1, rowCount: 5))
    }

    func testClickedRowOutOfBoundsIgnored() {
        XCTAssertTrue(T.rowIndexes(selected: IndexSet(), clickedRow: 99, rowCount: 5).isEmpty)
        XCTAssertFalse(T.shouldSelectClickedRow(selected: IndexSet(), clickedRow: 99, rowCount: 5))
    }
}
