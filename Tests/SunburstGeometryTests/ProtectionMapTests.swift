import XCTest
#if !SINGLE_MODULE
@testable import DiskScanCore
#endif
@testable import SunburstGeometry

/// P1-3 (only SIP/system locations propagate) + P1-4 (flags precomputed off the main
/// thread; chart rebuilds do no filesystem work, ≤ 8 ms).
final class ProtectionMapTests: XCTestCase {
    typealias S = SyntheticTree
    func f(_ n: String, _ gb: Double) -> FileNode { S.node(n, size: UInt64(gb * 1e9)) }

    /// Home is NOT dominant (< 50%), so it is an ordinary ring-1 branch.
    func sampleTree() -> FileNode {
        S.finish(S.node("/", [
            S.node("Users", [S.node("tester", [S.node("Library", [S.node("Caches", [f("a", 5)])]), S.node("Movies", [f("m", 40)])])]),
            S.node("Applications", [S.node("Xcode.app", [f("x", 60)])]),
            S.node("System", [S.node("Library", [f("k", 30)])]),
            S.node("usr", [S.node("local", [S.node("bin", [f("brew", 4)])]), S.node("bin", [f("ls", 1)])]),
            S.node("Library", [S.node("Apple", [f("ap", 9)]), S.node("Fonts", [f("ft", 2)])]),
            S.node("private", [S.node("var", [S.node("db", [f("d", 3)]), S.node("folders", [S.node("zz", [f("t", 2)])])])]),
        ]))
    }
    func guardFor(counter: Counter? = nil) -> DeletionGuard {
        DeletionGuard(homeDirectory: "/Users/tester",
                      mountPoints: { counter?.mounts += 1; return ["/"] },
                      fileFlags: { _ in counter?.flags += 1; return nil })
    }
    final class Counter { var mounts = 0; var flags = 0 }
    func all(_ n: FileNode) -> [FileNode] { [n] + n.children.flatMap(all) }
    func find(_ root: FileNode, _ p: String) -> FileNode { all(root).first { $0.path == p }! }

    func testOnlySystemLocationsPropagate() throws {
        let root = sampleTree()
        let m = try XCTUnwrap(ProtectionMap.build(root: root, guard: guardFor()))
        XCTAssertEqual(m.kind(find(root, "/Users/tester")), .selfOnly, "home: the folder itself only")
        XCTAssertEqual(m.kind(find(root, "/Users/tester/Library")), .none)
        XCTAssertEqual(m.kind(find(root, "/Users/tester/Library/Caches/a")), .none)
        XCTAssertEqual(m.kind(find(root, "/Users")), .selfOnly)
        XCTAssertEqual(m.kind(find(root, "/")), .selfOnly)
        XCTAssertEqual(m.kind(find(root, "/System")), .subtree)
        XCTAssertEqual(m.kind(find(root, "/System/Library/k")), .subtree, "inherited")
        XCTAssertEqual(m.kind(find(root, "/usr")), .subtree)
        XCTAssertEqual(m.kind(find(root, "/usr/bin/ls")), .subtree)
        XCTAssertEqual(m.kind(find(root, "/usr/local")), .none, "allowed exception under /usr")
        XCTAssertEqual(m.kind(find(root, "/usr/local/bin/brew")), .none)
        XCTAssertEqual(m.kind(find(root, "/Library")), .selfOnly)
        XCTAssertEqual(m.kind(find(root, "/Library/Fonts")), .none)
        XCTAssertEqual(m.kind(find(root, "/Library/Apple")), .subtree)
        XCTAssertEqual(m.kind(find(root, "/private/var/db/d")), .subtree)
        XCTAssertEqual(m.kind(find(root, "/private/var/folders/zz")), .none)
        XCTAssertLessThan(m.evaluated, all(root).count, "only nodes on the way to rule keys are evaluated")
    }

    /// The display map agrees with the (unchanged) guard's own verdict for EVERY node.
    func testAgreesWithLiveGuardRulesForEveryNode() throws {
        let root = sampleTree()
        let g = guardFor()
        let m = try XCTUnwrap(ProtectionMap.build(root: root, guard: g))
        for n in all(root) {
            XCTAssertEqual(m.kind(n), g.check(n.path)?.protectionKind ?? .none, n.path)
        }
    }

