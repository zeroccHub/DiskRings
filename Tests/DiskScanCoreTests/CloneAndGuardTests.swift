import XCTest
@testable import DiskScanCore

final class CloneAccountingTests: XCTestCase {
    func scan(_ items: [InMemoryDirectoryEnumerator.FakeItem], workers: Int = 4) throws -> ScanResult {
        try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", items),
                       options: ScanOptions(maxConcurrency: workers)).scanBlocking(path: "/r")
    }
    let share = BulkAttr.efMayShareBlocks

    func testClonesCountedOnceWithPrivateBytes() throws {
        // Three 1 MB clones of one family; two of them diverged by 8 KB / 0 KB.
        let r = try scan([
            .file(name: "a", size: 1_000_000, allocated: 1_003_520, cloneID: 9, privateSize: 0, extFlags: share),
            .dir(name: "d", [
                .file(name: "b", size: 1_000_000, allocated: 1_003_520, cloneID: 9, privateSize: 8192, extFlags: share),
                .file(name: "c", size: 1_000_000, allocated: 1_003_520, cloneID: 9, privateSize: 0, extFlags: share),
            ]),
        ])
        XCTAssertEqual(r.root.logicalSize, 3_000_000)
        XCTAssertEqual(r.root.allocatedSize, 3 * 1_003_520, "raw allocated is unchanged")
        // One full copy + private bytes of the later members. Which file is "first"
        // depends on scheduling, so the total is between the two possibilities.
        let possible: Set<UInt64> = [1_003_520 + 8192, 1_003_520 + 0]
        XCTAssertTrue(possible.contains(r.root.actualSize), "\(r.root.actualSize)")
        XCTAssertEqual(r.cloneDuplicates, 2)
        XCTAssertEqual(r.cloneSharedBytes, 3 * 1_003_520 - r.root.actualSize)
    }

    func testDeterministicWithOneWorker() throws {
        let r = try scan([
            .file(name: "a", size: 10, allocated: 40_960, cloneID: 1, privateSize: 0, extFlags: share),
            .file(name: "b", size: 10, allocated: 40_960, cloneID: 1, privateSize: 4096, extFlags: share),
        ], workers: 1)
        XCTAssertEqual(r.root.actualSize, 40_960 + 4096)
        let b = r.root.children.first { $0.name == "b" }!
        XCTAssertTrue(b.isCloneDuplicate)
        XCTAssertEqual(b.actualSize, 4096)
        XCTAssertEqual(b.allocatedSize, 40_960)
    }

    func testDifferentDevicesOrFamiliesAreIndependent() throws {
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", [
            .file(name: "a", size: 1, allocated: 4096, cloneID: 1, privateSize: 0, extFlags: share),
            .file(name: "b", size: 1, allocated: 4096, cloneID: 2, privateSize: 0, extFlags: share),
            .file(name: "c", size: 1, allocated: 4096, device: 5, cloneID: 1, privateSize: 0, extFlags: share),
        ]), options: ScanOptions(crossFilesystems: true)).scanBlocking(path: "/r")
        XCTAssertEqual(r.root.actualSize, 3 * 4096)
        XCTAssertEqual(r.cloneDuplicates, 0)
    }

    func testFlagsSayNotSharedMeansNoDedup() throws {
        // Same clone id reported but EF_MAY_SHARE_BLOCKS not set => charged fully.
        let r = try scan([
            .file(name: "a", size: 1, allocated: 4096, cloneID: 3, privateSize: 0, extFlags: 0),
            .file(name: "b", size: 1, allocated: 4096, cloneID: 3, privateSize: 0, extFlags: 0),
        ])
        XCTAssertEqual(r.root.actualSize, 8192)
    }

    func testFallbackWithoutCloneAttributes() throws {
        let r = try scan([.file(name: "a", size: 1, allocated: 4096), .file(name: "b", size: 1, allocated: 4096)])
        XCTAssertEqual(r.root.actualSize, r.root.allocatedSize)
        XCTAssertEqual(r.cloneDuplicates, 0)
    }

    func testHardLinksAndClonesDoNotDoubleSubtract() throws {
        // h1/h2: hard links of one inode that is itself a clone (id 7) of c.
        let r = try scan([
            .file(name: "h1", size: 100, allocated: 16_384, inode: 50, links: 2, cloneID: 7, privateSize: 4096, extFlags: share),
            .dir(name: "x", [
                .file(name: "h2", size: 100, allocated: 16_384, inode: 50, links: 2, cloneID: 7, privateSize: 4096, extFlags: share),
                .file(name: "c", size: 100, allocated: 16_384, cloneID: 7, privateSize: 4096, extFlags: share),
            ]),
        ], workers: 1)
        // Hard-link dup contributes 0; of the two remaining clone members one
        // is charged in full and one only its private bytes.
        XCTAssertEqual(r.hardLinkDuplicates, 1)
        XCTAssertEqual(r.cloneDuplicates, 1)
        XCTAssertEqual(r.root.actualSize, 16_384 + 4096)
        XCTAssertEqual(r.root.allocatedSize, 2 * 16_384)
        XCTAssertEqual(r.root.logicalSize, 200)
    }

    func testRemoveFromTreeSubtractsActual() throws {
        let r = try scan([
            .file(name: "a", size: 10, allocated: 40_960, cloneID: 1, privateSize: 0, extFlags: share),
            .file(name: "b", size: 10, allocated: 40_960, cloneID: 1, privateSize: 4096, extFlags: share),
        ], workers: 1)
        r.root.children.first { $0.name == "b" }!.removeFromTree()
        XCTAssertEqual(r.root.actualSize, 40_960)
        XCTAssertEqual(r.root.allocatedSize, 40_960)
    }

    func testPosixEnumeratorWithInjectedCloneInfo() throws {
        let base = NSTemporaryDirectory() + "diskrings-clone-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        for n in ["one", "two"] { try Data(repeating: 7, count: 50_000).write(to: URL(fileURLWithPath: base + "/" + n)) }
        let e = PosixDirectoryEnumerator(cloneInfoProvider: { _ in (cloneID: 42, privateSize: 0, extFlags: BulkAttr.efMayShareBlocks) })
        let r = try ScanEngine(enumerator: e, options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: base)
        XCTAssertEqual(r.cloneDuplicates, 1)
        XCTAssertEqual(r.root.actualSize * 2, r.root.allocatedSize)
    }
}

