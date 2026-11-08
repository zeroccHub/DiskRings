// Dependency-free self-test runner for DiskScanCore + SunburstGeometry.
// Compiled by `./build.sh test` together with the core sources as ONE module
// (-D SINGLE_MODULE), so it works with Command Line Tools that lack XCTest.
// The full XCTest suite lives in Tests/ (run with `swift test`).
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

var passed = 0
var failures: [String] = []
var currentTest = ""

@MainActor func check(_ cond: @autoclosure () -> Bool, _ msg: String = "", line: Int = #line) {
    if !cond() { failures.append("\(currentTest) (line \(line)) \(msg)") }
}
@MainActor func checkEq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: Int = #line) {
    if a != b { failures.append("\(currentTest) (line \(line)) expected \(b), got \(a) \(msg)") }
}
@MainActor func checkClose(_ a: Double, _ b: Double, _ eps: Double = 1e-9, line: Int = #line) {
    if abs(a - b) > eps { failures.append("\(currentTest) (line \(line)) expected \(b) ± \(eps), got \(a)") }
}
@MainActor func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    let before = failures.count
    do { try body() } catch { failures.append("\(name): threw \(error)") }
    if failures.count == before { passed += 1; print("  ok   \(name)") } else { print("  FAIL \(name)") }
}
@MainActor func testAsync(_ name: String, _ body: () async throws -> Void) async {
    currentTest = name
    let before = failures.count
    do { try await body() } catch { failures.append("\(name): threw \(error)") }
    if failures.count == before { passed += 1; print("  ok   \(name)") } else { print("  FAIL \(name)") }
}

typealias F = InMemoryDirectoryEnumerator.FakeItem
func engine(_ fs: DirectoryEnumerator, workers: Int = 4, cross: Bool = false) -> ScanEngine {
    ScanEngine(enumerator: fs, options: ScanOptions(crossFilesystems: cross, maxConcurrency: workers, progressInterval: 0))
}

print("DiskRings self-test")

// MARK: core
test("aggregate sizes and sort") {
    let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
        .file(name: "a.bin", size: 100, allocated: 4096),
        .dir(name: "big", [.file(name: "x", size: 10_000, allocated: 12_288),
                           .dir(name: "deeper", [.file(name: "y", size: 1, allocated: 4096)])]),
        .dir(name: "empty", []),
    ])
    let r = try engine(fs).scanBlocking(path: "/r/")
    checkEq(r.root.allocatedSize, 20_480)
    checkEq(r.root.logicalSize, 10_101)
    checkEq(r.root.children.map(\.name), ["big", "a.bin", "empty"])
    checkEq(r.root.descendant(atRelativePath: ["big", "deeper", "y"])?.path, "/r/big/deeper/y")
    checkEq(fs.enumeratedDirectories.count, 4)
}

test("hard links counted once") {
    let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
        .dir(name: "one", [.file(name: "h", size: 5000, allocated: 8192, inode: 77, links: 3)]),
        .dir(name: "two", [.file(name: "h2", size: 5000, allocated: 8192, inode: 77, links: 3)]),
        .file(name: "h3", size: 5000, allocated: 8192, inode: 77, links: 3),
    ])
    let r = try engine(fs).scanBlocking(path: "/r")
    checkEq(r.root.allocatedSize, 8192)
    checkEq(r.hardLinkDuplicates, 2)
}

test("does not cross filesystems by default") {
    let items: [F] = [.file(name: "local", size: 10, allocated: 4096),
                      .dir(name: "mnt", device: 2, [.file(name: "remote", size: 10, allocated: 1_000_000)]),
                      .dir(name: "flagged", mountPoint: true, [.file(name: "z", size: 1, allocated: 4096)])]
    let r1 = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", items)).scanBlocking(path: "/r")
    checkEq(r1.root.allocatedSize, 4096)
    check(r1.root.children.first { $0.name == "mnt" }!.isOtherFilesystem)
    let r2 = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", items), cross: true).scanBlocking(path: "/r")
    checkEq(r2.root.allocatedSize, 4096 + 1_000_000 + 4096)
}

