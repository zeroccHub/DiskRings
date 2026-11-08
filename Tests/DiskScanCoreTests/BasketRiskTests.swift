import XCTest
@testable import DiskScanCore

final class BasketRiskTests: XCTestCase {
    let home = "/Users/tester"
    let over50: UInt64 = 50 * 1024 * 1024 * 1024 + 1

    func testLibraryCachesIsNotHighRisk() {
        for p in [
            "/Users/tester/Library/Caches",
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Library/Caches",
            "/Library/Caches/foo",
        ] {
            let v = BasketRisk.classify(path: p, sizeBytes: 100, homeDirectory: home)
            XCTAssertFalse(v.isHighRisk, p)
            XCTAssertFalse(v.reasons.contains("library"), p)
        }
    }

    func testOtherLibraryIsHighRisk() {
        for p in [
            "/Users/tester/Library/Application Support/Foo",
            "/Users/tester/Library/Preferences",
            "/Library/LaunchDaemons",
        ] {
            let v = BasketRisk.classify(path: p, sizeBytes: 100, homeDirectory: home)
            XCTAssertTrue(v.isHighRisk, p)
            XCTAssertTrue(v.reasons.contains("library"), p)
        }
    }

    func testHiddenAndAppAreHighRisk() {
        XCTAssertTrue(BasketRisk.classify(path: "/Users/tester/.secret", sizeBytes: 1, homeDirectory: home).reasons.contains("hidden"))
        XCTAssertTrue(BasketRisk.classify(path: "/Applications/Xcode.app", sizeBytes: 1, homeDirectory: home).reasons.contains("appBundle"))
        XCTAssertTrue(BasketRisk.classify(path: "/Applications/Xcode.app/Contents", sizeBytes: 1, homeDirectory: home).reasons.contains("appBundle"))
    }

    func testOver50GBGetsWarning() {
        let v = BasketRisk.classify(path: "/Users/tester/Movies/huge.mov", sizeBytes: over50, homeDirectory: home)
        XCTAssertTrue(v.isHighRisk)
        XCTAssertTrue(v.reasons.contains("over50GB"))
        let small = BasketRisk.classify(path: "/Users/tester/Movies/clip.mov", sizeBytes: 1024, homeDirectory: home)
        XCTAssertFalse(small.isHighRisk)
    }

    func testLibraryStateHelper() {
        XCTAssertEqual(BasketRisk.libraryState(path: "/Library", homeDirectory: home), .library)
        XCTAssertEqual(BasketRisk.libraryState(path: "/Users/tester/Library/Caches/x", homeDirectory: home), .caches)
        XCTAssertEqual(BasketRisk.libraryState(path: "/Users/tester/Libraryx", homeDirectory: home), .none)
        XCTAssertEqual(BasketRisk.libraryState(path: "/Users/tester/Library", homeDirectory: ""), .none)
    }

    func testCachesPlusOver50StillHighRiskForSize() {
        let v = BasketRisk.classify(path: "/Users/tester/Library/Caches/big", sizeBytes: over50, homeDirectory: home)
        XCTAssertTrue(v.isHighRisk)
        XCTAssertEqual(v.reasons, ["over50GB"])
    }
}

final class BasketSnapshotTests: XCTestCase {
    func testBasketSnapshotMarksHighRiskChips() {
        let home = FileNode(name: "/Users/tester", kind: .directory)
        let lib = FileNode(name: "Library", kind: .directory)
        let caches = FileNode(name: "Caches", kind: .directory, logicalSize: 5, allocatedSize: 5, actualSize: 5)
        let prefs = FileNode(name: "Preferences", kind: .directory, logicalSize: 2, allocatedSize: 2, actualSize: 2)
        lib.setChildren([caches, prefs])
        home.setChildren([lib])
        let snap = BasketSnapshot.from(nodes: [caches, prefs], homeDirectory: "/Users/tester")
        XCTAssertEqual(snap.count, 2)
        XCTAssertEqual(snap.highRiskCount, 1)
        XCTAssertFalse(snap.chips[0].isHighRisk)
        XCTAssertTrue(snap.chips[1].isHighRisk)
    }
}
