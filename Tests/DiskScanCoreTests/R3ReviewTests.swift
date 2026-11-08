// Added by R3 acceptance review. Tests named testBUG_* are EXPECTED TO FAIL on
// the delivered code: they encode the safe behaviour the review asks for.
import XCTest
@testable import DiskScanCore

final class R3ReviewGuardTests: XCTestCase {
    func g(mounts: [String] = ["/", "/System/Volumes/Data"], symlinks: [String: String] = [:]) -> DeletionGuard {
        DeletionGuard(homeDirectory: "/Users/tester", mountPoints: { mounts },
                      fileFlags: { _ in nil }, resolveDirectory: { symlinks[$0] ?? $0 })
    }
    // APFS default is case-insensitive: /USR is the same directory as /usr.
    func testBUG_caseInsensitiveTopLevel() {
        XCTAssertNotNil(g().check("/USR"))
        XCTAssertNotNil(g().check("/system"))
        XCTAssertNotNil(g().check("/LIBRARY"))
        XCTAssertNotNil(g().check("/users/tester"))
    }
    func testBUG_caseInsensitiveNested() {
        XCTAssertNotNil(g().check("/usr/LOCAL/../BIN/ls".replacingOccurrences(of: "/../BIN", with: "/../bin")))
        XCTAssertNotNil(g().check("/System/LIBRARY/CoreServices"))  // still /System -> ok
        XCTAssertNotNil(g().check("/Private/Etc/hosts"))
    }
    // `..` is collapsed lexically BEFORE symlinks are resolved. The kernel
    // resolves /tmp/lnk/.. as the parent of the symlink TARGET.
    func testBUG_dotDotAfterSymlinkIsLexical() {
        let gd = g(symlinks: ["/private/tmp/lnk": "/System/Library"])
        XCTAssertNotNil(gd.check("/tmp/lnk/../Library"), "kernel path is /System/Library")
    }
    // Rule only blocks ancestors of the static prefix list, not arbitrary
    // protected descendants (mount points / SIP items inside the folder).
    func testBUG_parentOfMountPointNotBlocked() {
        let gd = g(mounts: ["/", "/Users/tester/mnt/disk"])
        XCTAssertNotNil(gd.check("/Users/tester/mnt"), "contains a mounted volume")
    }
    // Observations (pass/fail documents current policy, not necessarily a bug):
    func testPolicy_volumesChildNotInMountList() {
        // A stale folder under /Volumes (not a mount) is deletable; acceptable.
        XCTAssertNil(g().check("/Volumes/StaleFolder"))
    }
    func testPolicy_systemLaunchDaemonsAreDeletable() {
        // Documented as allowed; reviewer flags as P2 policy gap.
        XCTAssertNil(g().check("/Library/LaunchDaemons"))
        XCTAssertNil(g().check("/private/var/folders"))
    }
    func testDataVolumeFirmlinkCaseVariant() {
        XCTAssertNotNil(g().check("/System/Volumes/Data/usr/bin")) // -> /usr/bin
        XCTAssertNotNil(g().check("/system/volumes/data"), "case variant of Data volume root")
    }
}

final class R3ReviewCloneTests: XCTestCase {
    let share = BulkAttr.efMayShareBlocks
    func scan(_ items: [InMemoryDirectoryEnumerator.FakeItem]) throws -> ScanResult {
        try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", items),
                       options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/r")
    }
    // R4 (P3 decision): unknown extFlags / private size => NO dedup, each member charged in full (conservative).
    func testUnknownFlagsAndPrivateChargedInFull() throws {
        let r = try scan([
            .file(name: "a", size: 1, allocated: 8192, cloneID: 5),
            .file(name: "b", size: 1, allocated: 8192, cloneID: 5),
        ])
        XCTAssertEqual(r.root.actualSize, 16384)
        XCTAssertEqual(r.cloneDuplicates, 0)
    }
    // privateSize > allocated must not underflow / trap (clamped).
    func testPrivateLargerThanAllocatedClamped() throws {
        let r = try scan([
            .file(name: "a", size: 1, allocated: 4096, cloneID: 6, privateSize: 0, extFlags: share),
            .file(name: "b", size: 1, allocated: 4096, cloneID: 6, privateSize: 1 << 40, extFlags: share),
        ])
        XCTAssertEqual(r.root.actualSize, 8192)
        XCTAssertEqual(r.cloneSharedBytes, 0)
    }
    // Hard link seen first via the 2nd name still registers the clone family once.
    func testThreeHardLinksOfCloneMember() throws {
        let r = try scan([
            .file(name: "h1", size: 1, allocated: 4096, inode: 9, links: 3, cloneID: 1, privateSize: 0, extFlags: share),
            .file(name: "h2", size: 1, allocated: 4096, inode: 9, links: 3, cloneID: 1, privateSize: 0, extFlags: share),
            .file(name: "h3", size: 1, allocated: 4096, inode: 9, links: 3, cloneID: 1, privateSize: 0, extFlags: share),
        ])
        XCTAssertEqual(r.root.actualSize, 4096)
        XCTAssertEqual(r.hardLinkDuplicates, 2)
        XCTAssertEqual(r.cloneDuplicates, 0)
    }
}