test("unreadable dirs marked, symlinks not followed") {
    let fs = InMemoryDirectoryEnumerator(rootPath: "/r", [
        .dir(name: "secret", unreadable: true, [.file(name: "s", size: 1)]),
        .symlink(name: "ln"), .file(name: "ok", size: 1, allocated: 4096)])
    let r = try engine(fs).scanBlocking(path: "/r")
    check(r.root.children.first { $0.name == "secret" }!.isRestricted)
    checkEq(r.restrictedPaths, ["/r/secret"])
    checkEq(r.root.children.first { $0.name == "ln" }!.kind, .symlink)
}

test("parallel scan equals serial scan") {
    func build(_ d: Int, _ p: String) -> [F] {
        if d == 0 { return (0..<5).map { .file(name: "\(p)f\($0)", size: UInt64($0 * 1000 + 3)) } }
        var items: [F] = (0..<3).map { .file(name: "\(p)f\($0)", size: UInt64(100 * $0 + 7)) }
        for i in 0..<4 { items.append(.dir(name: "\(p)d\(i)", build(d - 1, "\(p)\(i)"))) }
        return items
    }
    let tree = build(5, "")
    let s = try engine(InMemoryDirectoryEnumerator(rootPath: "/b", tree), workers: 1).scanBlocking(path: "/b")
    let p = try engine(InMemoryDirectoryEnumerator(rootPath: "/b", tree), workers: 8).scanBlocking(path: "/b")
    checkEq(s.root.allocatedSize, p.root.allocatedSize)
    checkEq(p.progress.directoriesScanned, 1365)
}

final class SlowFS: DirectoryEnumerator, @unchecked Sendable {
    func rootEntry(at path: String) throws -> DirectoryEntry { DirectoryEntry(name: path, kind: .directory, device: 1, fileID: 1) }
    func entries(inDirectoryAt path: String) throws -> [DirectoryEntry] {
        Thread.sleep(forTimeInterval: 0.005)
        return (0..<4).map { DirectoryEntry(name: "d\($0)", kind: .directory, device: 1, fileID: UInt64($0)) }
    }
}
test("cancellation") {
    let token = ScanCancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { token.cancel() }
    do { _ = try engine(SlowFS()).scanBlocking(path: "/inf", cancellation: token); check(false, "no throw") }
    catch { checkEq(error as? ScanError, .cancelled) }
}

test("bulk attribute parser") {
    var b: [UInt8] = []
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { b.append(contentsOf: $0) } }
    let common = BulkAttr.cmnReturnedAttrs | BulkAttr.cmnName | BulkAttr.cmnDevID | BulkAttr.cmnObjType | BulkAttr.cmnFileID
    let file = BulkAttr.fileLinkCount | BulkAttr.fileTotalSize | BulkAttr.fileAllocSize
    put(UInt32(0)); put(common); put(UInt32(0)); put(UInt32(0)); put(file); put(UInt32(0))
    let nameRef = b.count; put(Int32(0)); put(UInt32(0))
    put(Int32(7)); put(BulkAttr.vReg); put(UInt64(42)); put(UInt32(2)); put(Int64(12345)); put(Int64(16384))
    let nameStart = b.count; b += Array("doc.txt".utf8) + [0]; while b.count % 4 != 0 { b.append(0) }
    withUnsafeBytes(of: Int32(nameStart - nameRef).littleEndian) { for (i, x) in $0.enumerated() { b[nameRef + i] = x } }
    withUnsafeBytes(of: UInt32(8).littleEndian) { for (i, x) in $0.enumerated() { b[nameRef + 4 + i] = x } }
    withUnsafeBytes(of: UInt32(b.count).littleEndian) { for (i, x) in $0.enumerated() { b[i] = x } }
    let e = try b.withUnsafeBytes { try BulkAttributeParser.parse($0, count: 1) }
    checkEq(e, [DirectoryEntry(name: "doc.txt", kind: .file, device: 7, fileID: 42, linkCount: 2, logicalSize: 12345, allocatedSize: 16384)])
}

test("size text") {
    checkEq(SizeText.format(1_500), "1.5 KB")
    checkEq(SizeText.format(250_000_000), "250 MB")
}