final class DeletionGuardTests: XCTestCase {
    func makeGuard(mounts: [String] = ["/", "/Volumes/External", "/System/Volumes/Data"],
                   flags: [String: UInt32] = [:],
                   symlinks: [String: String] = [:]) -> DeletionGuard {
        DeletionGuard(homeDirectory: "/Users/tester",
                      mountPoints: { mounts },
                      fileFlags: { flags[$0] },
                      resolveDirectory: { symlinks[$0] ?? $0 })
    }

    func testSystemLocationsBlocked() {
        let g = makeGuard()
        XCTAssertEqual(g.check("/System/Library/Fonts/x.ttf"), .systemLocation("/System"))
        XCTAssertEqual(g.check("/usr/bin/ls"), .systemLocation("/usr"))
        XCTAssertEqual(g.check("/bin"), .systemLocation("/bin"))
        XCTAssertEqual(g.check("/sbin/mount"), .systemLocation("/sbin"))
        XCTAssertEqual(g.check("/private/var/db/receipts"), .systemLocation("/private/var/db"))
        XCTAssertEqual(g.check("/Library/Apple/System"), .systemLocation("/Library/Apple"))
        XCTAssertEqual(g.check("/private/etc/hosts"), .systemLocation("/private/etc"))
    }

    func testUsrLocalAllowed() {
        let g = makeGuard()
        XCTAssertNil(g.check("/usr/local"))
        XCTAssertNil(g.check("/usr/local/bin/tool"))
        XCTAssertEqual(g.check("/usr/localfoo"), .systemLocation("/usr"), "prefix match is per component")
        XCTAssertEqual(g.check("/usr"), .systemLocation("/usr"))
    }

    func testAliasesAndFirmlinks() {
        let g = makeGuard()
        XCTAssertEqual(g.check("/etc/hosts"), .systemLocation("/private/etc"))
        XCTAssertEqual(g.check("/var/db/x"), .systemLocation("/private/var/db"))
        XCTAssertEqual(g.check("/System/Volumes/Data/private/etc/hosts"), .systemLocation("/private/etc"))
        XCTAssertEqual(g.check("/System/Volumes/Data/usr/bin/x"), .systemLocation("/usr"))
        XCTAssertNil(g.check("/System/Volumes/Data/Users/tester/Downloads/big.iso"), "user data via the Data volume path is fine")
        XCTAssertNil(g.check("/System/Volumes/Data/usr/local/lib/x"))
        XCTAssertEqual(g.check("/System/Volumes/Preboot/x"), .systemLocation("/System"))
        XCTAssertEqual(g.check("/System/Volumes/Data"), .volumeRoot("/System/Volumes/Data"))
        XCTAssertNil(g.check("/private/var/folders/xy/cache.bin"))
    }