    func testReasonClassification() {
        XCTAssertEqual(DeletionGuard.Reason.systemLocation("/System").protectionKind, .subtree)
        XCTAssertEqual(DeletionGuard.Reason.sipProtected.protectionKind, .subtree)
        for r: DeletionGuard.Reason in [.homeFolder, .containsHomeFolder, .volumeRoot("/"), .containsVolume("/Volumes/X"),
                                        .filesystemRoot, .essentialFolder("/Library"), .containsProtected("/Library/Apple")] {
            XCTAssertEqual(r.protectionKind, .selfOnly, "\(r)")
        }
    }

    func testChartDoesNotHatchTheHomeBranch() throws {
        let root = sampleTree()
        let a = try XCTUnwrap(TreeAnalysis.build(root: root, homeDirectory: "/Users/tester", protectionGuard: guardFor()))
        let m = ChartModel(focus: root, isProtected: { a.protectionKind($0) == .subtree }, isHighRisk: { a.isHighRisk($0) },
                           sizeText: { "\($0)" }, otherName: { "其他 \($0) 项" })
        let homeSectors = m.sectors.filter { $0.node.map { $0.path.hasPrefix("/Users") } ?? false }
        XCTAssertFalse(homeSectors.isEmpty)
        for s in homeSectors {
            XCTAssertNotEqual(s.color.role, .protected, s.name)
        }
        XCTAssertEqual(m.sectors.first { $0.depth == 1 && $0.node?.path.hasPrefix("/System") == true }?.color.role, .protected)
        let local = try XCTUnwrap(m.sectors.first { $0.node?.path.hasPrefix("/usr/local") == true })
        XCTAssertNotEqual(local.color.role, .protected, "allowed exception is not hatched")
        let bar = CapacityBarModel(root: m, volumeTotal: 500e9, volumeAvailable: 300e9, name: { $0.name })
        let prot = bar.segments.filter { $0.kind == .protected }.map(\.bytes).reduce(0, +)
        XCTAssertEqual(prot, 30e9 + 5e9, accuracy: 1e6, "系统保护 = the /System and /usr ring-1 branches only (never home)")
    }

    /// P1-4 acceptance: 100k-node tree, successive drill-downs, each main-thread
    /// `makeChartModel` ≤ 8 ms and zero guard filesystem calls after the analysis.
    func testDrillDownRebuildBudgetAndNoFilesystemCalls() throws {
        let home = S.build(rootPath: "tester", targetNodes: 100_000)
        let root = S.finish(S.node("/", [S.node("Users", [home]), S.node("System", [f("k", 30)]),
                                         S.node("Applications", [f("a", 20)])]))
        let counter = Counter()
        let a = try XCTUnwrap(TreeAnalysis.build(root: root, homeDirectory: "/Users/tester", protectionGuard: guardFor(counter: counter)))
        let before = (counter.mounts, counter.flags)
        var focus = root, worst = 0.0, steps = 0
        func make(_ n: FileNode) -> ChartModel<FileNode> {
            ChartModel(focus: n, isProtected: { a.protectionKind($0) == .subtree }, isHighRisk: { a.isHighRisk($0) },
                       sizeText: { SizeText.format(UInt64($0)) }, otherName: { "其他 \($0) 项" })
        }
        _ = make(root)
        while true {
            // Best of 3 per drill step: one preempted sample is not the code's cost.
            var best = Double.infinity
            for _ in 0..<3 { let t0 = Date(); _ = make(focus); best = min(best, Date().timeIntervalSince(t0)) }
            worst = max(worst, best); steps += 1
            guard let next = focus.children.filter(\.isDirectory).max(by: { $0.sunburstSize < $1.sunburstSize }) else { break }
            focus = next
        }
        print(String(format: "DRILL 100k: %d steps, main-thread makeChartModel worst (best-of-3)=%.2fms", steps, worst * 1000))
        XCTAssertLessThan(worst, TimingBudget.scaled(0.008))
        XCTAssertEqual(counter.mounts, before.0, "no mount-list reads during rebuilds")
        XCTAssertEqual(counter.flags, before.1, "no lstat during rebuilds")
    }
}