// MARK: APFS clones
let shareFlag = BulkAttr.efMayShareBlocks
test("clone family counted once (first full, rest private bytes)") {
    let r = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", [
        .file(name: "a", size: 10, allocated: 40_960, cloneID: 1, privateSize: 0, extFlags: shareFlag),
        .file(name: "b", size: 10, allocated: 40_960, cloneID: 1, privateSize: 4096, extFlags: shareFlag),
    ]), workers: 1).scanBlocking(path: "/r")
    checkEq(r.root.actualSize, 40_960 + 4096)
    checkEq(r.root.allocatedSize, 81_920)
    checkEq(r.cloneDuplicates, 1)
    check(r.root.children.first { $0.name == "b" }!.isCloneDuplicate)
}
test("hard links + clones do not double-subtract") {
    let r = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", [
        .file(name: "h1", size: 100, allocated: 16_384, inode: 50, links: 2, cloneID: 7, privateSize: 4096, extFlags: shareFlag),
        .file(name: "h2", size: 100, allocated: 16_384, inode: 50, links: 2, cloneID: 7, privateSize: 4096, extFlags: shareFlag),
        .file(name: "c", size: 100, allocated: 16_384, cloneID: 7, privateSize: 4096, extFlags: shareFlag),
    ]), workers: 1).scanBlocking(path: "/r")
    checkEq(r.hardLinkDuplicates, 1)
    checkEq(r.cloneDuplicates, 1)
    checkEq(r.root.actualSize, 16_384 + 4096)
}
test("fallback without clone attributes / flags say not shared") {
    let r1 = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", [
        .file(name: "a", size: 1, allocated: 4096), .file(name: "b", size: 1, allocated: 4096)])).scanBlocking(path: "/r")
    checkEq(r1.root.actualSize, r1.root.allocatedSize)
    let r2 = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", [
        .file(name: "a", size: 1, allocated: 4096, cloneID: 3, privateSize: 0, extFlags: 0),
        .file(name: "b", size: 1, allocated: 4096, cloneID: 3, privateSize: 0, extFlags: 0)])).scanBlocking(path: "/r")
    checkEq(r2.root.actualSize, 8192)
}
test("bulk parser: commonext group after file group") {
    var b: [UInt8] = []
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { b.append(contentsOf: $0) } }
    let common = BulkAttr.cmnReturnedAttrs | BulkAttr.cmnName | BulkAttr.cmnObjType
    put(UInt32(0)); put(common); put(UInt32(0)); put(UInt32(0)); put(BulkAttr.fileAllocSize); put(BulkAttr.cmnextPrivateSize | BulkAttr.cmnextCloneID | BulkAttr.cmnextExtFlags)
    let nameRef = b.count; put(Int32(0)); put(UInt32(0))
    put(BulkAttr.vReg); put(Int64(65_536)); put(Int64(8192)); put(UInt64(0xC10E)); put(UInt64(1))
    let nameStart = b.count; b += Array("c".utf8) + [0]; while b.count % 4 != 0 { b.append(0) }
    withUnsafeBytes(of: Int32(nameStart - nameRef).littleEndian) { for (i, x) in $0.enumerated() { b[nameRef + i] = x } }
    withUnsafeBytes(of: UInt32(2).littleEndian) { for (i, x) in $0.enumerated() { b[nameRef + 4 + i] = x } }
    withUnsafeBytes(of: UInt32(b.count).littleEndian) { for (i, x) in $0.enumerated() { b[i] = x } }
    let e = try b.withUnsafeBytes { try BulkAttributeParser.parse($0, count: 1) }
    checkEq(e.first?.allocatedSize, 65_536)
    checkEq(e.first?.privateSize, 8192)
    checkEq(e.first?.cloneID, 0xC10E)
    checkEq(e.first?.extFlags, 1)
}

