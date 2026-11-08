// Added by R4 acceptance review. testBUG_* are expected to FAIL on the delivered code.
import XCTest
@testable import DiskScanCore
#if canImport(Glibc)
import Glibc
#endif

final class R4GuardTests: XCTestCase {
    func g(mounts: [String] = ["/"], issue: DeletionGuard.SubtreeIssue? = nil) -> DeletionGuard {
        DeletionGuard(homeDirectory: "/Users/tester", mountPoints: { mounts }, inspectSubtree: { _ in issue })
    }
    func testAllDotDotRefused() {
        for p in ["/tmp/a/../b", "/Users/tester/x/..", "../etc", "/usr/local/../bin", "/a/./../b"] {
            guard case .unsafePath? = g().check(p) else { return XCTFail("not refused: \(p)") }
        }
        XCTAssertNil(g().check("/tmp/a..b/c"), "'..' only as a whole component")
    }
    func testCaseVariantsBlocked() {
        for p in ["/USR", "/SYSTEM", "/users/TESTER", "/system/volumes/data", "/ETC/hosts", "/Library/LAUNCHDAEMONS/../x"] {
            XCTAssertNotNil(g().check(p), p)
        }
    }
    func testPreflightReasonsWholeItem() {
        XCTAssertEqual(g(issue: .otherDevice("/Users/tester/m/d")).evaluate("/Users/tester/m", preflight: true).reason,
                       .containsOtherDevice("/Users/tester/m/d"))
        XCTAssertEqual(g(issue: .restricted("/Users/tester/m/x")).evaluate("/Users/tester/m", preflight: true).reason,
                       .containsRestricted("/Users/tester/m/x"))
        XCTAssertNil(g(issue: .restricted("x")).evaluate("/Users/tester/m").reason, "fast check skips preflight")
    }
    func testCautions() {
        XCTAssertEqual(g().caution(for: "/Library/LaunchDaemons/com.x.plist"), .launchdJob("/Library/LaunchDaemons/com.x.plist"))
        XCTAssertEqual(g().caution(for: "/applications/Foo.app"), .applicationBundle("/applications/Foo.app"))
        XCTAssertNotNil(g().caution(for: "/var/folders/ab"))
        XCTAssertNil(g().caution(for: "/Users/tester/Downloads/x"))
    }
}

final class Recorder: @unchecked Sendable { var paths: [String] = [] }
struct FakeDeleter: ItemDeleting {
    let rec: Recorder
    func deleteItem(atPath path: String) throws { rec.paths.append(path) }
    func deleteItem(atPath path: String, expected: FileIdentity?) throws { rec.paths.append(path) }
}

@MainActor
final class R4DeletionListTests: XCTestCase {
    func tree() throws -> FileNode {
        try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/Library", [
            .dir(name: "LaunchDaemons", [.file(name: "com.x.plist", size: 10)]),
            .dir(name: "Caches", [.file(name: "c", size: 10)]),
        ]), options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/Library").root
    }
    func testCautionItemsSkippedUnlessConfirmed() async throws {
        let root = try tree()
        let l = DeletionList(deletionGuard: DeletionGuard(homeDirectory: "/Users/tester"))
        let ld = root.children.first { $0.name == "LaunchDaemons" }!.children[0]
        let cache = root.children.first { $0.name == "Caches" }!.children[0]
        XCTAssertTrue(l.add(ld)); XCTAssertTrue(l.add(cache))
        let rec = Recorder()
        let out = await l.deleteAll(using: FakeDeleter(rec: rec))   // == "Skip These Items"
        XCTAssertEqual(rec.paths, ["/Library/Caches/c"])
        XCTAssertEqual(out.failed.count, 1)
        guard case DeletionError.needsConfirmation? = out.failed.first?.error as? DeletionError else { return XCTFail() }
        let out2 = await l.deleteAll(using: FakeDeleter(rec: rec), confirmedCautions: true) // == "Include Them"
        XCTAssertEqual(out2.deleted.count, 1)
        XCTAssertEqual(rec.paths.last, "/Library/LaunchDaemons/com.x.plist")
    }
}

final class R4PosixDeleterTests: XCTestCase {
    var base = ""
    override func setUpWithError() throws {
        base = NSTemporaryDirectory() + "dr4-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    }
    override func tearDown() {
        _ = chmod(base + "/v/ro", 0o755)
        try? FileManager.default.removeItem(atPath: base)
    }
    func testIdentityMismatchRefused() throws {
        let p = base + "/f"; _ = FileManager.default.createFile(atPath: p, contents: Data([1]))
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: p, expected: FileIdentity(device: 1, inode: 1)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: p))
    }
    func testSwappedForSymlinkAfterCheckRefused() throws {
        let d = base + "/d"; let keep = base + "/keep"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: keep, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: keep + "/precious", contents: Data([1]))
        let id = FileIdentity.of(d)
        try FileManager.default.removeItem(atPath: d)
        try FileManager.default.createSymbolicLink(atPath: d, withDestinationPath: keep)
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: d, expected: id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep + "/precious"))
    }
    /// P2: preflight checks devices/SIP flags/readability but not write permission
    /// (or UF_IMMUTABLE). A readable read-only subfolder passes preflight and the
    /// permanent delete then fails half-way: siblings are already gone.
    func testBUG_readOnlySubfolderCausesPartialDelete() throws {
        try XCTSkipIf(getuid() == 0, "root ignores permissions")
        let v = base + "/v"
        try FileManager.default.createDirectory(atPath: v + "/ro", withIntermediateDirectories: true)
        for i in 0..<50 { _ = FileManager.default.createFile(atPath: v + "/f\(i)", contents: Data([1])) }
        _ = FileManager.default.createFile(atPath: v + "/ro/locked", contents: Data([1]))
        XCTAssertEqual(chmod(v + "/ro", 0o555), 0)
        let gd = DeletionGuard(homeDirectory: "/nonexistent-home", mountPoints: { ["/"] },
                               inspectSubtree: { DeletionGuard.liveInspectSubtree($0) })
        let verdict = gd.evaluate(v, preflight: true)
        XCTAssertNil(verdict.reason, "preflight passes")
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: v))
        let left = (try? FileManager.default.contentsOfDirectory(atPath: v)) ?? []
        // Desired: all-or-nothing (51 entries left) or refusal by preflight.
        XCTAssertEqual(left.count, 51, "partial delete: only \(left.count) of 51 entries left")
    }
}

final class R4CloneDeterminismTests: XCTestCase {
    func testPrimaryIsLowestFileIDRegardlessOfWorkers() throws {
        let s = BulkAttr.efMayShareBlocks
        var results: Set<String> = []
        for w in [1, 2, 8, 8, 8, 16] {
            let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", [
                .dir(name: "x", [.file(name: "b", size: 1, allocated: 40_960, inode: 20, cloneID: 3, privateSize: 4096, extFlags: s)]),
                .dir(name: "y", [.file(name: "a", size: 1, allocated: 40_960, inode: 10, cloneID: 3, privateSize: 8192, extFlags: s)]),
                .file(name: "c", size: 1, allocated: 40_960, inode: 30, cloneID: 3, privateSize: 0, extFlags: s),
            ]), options: ScanOptions(maxConcurrency: w)).scanBlocking(path: "/r")
            results.insert("\(r.root.actualSize)/\(r.cloneDuplicates)")
        }
        XCTAssertEqual(results, ["\(40_960 + 4096 + 0)/2"], "inode 10 is primary; b,c charged private")
    }
}