    func testParentSymlinksResolved() {
        // /Users/tester/link-to-etc -> /private/etc ; deleting its child is deleting /private/etc/x
        let g = makeGuard(symlinks: ["/Users/tester/link-to-etc": "/private/etc"])
        XCTAssertEqual(g.check("/Users/tester/link-to-etc/hosts"), .systemLocation("/private/etc"))
        // ...but deleting the symlink itself only removes the link.
        XCTAssertNil(g.check("/Users/tester/link-to-etc"))
    }

    func testVolumeRootsHomeAndAncestors() {
        let g = makeGuard()
        XCTAssertEqual(g.check("/"), .filesystemRoot)
        XCTAssertEqual(g.check("/Volumes/External"), .volumeRoot("/Volumes/External"))
        XCTAssertEqual(g.check("/Volumes/External/"), .volumeRoot("/Volumes/External"))
        XCTAssertNil(g.check("/Volumes/External/Movies"))
        XCTAssertEqual(g.check("/Users/tester"), .homeFolder)
        XCTAssertEqual(g.check("/Users/tester/../tester/"), .unsafePath("contains '..'"), "paths with .. are refused")
        XCTAssertNil(g.check("/Users/tester/Downloads"))
        XCTAssertEqual(g.check("/Users"), .containsHomeFolder)
        XCTAssertEqual(g.check("/private"), .containsProtected("/private/var/db"))
        XCTAssertEqual(g.check("/Library"), .containsProtected("/Library/Apple"))
        XCTAssertEqual(g.check("/Applications"), .essentialFolder("/Applications"))
        XCTAssertNil(g.check("/Applications/Some.app"))
        XCTAssertNil(g.check("/Library/Caches/foo"))
    }

    func testSIPFlags() {
        let g = makeGuard(flags: ["/Applications/Safari.app": DeletionGuard.sfRestricted,
                                  "/Users/tester/locked": DeletionGuard.sfNoUnlink,
                                  "/Users/tester/plain": 0x8000 /* unrelated flag */])
        XCTAssertEqual(g.check("/Applications/Safari.app"), .sipProtected)
        XCTAssertEqual(g.check("/Users/tester/locked"), .sipProtected)
        XCTAssertNil(g.check("/Users/tester/plain"))
        XCTAssertTrue(DeletionGuard.Reason.sipProtected.description.contains("SIP"))
    }

    func testNormalize() {
        XCTAssertEqual(DeletionGuard.normalize("//a/./b/../c/"), "/a/c")
        XCTAssertEqual(DeletionGuard.normalize("/.."), "/")
    }

    func testVolumeScanTarget() {
        XCTAssertEqual(VolumeScanTarget.path(forVolumeAt: "/", isRootFileSystem: true, fileExists: { _ in true }), "/System/Volumes/Data")
        XCTAssertEqual(VolumeScanTarget.path(forVolumeAt: "/", isRootFileSystem: true, fileExists: { _ in false }), "/")
        XCTAssertEqual(VolumeScanTarget.path(forVolumeAt: "/Volumes/X", isRootFileSystem: false, fileExists: { _ in true }), "/Volumes/X")
    }

    @MainActor func testDeletionListRefusesAndDoubleChecks() async throws {
        let fs = InMemoryDirectoryEnumerator(rootPath: "/Users/tester", [
            .file(name: "a", size: 1, allocated: 4096), .file(name: "b", size: 1, allocated: 4096)])
        let root = try ScanEngine(enumerator: fs).scanBlocking(path: "/Users/tester").root
        var flags: [String: UInt32] = [:]
        let list = DeletionList(deletionGuard: DeletionGuard(homeDirectory: "/Users/tester", fileFlags: { flags[$0] }))
        XCTAssertFalse(list.add(root), "root/home never added")
        let a = root.children.first { $0.name == "a" }!
        let b = root.children.first { $0.name == "b" }!
        XCTAssertTrue(list.add(a))
        XCTAssertTrue(list.add(b))
        // The flag appears after the item was staged: executor must still refuse it.
        flags["/Users/tester/b"] = DeletionGuard.sfRestricted
        list.deletionGuard = DeletionGuard(homeDirectory: "/Users/tester", fileFlags: { flags[$0] })
        XCTAssertEqual(list.deletableItems.map(\.name), ["a"])
        final class Log: @unchecked Sendable { var paths: [String] = [] }
        struct Rec: ItemDeleting { let log: Log; func deleteItem(atPath p: String) throws { log.paths.append(p) } }
        let log = Log()
        let out = await list.deleteAll(using: Rec(log: log))
        XCTAssertEqual(log.paths, ["/Users/tester/a"])
        XCTAssertEqual(out.failed.count, 1)
        XCTAssertEqual(out.failed.first?.error as? DeletionError, .blocked(path: "/Users/tester/b", reason: .sipProtected))
        XCTAssertEqual(list.items.map(\.name), ["b"])
    }