// MARK: deletion guard
test("deletion guard rules") {
    let g = DeletionGuard(homeDirectory: "/Users/tester", mountPoints: { ["/", "/Volumes/Ext"] },
                          fileFlags: { $0 == "/Applications/Safari.app" ? DeletionGuard.sfRestricted : nil },
                          resolveDirectory: { $0 == "/Users/tester/etc-link" ? "/private/etc" : $0 })
    checkEq(g.check("/"), .filesystemRoot)
    checkEq(g.check("/System/Library/x"), .systemLocation("/System"))
    checkEq(g.check("/usr/bin/ls"), .systemLocation("/usr"))
    check(g.check("/usr/local/bin/x") == nil)
    checkEq(g.check("/etc/hosts"), .systemLocation("/private/etc"))
    checkEq(g.check("/var/db/x"), .systemLocation("/private/var/db"))
    checkEq(g.check("/System/Volumes/Data/private/etc/x"), .systemLocation("/private/etc"))
    check(g.check("/System/Volumes/Data/Users/tester/Movies/a.mov") == nil)
    checkEq(g.check("/Users/tester/etc-link/hosts"), .systemLocation("/private/etc"))
    checkEq(g.check("/Volumes/Ext"), .volumeRoot("/Volumes/Ext"))
    checkEq(g.check("/Users/tester"), .homeFolder)
    checkEq(g.check("/Users"), .containsHomeFolder)
    check(g.check("/Users/tester/Downloads") == nil)
    checkEq(g.check("/Applications/Safari.app"), .sipProtected)
    checkEq(g.check("/bin"), .systemLocation("/bin"))
    checkEq(g.check("/Library/Apple/x"), .systemLocation("/Library/Apple"))
    // round-3 QA: case variants, `..`, mount-point ancestors, cautions
    check(g.check("/USR") != nil && g.check("/system") != nil && g.check("/users/tester") != nil)
    checkEq(g.check("/tmp/lnk/../Library"), .unsafePath("contains '..'"))
    check(g.check("/Volumes") != nil)
    let g2 = DeletionGuard(homeDirectory: "/Users/tester", mountPoints: { ["/", "/Users/tester/mnt/d"] })
    checkEq(g2.check("/Users/tester/mnt"), .containsVolume("/Users/tester/mnt/d"))
    checkEq(g2.caution(for: "/Library/LaunchDaemons/x.plist"), .launchdJob("/Library/LaunchDaemons/x.plist"))
    check(g2.caution(for: "/Applications/X.app") != nil)
}
test("clone primary deterministic + unknown private size charged in full") {
    let fs: [F] = [
        .file(name: "a", size: 1, allocated: 40_960, inode: 10, cloneID: 4, privateSize: 4096, extFlags: shareFlag),
        .file(name: "z", size: 1, allocated: 40_960, inode: 3, cloneID: 4, privateSize: 0, extFlags: shareFlag),
        .file(name: "u", size: 1, allocated: 8192, inode: 20, cloneID: 4, extFlags: shareFlag),
    ]
    for w in [1, 8] {
        let r = try engine(InMemoryDirectoryEnumerator(rootPath: "/r", fs), workers: w).scanBlocking(path: "/r")
        checkEq(r.root.actualSize, 40_960 + 4096 + 8192)
        check(r.root.children.first { $0.name == "a" }!.isCloneDuplicate)
    }
}

test("all-or-nothing: flagged/read-only item refuses the whole permanent delete") {
    let fm = FileManager.default
    let base = NSTemporaryDirectory() + "dr-aon-\(UUID().uuidString)"
    try fm.createDirectory(atPath: base + "/v/sub", withIntermediateDirectories: true)
    defer { _ = chmod(base + "/v/sub", 0o755); try? fm.removeItem(atPath: base) }
    for i in 0..<10 { _ = fm.createFile(atPath: base + "/v/f\(i)", contents: Data([1])) }
    _ = fm.createFile(atPath: base + "/v/sub/locked", contents: Data([1]))
    let uchg = DeletabilityChecker(flags: { $0.hasSuffix("/locked") ? DeletabilityChecker.ufImmutable : 0 })
    check((try? PosixRecursiveDeleter(checker: uchg).deleteItem(atPath: base + "/v")) == nil)
    checkEq(((try? fm.contentsOfDirectory(atPath: base + "/v")) ?? []).count, 11)
    if getuid() != 0 {
        _ = chmod(base + "/v/sub", 0o555)
        check(DeletabilityChecker.live.check(base + "/v", recursive: true) != nil)
        check((try? PosixRecursiveDeleter().deleteItem(atPath: base + "/v")) == nil)
        checkEq(((try? fm.contentsOfDirectory(atPath: base + "/v")) ?? []).count, 11)
    }
}
@MainActor func cancelSelfTest() async throws {
    let r = try engine(InMemoryDirectoryEnumerator(rootPath: "/Users/tester/d", [
        .file(name: "a", size: 1), .file(name: "b", size: 1)]), workers: 1).scanBlocking(path: "/Users/tester/d")
    let l = DeletionList(deletionGuard: DeletionGuard(homeDirectory: "/Users/tester"))
    for n in r.root.children { _ = l.add(n) }
    final class D: ItemDeleting, @unchecked Sendable { var n = 0; func deleteItem(atPath path: String) throws { n += 1 } }
    let d = D(); let token = DeletionCancellation()
    let out = await l.deleteAll(using: d, cancellation: token, progress: { p in if p.itemIndex == 2 { token.cancel() } })
    check(out.cancelled); checkEq(d.n, 1); checkEq(out.notAttempted.count, 1); checkEq(l.items.count, 1)
}
await testAsync("deletion cancellation between items") { try await cancelSelfTest() }

