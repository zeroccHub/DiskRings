import XCTest
@testable import DiskScanCore

final class BasketDragTests: XCTestCase {
    func file(_ n: String, _ s: UInt64) -> FileNode {
        FileNode(name: n, kind: .file, logicalSize: s, allocatedSize: s, actualSize: s)
    }
    func dir(_ n: String, _ k: [FileNode]) -> FileNode {
        let d = FileNode(name: n, kind: .directory); d.setChildren(k); return d
    }

    func testValidDropAcceptsUnprotected() {
        let e = BasketDrag.Evaluation.evaluate(paths: ["/a", "/b"]) { $0 == "/b" }
        XCTAssertEqual(e.accepted, ["/a"])
        XCTAssertEqual(e.refused, ["/b"])
        XCTAssertTrue(e.canDrop)
        XCTAssertEqual(BasketDrag.highlight(isOverZone: true, evaluation: e), .accepting)
    }

    func testProtectedRefusedNoAcceptHighlight() {
        let e = BasketDrag.Evaluation.evaluate(paths: ["/sip"]) { _ in true }
        XCTAssertTrue(e.accepted.isEmpty)
        XCTAssertFalse(e.canDrop)
        XCTAssertEqual(BasketDrag.highlight(isOverZone: true, evaluation: e), .rejecting)
        XCTAssertEqual(BasketDrag.highlight(isOverZone: false, evaluation: e), .idle)
    }

    func testMultiSelectPathsPreserveOrderAndUniqueness() {
        let e = BasketDrag.Evaluation.evaluate(paths: ["/a", "/b", "/a", ""]) { _ in false }
        XCTAssertEqual(e.paths, ["/a", "/b"])
        XCTAssertEqual(e.accepted, ["/a", "/b"])
    }

    func testEncodeDecodeRoundTrip() {
        let raw = BasketDrag.encodePaths(["/Users/x/a", "/Users/x/b"])
        XCTAssertEqual(BasketDrag.decodePaths(raw), ["/Users/x/a", "/Users/x/b"])
    }

    func testResolveUnderRoot() {
        let root = dir("/Volumes/Data", [dir("Users", [dir("mac", [file("backup", 10)])])])
        root.aggregate()
        let n = BasketDrag.resolve(paths: [root.path + "/Users/mac/backup"], under: root)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].name, "backup")
    }

    func testNoDropHerePlaceholderInProductStrings() {
        // Gate also checks sources; this locks the constant list.
        for s in BasketDrag.forbiddenPlaceholders {
            XCTAssertFalse(s.isEmpty)
        }
        XCTAssertTrue(BasketDrag.forbiddenPlaceholders.contains("拖到这里"))
    }
}