    func testLiveGuardOnThisMachine() {
        let g = DeletionGuard.live()
        XCTAssertNotNil(g.check("/"))
        XCTAssertNotNil(g.check(NSHomeDirectory()))
        XCTAssertNotNil(g.check("/usr/bin"))
        XCTAssertNil(g.check(NSTemporaryDirectory() + "some-file-\(UUID().uuidString)"))
    }
}

// MARK: - Round 3 QA fixes

final class R3FixTests: XCTestCase {
    let share = BulkAttr.efMayShareBlocks

    func testDeviceIDBitPatternMatchesLstatRule() {
        XCTAssertEqual(DeviceID.key(Int32(-5)), UInt64(UInt32(bitPattern: -5)))
        XCTAssertEqual(DeviceID.key(UInt64(1) << 40), UInt64(1) << 40)
        XCTAssertEqual(DeviceID.key(Int32(16777220)), 16777220)
    }

    func testClonePrimaryIsLowestInodeRegardlessOfOrderAndWorkers() throws {
        // Primary is inode 3 ("z"), even though it is listed last and in a subfolder.
        for workers in [1, 8] {
            let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", [
                .file(name: "a", size: 1, allocated: 40_960, inode: 10, cloneID: 4, privateSize: 4096, extFlags: share),
                .dir(name: "d", [
                    .file(name: "z", size: 1, allocated: 40_960, inode: 3, cloneID: 4, privateSize: 0, extFlags: share),
                ]),
            ]), options: ScanOptions(maxConcurrency: workers)).scanBlocking(path: "/r")
            let a = r.root.children.first { $0.name == "a" }!
            let z = r.root.children.first { $0.name == "d" }!.children[0]
            XCTAssertFalse(z.isCloneDuplicate)
            XCTAssertTrue(a.isCloneDuplicate)
            XCTAssertEqual(z.actualSize, 40_960)
            XCTAssertEqual(a.actualSize, 4096)
        }
    }

    func testUnknownPrivateSizeIsChargedInFull() throws {
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", [
            .file(name: "a", size: 1, allocated: 8192, cloneID: 5, extFlags: share),
            .file(name: "b", size: 1, allocated: 8192, cloneID: 5, extFlags: share),
        ]), options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/r")
        XCTAssertEqual(r.root.actualSize, 16_384)
        XCTAssertEqual(r.cloneDuplicates, 0)
    }

    func g(_ subtree: DeletionGuard.SubtreeIssue? = nil, mounts: [String] = ["/"]) -> DeletionGuard {
        DeletionGuard(homeDirectory: "/Users/tester", mountPoints: { mounts }, inspectSubtree: { _ in subtree })
    }

    func testPreflightRefusesWholeItem() {
        XCTAssertNil(g(.otherDevice("/Users/tester/x/m")).check("/Users/tester/x"), "fast check skips the walk")
        XCTAssertEqual(g(.otherDevice("/Users/tester/x/m")).evaluate("/Users/tester/x", preflight: true).reason,
                       .containsOtherDevice("/Users/tester/x/m"))
        XCTAssertEqual(g(.restricted("/Users/tester/x/s")).evaluate("/Users/tester/x", preflight: true).reason,
                       .containsRestricted("/Users/tester/x/s"))
        XCTAssertEqual(g(.unreadable("/Users/tester/x/u")).evaluate("/Users/tester/x", preflight: true).reason,
                       .contentsNotVerifiable("/Users/tester/x/u"))
    }

    func testCaseInsensitiveMountAndCaution() {
        XCTAssertEqual(g(mounts: ["/", "/Volumes/Ext"]).check("/volumes/ext"), .volumeRoot("/volumes/ext"))
        XCTAssertEqual(g().caution(for: "/Library/LaunchDaemons/com.x.plist"), .launchdJob("/Library/LaunchDaemons/com.x.plist"))
        XCTAssertEqual(g().caution(for: "/library/launchagents"), .launchdJob("/library/launchagents"))
        XCTAssertEqual(g().caution(for: "/Applications/Foo.app"), .applicationBundle("/Applications/Foo.app"))
        XCTAssertEqual(g().caution(for: "/Applications/Foo.app/Contents/x"), .applicationBundle("/Applications/Foo.app/Contents/x"))
        XCTAssertEqual(g().caution(for: "/var/folders/ab/T/x"), .systemTempFolders("/var/folders/ab/T/x"))
        XCTAssertNil(g().caution(for: "/Applications/Utilities"))
        XCTAssertNil(g().caution(for: "/Users/tester/Downloads/x.app"))
        XCTAssertNil(g().caution(for: "/System/Library"), "blocked items have no caution")
    }

    func testVerdictUsesResolvedRealPathNotAlias() {
        let gd = DeletionGuard(homeDirectory: "/Users/tester", resolveDirectory: { $0 == "/Users/tester/l" ? "/Users/tester/real" : $0 })
        XCTAssertEqual(gd.evaluate("/Users/tester/l/f").canonicalPath, "/Users/tester/real/f")
        XCTAssertEqual(gd.evaluate("/tmp/x").canonicalPath, "/tmp/x", "alias mapping only affects rule matching")
    }

    @MainActor
    func testDeleteAllSkipsCautionUntilConfirmedAndUsesCanonicalPath() async throws {
        final class Recorder: ItemDeleting, @unchecked Sendable {
            var paths: [String] = []
            func deleteItem(atPath path: String) throws { paths.append(path) }
        }
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/Applications", [
            .file(name: "Foo.app", size: 1, allocated: 4096),
        ]), options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/Applications")
        let gd = DeletionGuard(homeDirectory: "/Users/tester", resolveItem: { $0 == "/Applications/Foo.app" ? "/Applications/FOO.app" : $0 })
        let list = DeletionList(deletionGuard: gd)
        XCTAssertTrue(list.add(r.root.children[0]))
        XCTAssertEqual(list.cautionItems.count, 1)
        let rec = Recorder()
        var o = await list.deleteAll(using: rec)
        XCTAssertEqual(o.deleted.count, 0)
        if case .needsConfirmation? = o.failed.first?.error as? DeletionError {} else { XCTFail("\(o.failed)") }
        o = await list.deleteAll(using: rec, confirmedCautions: true)
        XCTAssertEqual(o.deleted.count, 1)
        XCTAssertEqual(rec.paths, ["/Applications/FOO.app"], "deletes the exact canonical path the guard judged")
    }

    func testIdentityMismatchRefusesDelete() throws {
        let fm = FileManager.default
        let base = NSTemporaryDirectory() + "dr-id-\(UUID().uuidString)"
        try fm.createDirectory(atPath: base + "/d/e", withIntermediateDirectories: true)
        _ = fm.createFile(atPath: base + "/d/e/f", contents: Data([1, 2, 3]))
        defer { try? fm.removeItem(atPath: base) }
        let real = FileIdentity.of(base + "/d")!
        let wrong = FileIdentity(device: real.device, inode: real.inode &+ 1)
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: base + "/d", expected: wrong))
        XCTAssertTrue(fm.fileExists(atPath: base + "/d/e/f"))
        try PosixRecursiveDeleter().deleteItem(atPath: base + "/d", expected: real)
        XCTAssertFalse(fm.fileExists(atPath: base + "/d"))
    }

    func testLiveSubtreeInspectionAndSymlinkNotFollowed() throws {
        let fm = FileManager.default
        let base = NSTemporaryDirectory() + "dr-sub-\(UUID().uuidString)"
        try fm.createDirectory(atPath: base + "/a/b", withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: base + "/a/lnk", withDestinationPath: "/proc")
        defer { try? fm.removeItem(atPath: base) }
        XCTAssertNil(DeletionGuard.liveInspectSubtree(base + "/a"), "symlink to another fs is not followed")
        #if os(Linux)
        if fm.fileExists(atPath: "/proc/self") {
            XCTAssertNotNil(DeletionGuard.liveInspectSubtree("/dev"), "/dev contains other mounts (devpts/shm) or unreadable dirs")
        }
        #endif
        // Delete leaves the symlink target alone.
        try PosixRecursiveDeleter().deleteItem(atPath: base + "/a")
        XCTAssertFalse(fm.fileExists(atPath: base + "/a"))
        XCTAssertTrue(fm.fileExists(atPath: "/proc"))
    }
}
