import XCTest
@testable import DiskScanCore
#if canImport(Glibc)
import Glibc
#endif

final class AllOrNothingTests: XCTestCase {
    var base = ""
    let fm = FileManager.default
    override func setUpWithError() throws {
        base = NSTemporaryDirectory() + "dr4fix-\(UUID().uuidString)"
        try fm.createDirectory(atPath: base + "/v/sub", withIntermediateDirectories: true)
        for i in 0..<20 { _ = fm.createFile(atPath: base + "/v/f\(i)", contents: Data([1])) }
        _ = fm.createFile(atPath: base + "/v/sub/locked", contents: Data([1]))
    }
    override func tearDown() {
        _ = chmod(base + "/v/sub", 0o755)
        try? fm.removeItem(atPath: base)
    }
    func count() -> Int { ((try? fm.contentsOfDirectory(atPath: base + "/v")) ?? []).count }

    func testLiveCheckerRefusesReadOnlySubfolderAndNothingIsDeleted() throws {
        try XCTSkipIf(getuid() == 0, "root ignores permissions")
        XCTAssertEqual(chmod(base + "/v/sub", 0o555), 0)
        guard case .notDeletable(let p, _)? = DeletabilityChecker.live.check(base + "/v", recursive: true) else {
            return XCTFail("read-only folder not detected")
        }
        XCTAssertTrue(p.hasSuffix("/v/sub"))
        // The live guard refuses during the pre-scan, with path + reason.
        let r = DeletionGuard.live().evaluate(base + "/v", preflight: true).reason
        guard case .cannotDelete(let rp, let why)? = r else { return XCTFail("\(String(describing: r))") }
        XCTAssertTrue(rp.hasSuffix("/v/sub")); XCTAssertTrue(why.contains("read-only"))
        // The deleter alone is all-or-nothing too.
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: base + "/v"))
        XCTAssertEqual(count(), 21)
        // Trash mode checks only the top level: the parent is writable, so allowed.
        XCTAssertNil(DeletabilityChecker.live.check(base + "/v", recursive: false))
    }

    func testInjectedImmutableAndAppendFlagsRefuseWholeItem() throws {
        let cases: [(UInt32, String)] = [(DeletabilityChecker.ufImmutable, "uchg"), (DeletabilityChecker.ufAppend, "uappnd"),
                                         (DeletabilityChecker.sfImmutable, "schg"), (DeletabilityChecker.sfAppend, "sappnd")]
        for (flag, word) in cases {
            let locked = base + "/v/sub/locked"
            let checker = DeletabilityChecker(flags: { $0 == locked ? flag : 0 })
            guard case .notDeletable(let p, let why)? = checker.check(base + "/v", recursive: true) else { return XCTFail(word) }
            XCTAssertEqual(p, locked); XCTAssertTrue(why.contains(word), why)
            XCTAssertThrowsError(try PosixRecursiveDeleter(checker: checker).deleteItem(atPath: base + "/v"))
            XCTAssertEqual(count(), 21, "nothing removed for \(word)")
        }
        // A flagged FOLDER blocks removal of its entries.
        let folderFlag = DeletabilityChecker(flags: { $0.hasSuffix("/v/sub") ? DeletabilityChecker.ufImmutable : 0 })
        XCTAssertNotNil(folderFlag.check(base + "/v", recursive: true))
        // SIP flags map to `.restricted`.
        let sip = DeletabilityChecker(flags: { $0.hasSuffix("locked") ? DeletionGuard.sfRestricted : 0 })
        XCTAssertEqual(sip.check(base + "/v", recursive: true), .restricted(base + "/v/sub/locked"))
    }

    func testStickyBitRule() throws {
        let other = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { _ in true }, effectiveUID: 4242)
        XCTAssertEqual(chmod(base + "/v/sub", 0o1777), 0)
        guard case .notDeletable(let p, let why)? = other.check(base + "/v/sub", recursive: true) else { return XCTFail() }
        XCTAssertTrue(p.hasSuffix("locked")); XCTAssertTrue(why.contains("sticky"))
        let me = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { _ in true }, effectiveUID: UInt32(geteuid()))
        XCTAssertNil(me.check(base + "/v/sub", recursive: true), "owner may delete in a sticky folder")
    }

    func testInjectedAccessDeniedOnParentOfTopItem() {
        let c = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { [base] in $0 != base })
        XCTAssertEqual(c.check(base + "/v", recursive: false)?.isNotDeletable, true)
    }

    func testCleanTreeDeletesCompletely() throws {
        XCTAssertNil(DeletabilityChecker.live.check(base + "/v", recursive: true))
        try PosixRecursiveDeleter().deleteItem(atPath: base + "/v")
        XCTAssertFalse(fm.fileExists(atPath: base + "/v"))
    }
}

extension DeletionGuard.SubtreeIssue {
    var isNotDeletable: Bool { if case .notDeletable = self { return true }; return false }
}

@MainActor
final class DeletionCancellationTests: XCTestCase {
    final class Rec: ItemDeleting, @unchecked Sendable {
        let lock = NSLock(); var paths: [String] = []
        func deleteItem(atPath path: String) throws { lock.lock(); paths.append(path); lock.unlock() }
    }
    final class Events: @unchecked Sendable {
        let lock = NSLock(); var list: [DeletionProgress] = []
        func add(_ p: DeletionProgress) { lock.lock(); list.append(p); lock.unlock() }
    }

