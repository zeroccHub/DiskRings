import XCTest
import Foundation
import DiskScanCore
@testable import SunburstGeometry

/// TreeAnalysis precompute (background, O(n), cancellable) + the 5M-node chart
/// budgets of the Finder-style redesign: rebuild < 16 ms, hover hit-test < 2 ms.
final class TreeAnalysisTests: XCTestCase {
    typealias S = SyntheticTree
    let home = "/Users/tester"

    func realisticTree() -> FileNode {
        S.finish(S.node("/", [
            S.node("Applications", [S.node("Xcode.app", [S.node("Contents", [S.node("bin", size: 900)])]), S.node("notes.txt", size: 3)]),
            S.node("Library", [S.node("Caches", [S.node("x", [S.node("a.bin", size: 50)])]), S.node("LaunchDaemons", [S.node("p.plist", size: 1)])]),
            S.node("Users", [S.node("tester", [
                S.node("Library", [S.node("Caches", [S.node("c", size: 70)]), S.node("Preferences", [S.node("p", size: 2)]),
                                   S.node("Containers", [S.node("Weird.APP", [S.node("f", size: 1)])])]),
                S.node(".config", [S.node("rc", size: 1)]),
                S.node("Movies", [S.node("clip.mov", size: 400), S.node("empty.mov", size: 0), S.node(".hidden.mov", size: 2)]),
                S.node("Libraryx", [S.node("y", size: 4)]),
                S.node("EmptyDir", []),
            ])]),
        ]))
    }

    func testHighRiskMatchesBasketRiskForEveryNode() throws {
        for root in [realisticTree(), S.build(rootPath: "/Users/tester", targetNodes: 30_000)] {
            let a = try XCTUnwrap(TreeAnalysis.build(root: root, homeDirectory: home))
            var stack = [root], n = 0
            while let x = stack.popLast() {
                n += 1
                XCTAssertEqual(a.isHighRisk(x), BasketRisk.classify(x, homeDirectory: home).isHighRisk, x.path)
                stack.append(contentsOf: x.children)
            }
            XCTAssertEqual(a.visited, n)
        }
    }

    func testHiddenCountCountsZeroSizeAndUnreadable() throws {
        let root = realisticTree()
        let a = try XCTUnwrap(TreeAnalysis.build(root: root, homeDirectory: home))
        let movies = try XCTUnwrap(root.descendant(atRelativePath: ["Users", "tester", "Movies"]))
        XCTAssertEqual(a.hiddenCount(movies), 1, "empty.mov")
        let homeUser = try XCTUnwrap(movies.parent)
        XCTAssertEqual(a.hiddenCount(homeUser), 2, "empty.mov + EmptyDir")
        XCTAssertEqual(a.hiddenCount(root), 2)
    }

