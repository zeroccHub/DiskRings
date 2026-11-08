import XCTest
@testable import SunburstGeometry
@testable import DiskScanCore

/// Whole-tree search (「搜索文件和文件夹」): matching, top-500 + total, ordering, cancellation,
/// 5M nodes off the main thread, locate-to-parent, Esc restore.
/// Result slot written by the worker before `fulfill()` and read after `wait` (happens-before).
private final class Slot<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

final class TreeSearchTests: XCTestCase {
    func file(_ n: String, _ size: UInt64) -> FileNode {
        FileNode(name: n, kind: .file, logicalSize: size, allocatedSize: size, actualSize: size)
    }
    func dir(_ n: String, _ kids: [FileNode]) -> FileNode {
        let d = FileNode(name: n, kind: .directory); d.setChildren(kids); return d
    }
    /// Data root → Users › mac387 › Documents › backup-2024 (several levels down).
    func sampleTree() -> (root: FileNode, deep: FileNode, top: FileNode) {
        let deep = dir("backup-2024", [file("a.dat", 40), file("b.dat", 60)])
        let top = file("Backup.sparsebundle", 30)
        let root = dir("/System/Volumes/Data", [
            dir("Users", [dir("mac387", [dir("Documents", [deep, file("notes.txt", 5)]), file("ignore.bin", 1)])]),
            top, dir("Library", [file("BACKUPLOG.txt", 2)]),
        ])
        root.aggregate()
        return (root, deep, top)
    }

    func testMatching() {
        let m = TreeSearch.Matcher("BackUp")
        XCTAssertTrue(m.matches("my-backup.zip")); XCTAssertTrue(m.matches("BACKUP")); XCTAssertTrue(m.matches("backup"))
        XCTAssertFalse(m.matches("back-up")); XCTAssertFalse(m.matches("backu")); XCTAssertFalse(m.matches(""))
        XCTAssertFalse(TreeSearch.Matcher("   ").matches("anything"))
        XCTAssertTrue(TreeSearch.Matcher(" backup ").matches("x backup y"))       // trimmed
        XCTAssertTrue(TreeSearch.Matcher("文档").matches("我的文档备份"))
        XCTAssertTrue(TreeSearch.Matcher("CAFÉ").matches("old café photos"))     // non-ASCII, case-insensitive
        XCTAssertTrue(TreeSearch.Matcher("ap").matches("Ünicode-App"))          // ASCII query over non-ASCII name

        let (root, deep, top) = sampleTree()
        let r = TreeSearch.run(root: root, query: "backup")
        XCTAssertEqual(r.total, 3)
        XCTAssertEqual(r.hits.map(\.name), ["backup-2024", "Backup.sparsebundle", "BACKUPLOG.txt"])
        XCTAssertTrue(r.hits[0].node === deep); XCTAssertTrue(r.hits[1].node === top)
        XCTAssertEqual(r.hits[0].relativePath, "Users/mac387/Documents")
        XCTAssertEqual(r.hits[1].relativePath, "")
        XCTAssertEqual(r.hits[2].relativePath, "Library")
        XCTAssertFalse(TreeSearch.run(root: root, query: "Data").hits.contains { $0.node === root }, "root itself excluded")
        XCTAssertEqual(TreeSearch.run(root: root, query: "zzz").total, 0)
    }

    func testTop500AndTotalAndOrdering() {
        let kids = (0..<1200).map { file("backup-\($0)", UInt64($0 % 1000) + 1) } + [file("other", 5000)]
        let root = dir("/r", kids); root.aggregate()
        let r = TreeSearch.run(root: root, query: "BACKUP")
        XCTAssertEqual(r.total, 1200); XCTAssertEqual(r.hits.count, TreeSearch.limit); XCTAssertTrue(r.isTruncated)
        for i in 1..<r.hits.count { XCTAssertGreaterThanOrEqual(r.hits[i - 1].size, r.hits[i].size) }
        XCTAssertEqual(r.hits.first?.size, 1000)
        // Exactly the 500 largest: sizes 1000…801 twice (i and i+1000 for i < 200) + 1000…? → check min.
        let all = kids.filter { $0.name.hasPrefix("backup") }.map { Double($0.sunburstSize) }.sorted(by: >)
        XCTAssertEqual(r.hits.map(\.size), Array(all.prefix(500)))
        // Ties broken by name (deterministic).
        let tie = dir("/t", [file("b-backup", 7), file("a-backup", 7), file("c-backup", 9)]); tie.aggregate()
        XCTAssertEqual(TreeSearch.run(root: tie, query: "backup").hits.map(\.name), ["c-backup", "a-backup", "b-backup"])
        XCTAssertFalse(TreeSearch.run(root: tie, query: "backup").isTruncated)
    }

