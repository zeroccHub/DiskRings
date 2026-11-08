// Added by R5 acceptance review (no source changes).
import XCTest
@testable import DiskScanCore
#if canImport(Glibc)
import Glibc
#endif

final class R5AllOrNothingTests: XCTestCase {
    var base = ""
    let fm = FileManager.default
    override func setUpWithError() throws {
        try XCTSkipIf(getuid() == 0, "root ignores permissions")
        base = NSTemporaryDirectory() + "dr5-\(UUID().uuidString)"
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
    }
    override func tearDown() {
        if let e = fm.enumerator(atPath: base) { for case let p as String in e { _ = chmod(base + "/" + p, 0o755) } }
        _ = chmod(base, 0o755)
        try? fm.removeItem(atPath: base)
    }
    func listing(_ p: String) -> [String] { (fm.subpaths(atPath: p) ?? []).sorted() }
    func makeTree(_ root: String, files: Int = 100) throws {
        try fm.createDirectory(atPath: root + "/a/b/c", withIntermediateDirectories: true)
        for i in 0..<files { _ = fm.createFile(atPath: root + "/f\(i)", contents: Data([1])) }
        for d in ["a", "a/b", "a/b/c"] { for i in 0..<10 { _ = fm.createFile(atPath: "\(root)/\(d)/g\(i)", contents: Data([1])) } }
    }

    /// Variant of R4 testBUG_: read-only folder 3 levels deep, many siblings → nothing moves.
    func testDeepReadOnlyFolderTouchesNothing() throws {
        let v = base + "/v"; try makeTree(v)
        XCTAssertEqual(chmod(v + "/a/b/c", 0o555), 0)
        let before = listing(v)
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: v)) { e in
            guard case DeletionError.blocked(_, .cannotDelete(let p, _))? = e as? DeletionError else { return XCTFail("\(e)") }
            XCTAssertTrue(p.hasSuffix("/a/b/c"))
        }
        XCTAssertEqual(listing(v), before)
    }
    /// The top item itself read-only (non-empty) → refused, untouched.
    func testReadOnlyTopFolderTouchesNothing() throws {
        let v = base + "/v"; try makeTree(v, files: 5)
        XCTAssertEqual(chmod(v, 0o555), 0)
        let before = listing(v)
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: v))
        XCTAssertEqual(listing(v), before)
    }
    /// An EMPTY read-only subfolder is removable (rmdir needs only the parent) → full delete.
    func testEmptyReadOnlySubfolderIsDeletable() throws {
        let v = base + "/v"; try makeTree(v, files: 3)
        try fm.createDirectory(atPath: v + "/empty", withIntermediateDirectories: true)
        XCTAssertEqual(chmod(v + "/empty", 0o555), 0)
        XCTAssertNil(DeletabilityChecker.live.check(v, recursive: true))
        XCTAssertNoThrow(try PosixRecursiveDeleter().deleteItem(atPath: v))
        XCTAssertFalse(fm.fileExists(atPath: v))
    }
    /// Unreadable (000) subfolder → refused (contents not verifiable), untouched.
    func testUnreadableSubfolderTouchesNothing() throws {
        let v = base + "/v"; try makeTree(v, files: 20)
        XCTAssertEqual(chmod(v + "/a/b", 0o000), 0)
        let beforeTop = (try? fm.contentsOfDirectory(atPath: v))?.count
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: v))
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: v))?.count, beforeTop)
    }
    /// Flags on the TOP item and on a nested FOLDER (injected; Linux has no st_flags).
    func testFlagsOnTopItemAndNestedFolder() throws {
        let v = base + "/v"; try makeTree(v, files: 10)
        let before = listing(v)
        for (target, flag) in [(v, DeletabilityChecker.ufImmutable), (v + "/a/b", DeletabilityChecker.ufAppend),
                               (v + "/a/b/c/g3", DeletabilityChecker.sfImmutable), (v + "/a", DeletabilityChecker.sfAppend),
                               (v + "/f1", DeletionGuard.sfNoUnlink)] {
            let c = DeletabilityChecker(flags: { $0 == target ? flag : 0 })
            XCTAssertNotNil(c.check(v, recursive: true), target)
            XCTAssertThrowsError(try PosixRecursiveDeleter(checker: c).deleteItem(atPath: v))
            XCTAssertEqual(listing(v), before, "nothing removed for \(target)")
        }
    }
    /// Sticky rule: root may delete; other euid (not entry/dir owner) may not.
    func testStickyRootAndOtherUser() throws {
        let s = base + "/s"; try fm.createDirectory(atPath: s, withIntermediateDirectories: true)
        _ = fm.createFile(atPath: s + "/x", contents: Data([1])); XCTAssertEqual(chmod(s, 0o1777), 0)
        let root = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { _ in true }, effectiveUID: 0)
        XCTAssertNil(root.check(s + "/x", recursive: true))
        let other = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { _ in true }, effectiveUID: 4242)
        XCTAssertNotNil(other.check(s + "/x", recursive: true), "top item in sticky parent")
    }
    /// If the tree changes AFTER the pre-pass (simulated with a lenient checker),
    /// the deleter must report `partiallyDeleted` honestly with a count > 0.
    func testChangeAfterCheckIsReportedAsPartial() throws {
        let v = base + "/v"; try makeTree(v, files: 30)
        XCTAssertEqual(chmod(v + "/a/b/c", 0o555), 0)
        let lenient = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { _ in true })
        XCTAssertThrowsError(try PosixRecursiveDeleter(checker: lenient).deleteItem(atPath: v)) { e in
            guard case DeletionError.partiallyDeleted(_, let n, _)? = e as? DeletionError else { return XCTFail("\(e)") }
            XCTAssertGreaterThan(n, 0)
        }
    }
}

