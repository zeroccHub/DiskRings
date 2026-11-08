import XCTest
@testable import SunburstGeometry
@testable import DiskScanCore

private final class Slot<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

/// Regex search (opt-in): /pattern/ parsing, invalid patterns, path scope, time guard,
/// session-only settings, 5M benchmark.
final class RegexSearchTests: XCTestCase {
    typealias T = TreeSearch
    func file(_ n: String, _ s: UInt64) -> FileNode { FileNode(name: n, kind: .file, logicalSize: s, allocatedSize: s, actualSize: s) }
    func dir(_ n: String, _ k: [FileNode]) -> FileNode { let d = FileNode(name: n, kind: .directory); d.setChildren(k); return d }
    func compiled(_ text: String, _ mode: T.Mode = .regex, _ scope: T.Scope = .name) -> T.Compiled {
        guard case let .success(c) = T.compile(T.Query(text: text, mode: mode, scope: scope)) else { fatalError("compile \(text)") }
        return c
    }
    func sample() -> FileNode {
        let r = dir("/System/Volumes/Data", [
            dir("Users", [dir("mac387", [dir("Downloads", [dir("backup", [file("IMG_0001.JPG", 50), file("notes.txt", 5)]),
                                                         file("backup-2023.zip", 70)])])]),
            dir("Library", [dir("Backups", [file("old.bak", 9)])]),
        ])
        r.aggregate(); return r
    }

    func testSlashPatternParsing() {
        XCTAssertEqual(T.Query.parse("/^img_\\d+/", mode: .contains, scope: .name), T.Query(text: "^img_\\d+", mode: .regex))
        XCTAssertEqual(T.Query.parse("  /a|b/  ", mode: .contains, scope: .path), T.Query(text: "a|b", mode: .regex, scope: .path))
        XCTAssertEqual(T.Query.parse("//", mode: .contains, scope: .name).mode, .contains, "empty pattern is literal")
        XCTAssertEqual(T.Query.parse("/", mode: .contains, scope: .name).mode, .contains)
        XCTAssertEqual(T.Query.parse("/tmp", mode: .contains, scope: .name), T.Query(text: "/tmp", mode: .contains))
        XCTAssertEqual(T.Query.parse("backup", mode: .regex, scope: .name).mode, .regex, "menu toggle")
        XCTAssertEqual(T.Query.parse("backup", mode: .contains, scope: .name).mode, .contains, "default literal")
    }

    func testInvalidRegexRunsNothing() {
        for bad in ["(", "[a-", "*x", "a{2,1}"] {
            guard case .failure(.invalidRegex(let msg)) = T.compile(T.Query(text: bad, mode: .regex)) else { return XCTFail(bad) }
            XCTAssertFalse(msg.isEmpty)
        }
        // The same text is fine as a literal "contains" query.
        if case .failure = T.compile(T.Query(text: "(", mode: .contains)) { XCTFail() }
        XCTAssertEqual(T.compile(T.Query(text: "", mode: .regex)).failureValue, .emptyPattern)
    }

    func testRegexAndPathScopeMatching() {
        let root = sample()
        // Case-insensitive by default, names only.
        var r = T.run(root: root, compiled: compiled("^img_\\d{4}\\.jpe?g$"))
        XCTAssertEqual(r.hits.map(\.name), ["IMG_0001.JPG"])
        r = T.run(root: root, compiled: compiled("^backup"))
        XCTAssertEqual(Set(r.hits.map(\.name)), ["backup", "backup-2023.zip", "Backups"])
        // Name scope never sees the folders above.
        XCTAssertEqual(T.run(root: root, compiled: compiled("downloads/backup")).total, 0)
        // Path scope: relative path from the scan root.
        r = T.run(root: root, compiled: compiled("^users/mac387/downloads/backup/", .regex, .path))
        XCTAssertEqual(Set(r.hits.map(\.name)), ["IMG_0001.JPG", "notes.txt"])
        r = T.run(root: root, compiled: compiled("Library/Backups", .contains, .path))
        XCTAssertEqual(Set(r.hits.map(\.name)), ["Backups", "old.bak"])
        // Contains through the compiled path equals the plain search.
        XCTAssertEqual(T.run(root: root, compiled: compiled("backup", .contains)).total, T.run(root: root, query: "backup").total)
    }

    func testTimeoutAbortsPathologicalPattern() {
        // (a+)+$ against "aaaa…!" backtracks exponentially per name; the deadline is checked
        // between nodes, so the whole search stops shortly after the timeout.
        let kids = (0..<3000).map { file(String(repeating: "a", count: 19) + "!\($0)", 1) }
        let root = dir("/r", kids); root.aggregate()
        let t0 = Date()
        let r = T.run(root: root, compiled: compiled("^(a+)+$"), timeout: 0.3)
        let secs = Date().timeIntervalSince(t0)
        XCTAssertTrue(r.timedOut); XCTAssertTrue(r.hits.isEmpty); XCTAssertFalse(r.cancelled)
        XCTAssertLessThan(r.visited, 3000)
        XCTAssertLessThan(secs, 3, "aborted near the deadline (+ at most one in-flight match)")
        print(String(format: "REGEX timeout: aborted after %.2fs, %d nodes", secs, r.visited))
        // Long subjects are capped (last 1024 UTF-16 units are matched).
        let long = String(repeating: "x", count: 5000) + "tail"
        XCTAssertTrue(compiled("tail$").matches(long))
        XCTAssertFalse(compiled("^x").matches(long), "start of a >1024 subject is outside the cap")
        XCTAssertEqual(T.maxRegexSubject, 1024); XCTAssertEqual(T.regexTimeout, 10)
    }

    func testSettingsResetToContainsOnLaunch() {
        // No persistence: a fresh session always starts in Contains / names.
        XCTAssertEqual(T.Settings.launch, T.Settings(mode: .contains, scope: .name))
        XCTAssertFalse(T.Settings.launch.regexEnabled)
        var s = T.Settings.launch; s.mode = .regex; s.scope = .path
        XCTAssertTrue(s.regexEnabled)
        XCTAssertEqual(T.Settings.launch.mode, .contains, "changing the session copy never changes the launch state")
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            XCTAssertFalse(key.hasPrefix("DiskRings.search"), "no search setting is written to UserDefaults: \(key)")
        }
    }

    /// 5M nodes, regex over names, background queue.
    func testFiveMillionRegexBenchmark() {
        let heavy = ProcessInfo.processInfo.environment["DISKRINGS_HEAVY"] == "1"
        let n = heavy ? 5_000_000 : 200_000
        let root = SyntheticTree.build(targetNodes: n)
        let c = compiled("^cache(s|_data)\\d+$")
        let done = expectation(description: "regex")
        let slot = Slot<(T.Result?, Double, Bool)>((nil, 0, true))
        DispatchQueue.global(qos: .userInitiated).async {
            let main = Thread.isMainThread, t0 = Date()
            let r = T.run(root: root, compiled: c, timeout: 60)
            slot.value = (r, Date().timeIntervalSince(t0), main)
            done.fulfill()
        }
        wait(for: [done], timeout: 300)
        let (r, secs, main) = slot.value
        print(String(format: "REGEX %d nodes: %.2fs total=%d (off main thread)", n, secs, r?.total ?? -1))
        XCTAssertFalse(main); XCTAssertEqual(r?.timedOut, false)
        XCTAssertGreaterThan(r?.total ?? 0, 0); XCTAssertEqual(r?.visited, n - 1)
    }
}

extension Result {
    var failureValue: Failure? { if case let .failure(e) = self { return e }; return nil }
}

