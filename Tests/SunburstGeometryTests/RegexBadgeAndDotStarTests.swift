import XCTest
@testable import SunburstGeometry
@testable import DiskScanCore

private final class Slot<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

final class RegexBadgeAndDotStarTests: XCTestCase {
    typealias T = TreeSearch
    let launch = T.Settings.launch

    // Bug 1: ".*" badge
    func testBadgeHiddenAtLaunchShownOnToggleSlashOnlyAndHiddenAfterClear() {
        XCTAssertEqual(launch.mode, .contains)
        XCTAssertFalse(SearchModeIndicator.regexBadgeVisible(text: "", settings: launch))
        XCTAssertFalse(SearchModeIndicator.regexBadgeVisible(text: "backup", settings: launch))
        XCTAssertFalse(SearchModeIndicator.regexBadgeVisible(text: ".*backup.*", settings: launch))
        var on = launch; on.mode = .regex
        XCTAssertTrue(SearchModeIndicator.regexBadgeVisible(text: "", settings: on))
        XCTAssertTrue(SearchModeIndicator.regexBadgeVisible(text: "/x/", settings: launch))
        XCTAssertFalse(SearchModeIndicator.regexBadgeVisible(text: "/x", settings: launch))
        XCTAssertFalse(SearchModeIndicator.regexBadgeVisible(text: "", settings: launch))   // cleared
        on.mode = .contains
        XCTAssertFalse(SearchModeIndicator.regexBadgeVisible(text: "", settings: on))       // toggled back off
    }

    // Bug 2: ".*backup.*"
    func file(_ n: String, _ s: UInt64) -> FileNode { FileNode(name: n, kind: .file, logicalSize: s, allocatedSize: s, actualSize: s) }
    func dir(_ n: String, _ k: [FileNode]) -> FileNode { let d = FileNode(name: n, kind: .directory); d.setChildren(k); return d }
    func tree() -> FileNode {
        let r = dir("Data", [dir("Users", [dir("mac387", [dir("Downloads", [dir("backup", [file("x.bin", 100)])]),
                                                         file("state.vscdb.BACKUP", 10), file("other", 5)])])])
        r.aggregate(); return r
    }
    func names(_ r: T.Result) -> Set<String> { Set(r.hits.map(\.name)) }

    func testContainsModeSearchesLiteralDotStar() {
        let c = try! T.compile(.init(text: ".*backup.*", mode: .contains)).get()
        let r = T.run(root: tree(), compiled: c)
        XCTAssertEqual(r.total, 0); XCTAssertFalse(r.timedOut); XCTAssertFalse(r.cancelled)
    }

    func testRegexDotStarFindsSameAsPlainBackup() {
        let root = tree()
        let plain = T.run(root: root, compiled: try! T.compile(.init(text: "backup")).get())
        for p in [".*backup.*", "backup.*", ".*backup", ".*?backup.*?"] {
            let c = try! T.compile(.init(text: p, mode: .regex)).get()
            XCTAssertTrue(c.usesLiteralMatcher, p)
            XCTAssertEqual(names(T.run(root: root, compiled: c)), names(plain), p)
        }
        let viaSlash = T.Query.parse("/.*backup.*/", mode: .contains, scope: .name)
        XCTAssertEqual(names(T.run(root: root, compiled: try! T.compile(viaSlash).get())), names(plain))
        XCTAssertEqual(names(plain), ["backup", "state.vscdb.BACKUP"])
    }

    func testSimplificationRules() {
        XCTAssertEqual(T.simplifiedRegex(".*backup.*"), "backup")
        XCTAssertEqual(T.simplifiedRegex(".*.*a.*?"), "a")
        XCTAssertEqual(T.simplifiedRegex("a\\.*"), "a\\.*")         // escaped dot kept
        XCTAssertEqual(T.simplifiedRegex("a\\\\.*"), "a\\\\")       // escaped backslash, real .*
        XCTAssertEqual(T.simplifiedRegex("^back.*$"), "^back.*$")   // anchors untouched
        XCTAssertEqual(T.simplifiedRegex(".*"), "")
        // ".*" alone still compiles (matches everything) instead of an empty pattern
        let c = try! T.compile(.init(text: ".*", mode: .regex)).get()
        XCTAssertFalse(c.usesLiteralMatcher)
        XCTAssertEqual(T.run(root: tree(), compiled: c).total, 7)
        // real regex after stripping stays a regex
        XCTAssertFalse(try! T.compile(.init(text: ".*back(up)?.*", mode: .regex)).get().usesLiteralMatcher)
    }

    /// 5M (DISKRINGS_HEAVY=1; 200k otherwise) ".*backup.*" off the main thread: no catastrophic
    /// backtracking, far under the 10 s guard. Also times the unsimplified regex for the record.
    func testDotStarBenchmark() {
        let heavy = ProcessInfo.processInfo.environment["DISKRINGS_HEAVY"] == "1"
        let n = heavy ? 5_000_000 : 200_000
        let root = SyntheticTree.build(targetNodes: n)
        let slot = Slot<[String: (Double, Int, Bool)]>([:])
        let done = expectation(description: "bench")
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [String: (Double, Int, Bool)] = [:]
            let simplified = try! T.compile(.init(text: ".*cache.*", mode: .regex)).get()
            var t0 = Date(); var r = T.run(root: root, compiled: simplified, timeout: 60)
            out["simplified"] = (Date().timeIntervalSince(t0), r.total, r.timedOut)
            let raw = T.Compiled(query: .init(text: ".*cache.*", mode: .regex), matcher: nil,
                                 regex: try! NSRegularExpression(pattern: ".*cache.*", options: [.caseInsensitive]))
            t0 = Date(); r = T.run(root: root, compiled: raw, timeout: 60)
            out["raw"] = (Date().timeIntervalSince(t0), r.total, r.timedOut)
            slot.value = out; done.fulfill()
        }
        wait(for: [done], timeout: 300)
        let o = slot.value
        print(String(format: "DOTSTAR %d nodes: simplified %.2fs (total %d) · raw NSRegularExpression %.2fs (total %d)",
                     n, o["simplified"]!.0, o["simplified"]!.1, o["raw"]!.0, o["raw"]!.1))
        XCTAssertEqual(o["simplified"]!.1, o["raw"]!.1)
        XCTAssertFalse(o["simplified"]!.2); XCTAssertFalse(o["raw"]!.2)
        XCTAssertLessThan(o["simplified"]!.0, T.regexTimeout / 2)
    }
}