@MainActor
final class R5OutcomeTests: XCTestCase {
    final class Del: ItemDeleting, @unchecked Sendable {
        let lock = NSLock(); var calls: [String] = []; var onDelete: ((String) throws -> Void)?
        func deleteItem(atPath path: String) throws {
            lock.lock(); calls.append(path); lock.unlock(); try onDelete?(path)
        }
    }
    var keep: FileNode?
    func list() throws -> DeletionList {
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/Users/tester/d",
            ["a", "b", "c", "d"].map { .file(name: $0, size: 1, allocated: 4096) }),
            options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/Users/tester/d")
        keep = r.root
        let l = DeletionList(deletionGuard: DeletionGuard(homeDirectory: "/Users/tester"))
        for n in r.root.children.sorted(by: { $0.name < $1.name }) { XCTAssertTrue(l.add(n)) }
        return l
    }
    /// Cancel pressed WHILE item "a" is being removed: a finishes, b..d not attempted.
    func testCancelMidItemFinishesThatItemOnly() async throws {
        let l = try list(); let tok = DeletionCancellation(); let d = Del()
        d.onDelete = { _ in tok.cancel() }
        let out = await l.deleteAll(using: d, cancellation: tok)
        XCTAssertEqual(d.calls, ["/Users/tester/d/a"])
        XCTAssertEqual(out.deleted.map(\.name), ["a"])
        XCTAssertEqual(out.notAttempted.map(\.name), ["b", "c", "d"])
        XCTAssertTrue(out.cancelled); XCTAssertTrue(out.failed.isEmpty)
    }
    /// Mixed outcome counts are disjoint and complete: deleted + failed + notAttempted == items.
    func testOutcomeCountsAreHonest() async throws {
        let l = try list(); let tok = DeletionCancellation(); let d = Del()
        d.onDelete = { p in
            if p.hasSuffix("/b") { throw DeletionError.partiallyDeleted(path: p, removedEntries: 3, cause: "x") }
            if p.hasSuffix("/c") { tok.cancel(); throw DeletionError.posix(path: p, operation: "unlink", code: EIO) }
        }
        let out = await l.deleteAll(using: d, cancellation: tok)
        XCTAssertEqual(out.deleted.map(\.name), ["a"])
        XCTAssertEqual(Set(out.failed.map(\.node.name)), ["b", "c"])
        XCTAssertEqual(out.partial.map(\.name), ["b"])
        XCTAssertEqual(out.notAttempted.map(\.name), ["d"])
        XCTAssertEqual(out.deleted.count + out.failed.count + out.notAttempted.count, 4)
        XCTAssertEqual(Set(l.items.map(\.name)), ["b", "c", "d"], "partial/failed/not attempted stay listed")
    }
    /// Deletion work runs off the main thread.
    func testDeleterRunsOffMainThread() async throws {
        let l = try list(); let d = Del(); let flag = Del()
        d.onDelete = { _ in if Thread.isMainThread { flag.calls.append("main") } }
        _ = await l.deleteAll(using: d)
        XCTAssertTrue(flag.calls.isEmpty)
    }
}