    func testCancellation() {
        let root = SyntheticTree.build(targetNodes: 300_000)
        let pre = TreeSearch.Token(); pre.cancel()
        let r = TreeSearch.run(root: root, query: "cache", token: pre)
        XCTAssertTrue(r.cancelled); XCTAssertTrue(r.hits.isEmpty); XCTAssertLessThanOrEqual(r.visited, 4096)
        // Cancel while running on another thread: stops early.
        let token = TreeSearch.Token()
        let done = expectation(description: "search returned")
        let slot = Slot<TreeSearch.Result?>(nil)
        DispatchQueue.global().async {
            slot.value = TreeSearch.run(root: root, query: "cache", token: token)
            done.fulfill()
        }
        token.cancel()
        wait(for: [done], timeout: 30)
        let result = slot.value
        XCTAssertEqual(result?.cancelled, true)
        XCTAssertEqual(result?.hits.count, 0)
        // Stale results are never shown: a newer query bumps the generation.
        final class F {}
        var st = SearchState<F>()
        guard case let .start(g1, _) = st.typed("cac", current: nil) else { return XCTFail() }
        guard case let .start(g2, _) = st.typed("cache", current: nil) else { return XCTFail() }
        XCTAssertFalse(st.accepts(generation: g1)); XCTAssertTrue(st.accepts(generation: g2))
    }

    /// 5M-node search on a background queue (never the main thread); time reported.
    func testFiveMillionSearchOffMainThread() throws {
        let heavy = ProcessInfo.processInfo.environment["DISKRINGS_HEAVY"] == "1"
        let n = heavy ? 5_000_000 : 300_000
        let root = SyntheticTree.build(targetNodes: n)
        let done = expectation(description: "search")
        let slot = Slot<(TreeSearch.Result?, Double, Bool)>((nil, 0, true))
        DispatchQueue.global(qos: .userInitiated).async {
            let onMain = Thread.isMainThread
            let t0 = Date()
            let res = TreeSearch.run(root: root, query: "cache")
            slot.value = (res, Date().timeIntervalSince(t0), onMain)
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        let (r, secs, onMain) = slot.value
        print(String(format: "SEARCH %d nodes: %.3fs total=%d shown=%d (off main thread)", n, secs, r?.total ?? -1, r?.hits.count ?? -1))
        XCTAssertFalse(onMain)
        XCTAssertEqual(r?.visited, n - 1)
        XCTAssertGreaterThan(r?.total ?? 0, TreeSearch.limit)
        XCTAssertEqual(r?.hits.count, TreeSearch.limit)
        if heavy { XCTAssertLessThan(secs, 5) }
    }

    func testLocateDrillsToParentAndSelects() {
        let (root, deep, top) = sampleTree()
        let hit = deep.children[1]                                   // b.dat inside backup-2024
        let (focus, sel) = TreeSearch.locate(hit, root: root)
        XCTAssertTrue(focus === deep); XCTAssertTrue(sel === hit)
        let m = ChartModel(focus: focus, isProtected: { _ in false }, isHighRisk: { _ in false },
                           sizeText: { "\(Int($0))" }, otherName: { "其他 \($0) 项" })
        XCTAssertNotNil(m.sectors.firstIndex { $0.node === sel }, "hit is a sector of its parent's chart")
        XCTAssertTrue(TreeSearch.locate(top, root: root).focus === root)
        XCTAssertEqual(TreeSearch.relativeParentPath(hit, root: root), "Users/mac387/Documents/backup-2024")
    }

    func testEscRestoresPreviousView() {
        final class F {}
        let a = F(), b = F()
        var st = SearchState<F>()
        XCTAssertNil(st.escape(), "inactive: nothing to restore")
        XCTAssertEqual(st.typed("back", current: a), .start(generation: 1, query: "back"))
        XCTAssertEqual(st.typed("back", current: a), SearchState<F>.Action.none)
        // Locating a hit moves the chart to b; the restore target stays a.
        XCTAssertEqual(st.typed("backup", current: b), .start(generation: 2, query: "backup"))
        XCTAssertEqual(st.refresh(), .start(generation: 3, query: "backup"))
        XCTAssertTrue(st.escape() === a)
        XCTAssertFalse(st.isActive); XCTAssertNil(st.escape())
        // Emptying the field clears without restore; a new scan clears too.
        _ = st.typed("x", current: b)
        XCTAssertEqual(st.typed("  ", current: b), .clear); XCTAssertNil(st.restoreFocus)
        _ = st.typed("x", current: b); st.rescan()
        XCTAssertFalse(st.isActive); XCTAssertNil(st.escape())
        XCTAssertFalse(st.accepts(generation: st.generation), "inactive state accepts no result")
    }
}