test("app activity gating + quit during deletion") {
    let a = AppActivity()
    check(a.beginDeletion()); check(!a.isAllowed(.scan)); check(!a.isAllowed(.delete)); check(!a.beginScan())
    checkEq(a.requestTermination(), .later); checkEq(a.endDeletion(), .replyTerminate); check(a.isAllowed(.scan))
}
test("ACL deny refuses whole item; readdir error is not end-of-folder; stale progress dropped") {
    let fm = FileManager.default
    let base = NSTemporaryDirectory() + "dr-acl-\(UUID().uuidString)"
    try fm.createDirectory(atPath: base + "/v/s", withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: base) }
    _ = fm.createFile(atPath: base + "/v/s/x", contents: Data([1]))
    let c = DeletabilityChecker(flags: { _ in 0 }, aclDenies: { p, k in p.hasSuffix("/v/s") && k == .deleteChild })
    check(c.check(base + "/v", recursive: true) != nil)
    check((try? PosixRecursiveDeleter(checker: c).deleteItem(atPath: base + "/v")) == nil)
    check(fm.fileExists(atPath: base + "/v/s/x"))
    var steps: [(String?, Int32)] = [("a", 0), (nil, EIO)]
    check((try? DirectoryListing.drain { steps.removeFirst() }.get()) == nil)
    var seq = ProgressSequencer()
    let p2 = DeletionProgress(phase: .checking, itemIndex: 1, itemCount: 1, currentPath: "", deletedCount: 0, sequence: 2)
    let p1 = DeletionProgress(phase: .checking, itemIndex: 1, itemCount: 1, currentPath: "", deletedCount: 0, sequence: 1)
    check(seq.accept(p2)); check(!seq.accept(p1))
}

test("design tokens + chart colouring (simplify-v2)") {
    checkEq(ThemeTokens.light.brand.hex, "#0064D2"); checkEq(ThemeTokens.dark.brand.hex, "#1A6FD6")
    checkEq(ThemeTokens.light.danger.hex, "#D70015"); checkEq(ThemeTokens.dark.danger.hex, "#D12C24")
    check(RGB(hex: "#zz0000") == nil)
    check(RGB.contrast(RGB(0xFFFFFF), ThemeTokens.dark.brand) >= 4.5)
    checkEq(OKLCH.rgb(0.70, 0.115, 250).hex, "#64A3E3"); checkEq(OKLCH.rgb(0.525, 0.100, 250).hex, "#396EA2")
    checkEq(SunburstPalette.fixed(.container, .light).hex, "#B2BFCE"); checkEq(SunburstPalette.fixed(.other, .dark).hex, "#484848")
}

// MARK: geometry
struct T: SunburstNode {
    var name: String; var own: Double = 0; var kids: [T] = []
    var sunburstSize: Double { kids.isEmpty ? own : max(own, kids.reduce(0) { $0 + $1.sunburstSize }) }
    var sunburstChildren: [T] { kids }
}
let cfg = SunburstConfig(centerRadius: 50, ringWidth: 20, maxDepth: 3, minSliceAngle: 0.05, minOtherAngle: 0.001)

