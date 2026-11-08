import XCTest
@testable import DiskScanCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class TreeAndDeletionTests: XCTestCase {
    func sampleTree() throws -> FileNode {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
            .dir(name: "a", [.file(name: "a1", size: 1, allocated: 1000), .dir(name: "aa", [.file(name: "a2", size: 1, allocated: 2000)])]),
            .file(name: "b", size: 1, allocated: 500),
        ])
        return try ScanEngine(enumerator: fs, options: ScanOptions(maxConcurrency: 2)).scanBlocking(path: "/r").root
    }

    func testRemoveFromTreeUpdatesAncestors() throws {
        let root = try sampleTree()
        let aa = root.descendant(atRelativePath: ["a", "aa"])!
        XCTAssertEqual(root.allocatedSize, 3500)
        XCTAssertTrue(aa.removeFromTree())
        XCTAssertTrue(aa.isDeleted)
        XCTAssertNil(aa.parent)
        XCTAssertEqual(root.allocatedSize, 1500)
        XCTAssertEqual(root.children.first { $0.name == "a" }!.allocatedSize, 1000)
        XCTAssertEqual(root.itemCount, 2)
        XCTAssertFalse(root.removeFromTree(), "root has no parent")
    }

    @MainActor func testDeletionListAncestorDescendantRules() async throws {
        let root = try sampleTree()
        let a = root.descendant(atRelativePath: ["a"])!
        let a1 = root.descendant(atRelativePath: ["a", "a1"])!
        let b = root.descendant(atRelativePath: ["b"])!
        let c = DeletionList()
        XCTAssertFalse(c.add(root))
        XCTAssertTrue(c.add(a1))
        XCTAssertTrue(c.add(b))
        XCTAssertTrue(c.add(a))            // replaces a1
        XCTAssertEqual(c.items.map(\.name), ["b", "a"])
        XCTAssertFalse(c.add(a1))           // ancestor already collected
        XCTAssertEqual(c.totalSize(), 3500)
        c.remove(b)
        XCTAssertEqual(c.totalSize(), 3000)
    }

    struct RecordingDeleter: ItemDeleting {
        final class Log: @unchecked Sendable { var paths: [String] = [] }
        let log = Log()
        var failPaths: Set<String> = []
        func deleteItem(atPath path: String) throws {
            if failPaths.contains(path) { throw DeletionError.posix(path: path, operation: "unlink", code: EACCES) }
            log.paths.append(path)
        }
    }

    @MainActor func testDeletionListDeleteUpdatesTreeAndReportsFailures() async throws {
        let root = try sampleTree()
        let c = DeletionList()
        c.add(root.descendant(atRelativePath: ["a", "aa"])!)
        c.add(root.descendant(atRelativePath: ["b"])!)
        let deleter = RecordingDeleter(failPaths: ["/r/b"])
        let outcome = await c.deleteAll(using: deleter, privileged: UnimplementedPrivilegedDeleter())
        XCTAssertEqual(deleter.log.paths, ["/r/a/aa"])
        XCTAssertEqual(outcome.deleted.count, 1)
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(outcome.freedBytes, 2000)
        XCTAssertEqual(root.allocatedSize, 1500)
        XCTAssertEqual(c.items.map(\.name), ["b"], "failed items stay in the deletionList")
    }

    func testPrivilegedStubThrows() async {
        do {
            try await UnimplementedPrivilegedDeleter().deleteItemPrivileged(atPath: "/x")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? DeletionError, .privilegedHelperNotImplemented)
        }
    }

    // MARK: Real filesystem (Linux box / macOS): PosixDirectoryEnumerator + PosixRecursiveDeleter

    @MainActor func testRealFilesystemScanHardlinkSymlinkAndDelete() async throws {
        let base = NSTemporaryDirectory() + "diskrings-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: base + "/sub/deep", withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: URL(fileURLWithPath: base + "/sub/big.bin"))
        try Data(repeating: 2, count: 10).write(to: URL(fileURLWithPath: base + "/sub/deep/small.txt"))
        XCTAssertEqual(link(base + "/sub/big.bin", base + "/hardlink.bin"), 0)
        try fm.createSymbolicLink(atPath: base + "/loop", withDestinationPath: base) // would recurse forever if followed
        defer { try? fm.removeItem(atPath: base) }

        let engine = ScanEngine(enumerator: PosixDirectoryEnumerator(), options: ScanOptions(maxConcurrency: 4))
        let r = try await engine.scan(path: base)
        XCTAssertEqual(r.hardLinkDuplicates, 1)
        XCTAssertEqual(r.root.logicalSize, 100_000 + 10 + r.root.children.first { $0.name == "loop" }!.logicalSize)
        XCTAssertEqual(r.root.children.first { $0.name == "loop" }!.kind, .symlink)
        let sub = r.root.descendant(atRelativePath: ["sub"])!
        // Which of the two links "owns" the bytes depends on scheduling; the total does not.
        XCTAssertGreaterThanOrEqual(r.root.allocatedSize, 100_000)
        XCTAssertLessThan(r.root.allocatedSize, 200_000)

        let c = DeletionList()
        c.add(sub)
        let outcome = await c.deleteAll(using: PosixRecursiveDeleter())
        XCTAssertEqual(outcome.failed.count, 0, "\(outcome.failed)")
        XCTAssertFalse(fm.fileExists(atPath: base + "/sub"))
        XCTAssertTrue(fm.fileExists(atPath: base + "/hardlink.bin"), "other hard link survives")
        XCTAssertTrue(fm.fileExists(atPath: base), "symlink target not followed by deleter")
        XCTAssertNil(r.root.descendant(atRelativePath: ["sub"]))
    }

    func testDeleterRefusesRootAndDoesNotFollowSymlinks() throws {
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: "/"))
        let base = NSTemporaryDirectory() + "diskrings-sl-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: base + "/target", withIntermediateDirectories: true)
        try Data([1]).write(to: URL(fileURLWithPath: base + "/target/keep"))
        try fm.createSymbolicLink(atPath: base + "/ln", withDestinationPath: base + "/target")
        defer { try? fm.removeItem(atPath: base) }
        try PosixRecursiveDeleter().deleteItem(atPath: base + "/ln")
        XCTAssertTrue(fm.fileExists(atPath: base + "/target/keep"))
        XCTAssertFalse((try? fm.destinationOfSymbolicLink(atPath: base + "/ln")) != nil)
    }
}
