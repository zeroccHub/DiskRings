import XCTest
@testable import DiskScanCore

final class ScanEngineTests: XCTestCase {
    typealias F = InMemoryDirectoryEnumerator.FakeItem

    func makeEngine(_ fs: DirectoryEnumerator, workers: Int = 4, cross: Bool = false) -> ScanEngine {
        ScanEngine(enumerator: fs, options: ScanOptions(crossFilesystems: cross, maxConcurrency: workers, progressInterval: 0))
    }

    func testAggregatesSizesBottomUpAndSortsChildren() throws {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
            .file(name: "a.bin", size: 100, allocated: 4096),
            .dir(name: "big", [
                .file(name: "x", size: 10_000, allocated: 12_288),
                .dir(name: "deeper", [.file(name: "y", size: 1, allocated: 4096)]),
            ]),
            .dir(name: "empty", []),
        ])
        let result = try makeEngine(fs).scanBlocking(path: "/r/")
        let root = result.root
        XCTAssertEqual(root.name, "/r")
        XCTAssertEqual(root.allocatedSize, 4096 + 12_288 + 4096)
        XCTAssertEqual(root.logicalSize, 100 + 10_000 + 1)
        XCTAssertEqual(root.itemCount, 3)
        XCTAssertEqual(root.children.map(\.name), ["big", "a.bin", "empty"])
        let big = root.children[0]
        XCTAssertEqual(big.allocatedSize, 16_384)
        XCTAssertTrue(big.parent === root)
        XCTAssertEqual(root.descendant(atRelativePath: ["big", "deeper", "y"])?.path, "/r/big/deeper/y")
        XCTAssertEqual(result.progress.directoriesScanned, 4)
        XCTAssertEqual(result.progress.filesSeen, 3)
        XCTAssertTrue(result.progress.isFinished)
        XCTAssertEqual(fs.enumeratedDirectories.count, 4, "each directory enumerated exactly once")
    }

    func testHardLinksCountedOnce() throws {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
            .dir(name: "one", [.file(name: "h", size: 5000, allocated: 8192, inode: 77, links: 3)]),
            .dir(name: "two", [.file(name: "h2", size: 5000, allocated: 8192, inode: 77, links: 3)]),
            .file(name: "h3", size: 5000, allocated: 8192, inode: 77, links: 3),
            // same inode number on a different device is a different file
            .file(name: "other-dev", size: 5000, allocated: 8192, inode: 77, links: 2, device: 9),
        ])
        let result = try makeEngine(fs, cross: true).scanBlocking(path: "/r")
        XCTAssertEqual(result.root.allocatedSize, 8192 * 2)
        XCTAssertEqual(result.hardLinkDuplicates, 2)
        var dupes = 0
        var stack = [result.root]
        while let n = stack.popLast() { if n.isHardLinkDuplicate { dupes += 1 }; stack += n.children }
        XCTAssertEqual(dupes, 2)
    }

    func testDoesNotCrossFilesystemsByDefault() throws {
        let items: [F] = [
            .file(name: "local", size: 10, allocated: 4096),
            .dir(name: "mnt", device: 2, [.file(name: "remote", size: 10, allocated: 1_000_000)]),
            .dir(name: "flagged", mountPoint: true, [.file(name: "z", size: 1, allocated: 4096)]),
        ]
        let r1 = try makeEngine(InMemoryDirectoryEnumerator(rootPath: "/r", items)).scanBlocking(path: "/r")
        XCTAssertEqual(r1.root.allocatedSize, 4096)
        let mnt = r1.root.children.first { $0.name == "mnt" }!
        XCTAssertTrue(mnt.isOtherFilesystem)
        XCTAssertTrue(mnt.children.isEmpty)
        XCTAssertTrue(r1.root.children.first { $0.name == "flagged" }!.isOtherFilesystem)

        let r2 = try makeEngine(InMemoryDirectoryEnumerator(rootPath: "/r", items), cross: true).scanBlocking(path: "/r")
        XCTAssertEqual(r2.root.allocatedSize, 4096 + 1_000_000 + 4096)
    }

    func testSymlinksAreNotFollowed() throws {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [.symlink(name: "link"), .dir(name: "d", [])])
        let r = try makeEngine(fs).scanBlocking(path: "/r")
        let link = r.root.children.first { $0.name == "link" }!
        XCTAssertEqual(link.kind, .symlink)
        XCTAssertTrue(link.children.isEmpty)
        XCTAssertEqual(fs.enumeratedDirectories.count, 2)
    }

    func testUnreadableDirectoriesAreMarkedAndScanContinues() throws {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
            .dir(name: "secret", unreadable: true, [.file(name: "s", size: 1)]),
            .file(name: "ok", size: 1, allocated: 4096),
        ])
        let r = try makeEngine(fs).scanBlocking(path: "/r")
        XCTAssertTrue(r.root.children.first { $0.name == "secret" }!.isRestricted)
        XCTAssertEqual(r.restrictedPaths, ["/r/secret"])
        XCTAssertEqual(r.progress.restrictedDirectories, 1)
        XCTAssertEqual(r.root.allocatedSize, 4096)
    }

    func testRootErrors() {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [])
        XCTAssertThrowsError(try makeEngine(fs).scanBlocking(path: "/missing")) { err in
            guard case ScanError.rootUnreadable = err else { return XCTFail("\(err)") }
        }
    }

    /// Big synthetic tree: results must be identical regardless of worker count.
    func testConcurrentScanMatchesSerialScan() throws {
        func build(_ depth: Int, _ prefix: String) -> [F] {
            if depth == 0 { return (0..<5).map { .file(name: "\(prefix)f\($0)", size: UInt64($0 * 1000 + depth)) } }
            var items: [F] = (0..<3).map { .file(name: "\(prefix)f\($0)", size: UInt64(100 * $0 + 7)) }
            for i in 0..<4 { items.append(.dir(name: "\(prefix)d\(i)", build(depth - 1, "\(prefix)\(i)"))) }
            return items
        }
        let tree = build(5, "")
        let serial = try makeEngine(InMemoryDirectoryEnumerator(rootPath: "/big", tree), workers: 1).scanBlocking(path: "/big")
        let parallel = try makeEngine(InMemoryDirectoryEnumerator(rootPath: "/big", tree), workers: 8).scanBlocking(path: "/big")
        XCTAssertEqual(serial.root.allocatedSize, parallel.root.allocatedSize)
        XCTAssertEqual(serial.root.logicalSize, parallel.root.logicalSize)
        XCTAssertEqual(serial.root.itemCount, parallel.root.itemCount)
        XCTAssertEqual(serial.progress.directoriesScanned, 1 + 4 + 16 + 64 + 256 + 1024)
        XCTAssertEqual(parallel.progress.directoriesScanned, serial.progress.directoriesScanned)
        func signature(_ n: FileNode) -> String { n.name + ":" + String(n.allocatedSize) + "[" + n.children.map(signature).joined(separator: ",") + "]" }
        XCTAssertEqual(signature(serial.root), signature(parallel.root))
    }

    /// Enumerator that is slow and lets the test cancel mid-scan.
    final class SlowFS: DirectoryEnumerator, @unchecked Sendable {
        func rootEntry(at path: String) throws -> DirectoryEntry {
            DirectoryEntry(name: path, kind: .directory, device: 1, fileID: 1)
        }
        func entries(inDirectoryAt path: String) throws -> [DirectoryEntry] {
            Thread.sleep(forTimeInterval: 0.005)
            return (0..<4).map { DirectoryEntry(name: "d\($0)", kind: .directory, device: 1, fileID: UInt64($0)) } // infinite tree
        }
    }

    func testCancellationStopsInfiniteScan() {
        let token = ScanCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { token.cancel() }
        let start = Date()
        XCTAssertThrowsError(try makeEngine(SlowFS()).scanBlocking(path: "/inf", cancellation: token)) { err in
            XCTAssertEqual(err as? ScanError, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testAsyncScanAndTaskCancellation() async throws {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [.file(name: "a", size: 1, allocated: 4096)])
        let counter = ProgressCounter()
        let r = try await makeEngine(fs).scan(path: "/r") { _ in counter.bump() }
        XCTAssertEqual(r.root.allocatedSize, 4096)
        XCTAssertGreaterThan(counter.value, 0)

        let engine = makeEngine(SlowFS())
        let task = Task { try await engine.scan(path: "/inf") }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? ScanError, .cancelled)
        }
    }

    final class ProgressCounter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func testSizeText() {
        XCTAssertEqual(SizeText.format(0), "0 bytes")
        XCTAssertEqual(SizeText.format(1), "1 byte")
        XCTAssertEqual(SizeText.format(1_500), "1.5 KB")
        XCTAssertEqual(SizeText.format(250_000_000), "250 MB")
        XCTAssertEqual(SizeText.format(3_210_000_000_000), "3.2 TB")
    }
}