test("sunburst angles proportional") {
    let l = SunburstLayout(root: T(name: "r", kids: [T(name: "a", own: 3), T(name: "b", own: 1)]), config: cfg)
    checkEq(l.segments.count, 2)
    checkClose(l.segments[0].endAngle, 2 * .pi * 0.75)
}
test("sunburst small slices merge into other") {
    var kids = [T(name: "big", own: 1000)]
    for i in 0..<10 { kids.append(T(name: "t\(i)", own: 1)) }
    let l = SunburstLayout(root: T(name: "r", kids: kids), config: cfg)
    checkEq(l.segments.count, 2)
    check(l.segments[1].isOther)
}
test("sunburst hit testing") {
    let l = SunburstLayout(root: T(name: "r", kids: [T(name: "a", own: 10, kids: [T(name: "a1", own: 5)]), T(name: "b", own: 10)]), config: cfg)
    checkEq(l.hitTest(Point2D(x: 0, y: 0)), .center)
    if case let .segment(i) = l.hitTest(Point2D(x: 60, y: 0)) { checkEq(l.segments[i].node?.name, "a") } else { check(false) }
    if case let .segment(i) = l.hitTest(Point2D(x: 55, y: 55)) { checkEq(l.segments[i].node?.name, "a1") } else { check(false) }
    checkEq(l.hitTest(Point2D(x: 55, y: -55)), .none)
    checkEq(l.hitTest(Point2D(x: 500, y: 0)), .none)
    for s in l.segments { checkEq(l.hitTest(l.anchor(of: s)), .segment(s.index)) }
}

// MARK: deletion + real filesystem (main actor)
await testAsync("real filesystem scan, hard link, symlink loop, delete") {
    let base = NSTemporaryDirectory() + "diskrings-selftest-\(UUID().uuidString)"
    let fm = FileManager.default
    try fm.createDirectory(atPath: base + "/sub/deep", withIntermediateDirectories: true)
    try Data(repeating: 1, count: 100_000).write(to: URL(fileURLWithPath: base + "/sub/big.bin"))
    check(link(base + "/sub/big.bin", base + "/hard.bin") == 0)
    try fm.createSymbolicLink(atPath: base + "/loop", withDestinationPath: base)
    defer { try? fm.removeItem(atPath: base) }
    let r = try await ScanEngine(enumerator: PosixDirectoryEnumerator()).scan(path: base)
    checkEq(r.hardLinkDuplicates, 1)
    let list = DeletionList()
    list.add(r.root.descendant(atRelativePath: ["sub"])!)
    let out = await list.deleteAll(using: PosixRecursiveDeleter())
    checkEq(out.failed.count, 0)
    check(!fm.fileExists(atPath: base + "/sub"))
    check(fm.fileExists(atPath: base + "/hard.bin"))
    check(r.root.descendant(atRelativePath: ["sub"]) == nil)
}


// MARK: Batch 3 — delete confirm policy
test("delete confirm policy: phrase / matrix / return key") {
    checkEq(DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: true), "永久删除")
    checkEq(DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: false), "Delete Permanently")
    check(DeleteConfirmPolicy.returnKeyTriggersPrimary(method: .trash))
    check(!DeleteConfirmPolicy.returnKeyTriggersPrimary(method: .permanent))
    let hr = DeleteConfirmPolicy.Item(id: "/a.app", name: "a.app", path: "/a.app", bytes: 1, isHighRisk: true, riskReasons: ["appBundle"])
    let ok = DeleteConfirmPolicy.Item(id: "/c", name: "c", path: "/c", bytes: 1, isHighRisk: false, riskReasons: [])
    var snap = DeleteConfirmPolicy.Snapshot(items: [hr, ok], method: .trash)
    checkEq(DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: true), .none)
    snap.method = .permanent
    if case .typePhrase(let p) = DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: false) {
        checkEq(p, "Delete Permanently")
    } else { check(false, "expected typePhrase") }
    snap = DeleteConfirmPolicy.settingChecked(id: "/a.app", checked: false, in: snap)
    checkEq(DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: true), .typePhrase("永久删除"))
    check(!DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "", languageIsChinese: true))
    check(!DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "永久删除 ", languageIsChinese: true))
    check(DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "永久删除", languageIsChinese: true))
    let app = FileNode(name: "/Applications/X.app", kind: .directory, logicalSize: 1, allocatedSize: 1, actualSize: 1)
    let caches = FileNode(name: "/Users/u/Library/Caches", kind: .directory, logicalSize: 1, allocatedSize: 1, actualSize: 1)
    let built = DeleteConfirmPolicy.build(nodes: [app, caches], excluded: [], homeDirectory: "/Users/u", preferredMethod: .trash)
    checkEq(built.highRiskItems.count, 1)
    checkEq(built.normalItems.count, 1)
}

print("\(passed) passed, \(failures.count) failed")
for f in failures { print("FAIL: \(f)") }
exit(failures.isEmpty ? 0 : 1)