    func testCancellation() {
        let root = S.build(targetNodes: 300_000)
        let t0 = Date()
        XCTAssertNil(TreeAnalysis.build(root: root, homeDirectory: home, isCancelled: { true }))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.2)
    }

    func testAnalysisScalesLinearly() {
        func time(_ n: Int) -> Double {
            let r = S.build(targetNodes: n); let t0 = Date()
            _ = TreeAnalysis.build(root: r, homeDirectory: home)
            return Date().timeIntervalSince(t0)
        }
        _ = time(20_000)
        let t1 = time(100_000), t5 = time(500_000)
        print(String(format: "ANALYSIS 100k=%.3fs 500k=%.3fs", t1, t5))
        XCTAssertLessThan(t5 / max(t1, 1e-3), 12, "O(n)")
    }

    static func model(_ root: FileNode, _ a: TreeAnalysis) -> ChartModel<FileNode> {
        ChartModel(focus: root, isProtected: { $0.isRestricted }, isHighRisk: { a.isHighRisk($0) },
                   sizeText: { SizeText.format(UInt64($0)) }, otherName: { "其他 \($0) 项" })
    }

    /// Chart budgets on a tree. Debug builds run 200k nodes; the 5M variant is opt-in (release).
    func runBudgets(root: FileNode, a: TreeAnalysis, rebuildBudget: Double, hoverBudget: Double) throws {
        let nodes = a.visited
        _ = Self.model(root, a) // warm-up
        var rebuilds: [Double] = [], m: ChartModel<FileNode>?
        for _ in 0..<20 {
            let t0 = Date(); m = Self.model(root, a); rebuilds.append(Date().timeIntervalSince(t0))
        }
        let worst = rebuilds.max()!
        let model = try XCTUnwrap(m)
        XCTAssertLessThanOrEqual(model.sectors.count, 150)
        // Hover: hit-test + per-sector opacity, at 2,000 points across the chart.
        var hovers: [Double] = []
        for i in 0..<2000 {
            let ang = Double(i) * 0.0317, r = 60 + Double(i % 230)
            let t0 = Date()
            let hit = model.layout.hitTest(Point2D(x: r * sin(ang), y: r * cos(ang)))
            var h: Int? = nil
            if case let .segment(s) = hit { h = s }
            _ = model.opacities(hover: h)
            hovers.append(Date().timeIntervalSince(t0))
        }
        print(String(format: "CHART %d nodes: rebuild worst=%.2fms hover worst=%.3fms sectors=%d",
                     nodes, worst * 1000, hovers.max()! * 1000, model.sectors.count))
        print("CHART " + TimingBudget.check(rebuilds, budget: rebuildBudget, "rebuild"))
        print("CHART " + TimingBudget.check(hovers, budget: hoverBudget, "hover", p: 0.99))
        // Capacity bar: built from the root-level model (no tree walk) + drill scope.
        var bars: [Double] = [], scopes: [Double] = []
        let deep = root.children.first?.children.first ?? root
        for _ in 0..<20 {
            var t0 = Date()
            let bar = CapacityBarModel(root: model, volumeTotal: model.layout.rootSize * 1.3,
                                       volumeAvailable: model.layout.rootSize * 0.2, name: { $0.name })
            bars.append(Date().timeIntervalSince(t0))
            t0 = Date()
            _ = bar.scope(focus: deep, isRoot: false, isAncestorOrSelf: { a, n in
                var c: FileNode? = n
                while let x = c { if x === a { return true }; c = x.parent }
                return false
            })
            scopes.append(Date().timeIntervalSince(t0))
        }
        print("CAPACITY BAR " + TimingBudget.check(bars, budget: 0.002, "build"))
        print("CAPACITY BAR " + TimingBudget.check(scopes, budget: 0.002, "scope"))
    }

    func testChartBudgetsOnLargeTree() throws {
        let root = S.build(targetNodes: 200_000)
        try runBudgets(root: root, a: XCTUnwrap(TreeAnalysis.build(root: root, homeDirectory: home)),
                       rebuildBudget: 0.05, hoverBudget: 0.002)
    }

    /// DISKRINGS_HEAVY=1 swift test -c release -Xswiftc -enable-testing --filter testFiveMillion
    func testFiveMillionNodeChartBudgets() throws {
        guard ProcessInfo.processInfo.environment["DISKRINGS_HEAVY"] == "1" else {
            throw XCTSkip("set DISKRINGS_HEAVY=1 (release) to run the 5M-node budget test")
        }
        let root = S.build(targetNodes: 5_000_000)
        let t0 = Date()
        let a = try XCTUnwrap(TreeAnalysis.build(root: root, homeDirectory: home))
        print(String(format: "ANALYSIS 5M=%.2fs", Date().timeIntervalSince(t0)))
        XCTAssertEqual(a.visited, 5_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 10)
        try runBudgets(root: root, a: a, rebuildBudget: 0.016, hoverBudget: 0.002)
    }

    func testProgressCoalescerIsBoundedPerTick() {
        let c = ProgressCoalescer<Int>()
        let p = 7
        let t0 = Date()
        for i in 0..<1_000_000 { _ = c.offer(i) }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
        XCTAssertEqual(c.scheduled, 1, "only one pending main-thread hop while unconsumed")
        XCTAssertEqual(c.take(), 999_999, "hop gets the newest value")
        XCTAssertTrue(c.offer(p)); XCTAssertFalse(c.offer(p))
    }

    func testEngineProgressIsThrottled() throws {
        var items: [InMemoryDirectoryEnumerator.FakeItem] = []
        for d in 0..<400 { items.append(.dir(name: "d\(d)", (0..<50).map { .file(name: "f\($0)", size: 10, allocated: 4096) })) }
        let engine = ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/r", items),
                                options: ScanOptions(maxConcurrency: 4, progressInterval: 0.1))
        let box = ProgressCoalescer<Int>()
        let t0 = Date()
        _ = try engine.scanBlocking(path: "/r") { _ in _ = box.offer(1); _ = box.take() }
        let dur = Date().timeIntervalSince(t0)
        XCTAssertLessThanOrEqual(box.offered, Int(dur / 0.1) + 3, "≤10 Hz")
    }
}