    var keepRoot: FileNode?   // FileNode.parent is weak: keep the tree alive
    func makeList(_ gd: DeletionGuard?) throws -> (DeletionList, [FileNode]) {
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/Users/tester/d", [
            .file(name: "a", size: 1, allocated: 4096), .file(name: "b", size: 1, allocated: 4096),
            .file(name: "c", size: 1, allocated: 4096),
        ]), options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/Users/tester/d")
        keepRoot = r.root
        let l = DeletionList(deletionGuard: gd)
        let nodes = r.root.children.sorted { $0.name < $1.name }
        for n in nodes { XCTAssertTrue(l.add(n)) }
        return (l, nodes)
    }

    func testCancelBetweenItemsReportsDeletedAndNotAttempted() async throws {
        let (l, nodes) = try makeList(DeletionGuard(homeDirectory: "/Users/tester"))
        let token = DeletionCancellation()
        let rec = Rec()
        let out = await l.deleteAll(using: rec, cancellation: token, progress: { p in
            // Cancel as soon as the first item has been deleted.
            if p.phase == .checking && p.itemIndex == 2 { token.cancel() }
        })
        XCTAssertTrue(out.cancelled)
        XCTAssertEqual(rec.paths, ["/Users/tester/d/a"])
        XCTAssertEqual(out.deleted.map(\.name), ["a"])
        // Item 2 was cancelled during its pre-scan (before any removal), item 3 never started.
        XCTAssertEqual(out.notAttempted.map(\.name), ["b", "c"])
        XCTAssertTrue(out.failed.isEmpty)
        XCTAssertEqual(l.items.map(\.name), ["b", "c"], "undeleted items stay on the list")
        XCTAssertNil(nodes[0].parent, "deleted node detached from the tree")
    }

    func testCancelDuringPrescanTouchesNothing() async throws {
        let token = DeletionCancellation()
        var gd = DeletionGuard(homeDirectory: "/Users/tester")
        gd.checkDeletable = { _, _, c in c?.cancel(); return c?.isCancelled == true ? .cancelled : nil }
        let (l, _) = try makeList(gd)
        let rec = Rec()
        let out = await l.deleteAll(using: rec, cancellation: token)
        XCTAssertTrue(out.cancelled)
        XCTAssertTrue(rec.paths.isEmpty)
        XCTAssertEqual(out.notAttempted.count, 3)
        XCTAssertEqual(l.items.count, 3)
    }

    func testProgressPhasesAndBackgroundExecution() async throws {
        let (l, _) = try makeList(DeletionGuard(homeDirectory: "/Users/tester"))
        let ev = Events()
        final class ThreadRec: ItemDeleting, @unchecked Sendable {
            let lock = NSLock(); var onMain: [Bool] = []
            func deleteItem(atPath path: String) throws { lock.lock(); onMain.append(Thread.isMainThread); lock.unlock() }
        }
        let tr = ThreadRec()
        let out = await l.deleteAll(using: tr, progress: { ev.add($0) })
        XCTAssertEqual(out.deleted.count, 3)
        XCTAssertEqual(ev.list.filter { $0.phase == .deleting }.map(\.itemIndex), [1, 2, 3])
        XCTAssertEqual(ev.list.last?.phase, .finished)
        XCTAssertEqual(ev.list.last?.deletedCount, 3)
        XCTAssertEqual(tr.onMain, [false, false, false], "deletes run off the main thread")
    }

    func testRefusalIsReportedWithReasonAndOthersContinue() async throws {
        var gd = DeletionGuard(homeDirectory: "/Users/tester")
        gd.checkDeletable = { p, _, _ in p.hasSuffix("/b") ? .notDeletable(p + "/x", "folder is read-only for you") : nil }
        let (l, _) = try makeList(gd)
        let rec = Rec()
        let out = await l.deleteAll(using: rec)
        XCTAssertEqual(rec.paths, ["/Users/tester/d/a", "/Users/tester/d/c"])
        guard case DeletionError.blocked(_, .cannotDelete(let p, let why))? = out.failed.first?.error as? DeletionError else { return XCTFail() }
        XCTAssertEqual(p, "/Users/tester/d/b/x"); XCTAssertTrue(why.contains("read-only"))
    }
}

final class DisplayPathTests: XCTestCase {
    func testFirmlinkPrefixHiddenForDisplay() {
        XCTAssertEqual(DisplayPath.forUser("/System/Volumes/Data/Users/tester/x"), "/Users/tester/x")
        XCTAssertEqual(DisplayPath.forUser("/System/Volumes/Data"), "/System/Volumes/Data", "the volume root itself stays")
        XCTAssertEqual(DisplayPath.forUser("/System/Volumes/Data/private/var/x"), "/private/var/x")
        XCTAssertEqual(DisplayPath.forUser("/Volumes/Ext/a"), "/Volumes/Ext/a")
        XCTAssertEqual(DisplayPath.forUser("/System/Volumes/Preboot/x"), "/System/Volumes/Preboot/x")
        XCTAssertEqual(DisplayPath.forUser("/System/Volumes/DataX/y"), "/System/Volumes/DataX/y")
    }
}
