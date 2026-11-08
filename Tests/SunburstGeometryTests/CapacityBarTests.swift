import XCTest
@testable import SunburstGeometry

/// Top capacity bar: branch-root expansion, < 3% folding, 系统与快照 gap, drill-down scope.
final class CapacityBarTests: XCTestCase {
    typealias N = ChartModelTests.N
    func model(_ root: N) -> ChartModel<N> {
        ChartModel(focus: root, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                   sizeText: { "\(Int($0)) B" }, otherName: { "其他 \($0) 项" })
    }
    func bar(_ root: N, total: Double? = nil, avail: Double? = nil) -> (ChartModel<N>, CapacityBarModel<N>) {
        let m = model(root)
        return (m, CapacityBarModel(root: m, volumeTotal: total, volumeAvailable: avail, name: { $0.name }))
    }
    // Users (≥50%) → container; its children become the bar's branch roots.
    var sample: N {
        N(name: "r", kids: [
            N(name: "Users", kids: [N(name: "Library", own: 300), N(name: "Movies", own: 150), N(name: "Docs", own: 100)]),
            N(name: "Apps", own: 120), N(name: "private", own: 60, locked: true), N(name: "Sys", own: 40),
            N(name: "opt", own: 10), N(name: "tiny", own: 9),
        ])
    }

    func testContainerExpandsIntoChildrenSameOrderAndColours() {
        let (m, b) = bar(sample)
        XCTAssertFalse(b.segments.contains { $0.name == "Users" }, "the ≥50% container never appears itself")
        XCTAssertEqual(b.segments.filter { $0.kind == .branch }.map(\.name), ["Library", "Movies", "Docs", "Apps", "Sys", "opt", "tiny"])
        for s in b.segments where s.kind == .branch {
            XCTAssertEqual(s.light, m.sectors[s.sector!].color.light); XCTAssertEqual(s.dark, m.sectors[s.sector!].color.dark)
        }
        let p = b.segments.first { $0.kind == .protected }!
        XCTAssertEqual(p.light.hex, "#BEBEBE"); XCTAssertEqual(p.name, "private"); XCTAssertTrue(p.isClickable)
        // Contiguous, left→right, no free track when the volume is unknown (folder scan).
        for (a, c) in zip(b.segments, b.segments.dropFirst()) { XCTAssertEqual(a.end, c.start, accuracy: 1e-12) }
        XCTAssertEqual(b.segments.last!.end, 1, accuracy: 1e-9)
        XCTAssertFalse(b.legend.contains { $0.kind == .free })
    }

    func testSmallBranchesFoldIntoPlusNAndFixedItemsStay() {
        let (_, b) = bar(sample, total: 1000, avail: 211)   // used 785 = scanned
        // 3% of 1000 = 30: Sys 40 stays, opt 10 + tiny 9 fold.
        guard case let .folded(idx)? = b.legend.first(where: { if case .folded = $0.kind { return true }; return false })?.kind else {
            return XCTFail("no +N item") }
        XCTAssertEqual(idx.map { b.segments[$0].name }, ["opt", "tiny"])
        XCTAssertTrue(b.legend.contains(.init(kind: .protected, bytes: 60)))
        XCTAssertTrue(b.legend.contains(.init(kind: .free, bytes: 211)))
        XCTAssertFalse(b.segments.contains { $0.kind == .systemGap }, "used == scanned → no gap")
        // Width fitting folds the smallest shown branch first, never 其他/系统保护/可用.
        let fitted = b.fittedLegend(width: 300, itemWidth: { _ in 60 })
        XCTAssertLessThanOrEqual(fitted.count * 60 + 14 * (fitted.count - 1), 300)
        XCTAssertTrue(fitted.contains { $0.kind == .protected }); XCTAssertTrue(fitted.contains { $0.kind == .free })
        let shownBranches = fitted.compactMap { if case let .branch(i) = $0.kind { return b.segments[i].name }; return nil }
        XCTAssertEqual(shownBranches, ["Library"], "largest survives")
        XCTAssertEqual(b.fittedLegend(width: 10_000, itemWidth: { _ in 60 }), b.legend)
    }

    func testSystemAndSnapshotsGapWhenUsedExceedsScanned() {
        let (_, b) = bar(sample, total: 1000, avail: 111)   // used 885, scanned 785
        let gap = b.segments.last!
        XCTAssertEqual(gap.kind, .systemGap); XCTAssertEqual(gap.bytes, 100, accuracy: 1e-9)
        XCTAssertFalse(gap.isClickable)
        XCTAssertEqual(gap.end, 0.889, accuracy: 1e-9)
        XCTAssertEqual(gap.light, SunburstPalette.fixed(.other, .light))
        XCTAssertTrue(b.legend.contains(.init(kind: .systemGap, bytes: 100)))
        XCTAssertEqual(b.free, 111, accuracy: 1e-9)
    }

    func testDrillScopeGreysOutsideAndBracketsTheFocus() {
        let root = sample
        let (_, b) = bar(root, total: 1000, avail: 211)
        func anc(_ a: N, _ n: N) -> Bool {   // test tree: names are unique; a contains n
            if a.name == n.name { return true }
            return a.kids.contains { anc($0, n) }
        }
        let atRoot = b.scope(focus: root, isRoot: true, isAncestorOrSelf: anc)
        XCTAssertTrue(atRoot.inScope.allSatisfy { $0 }); XCTAssertNil(atRoot.bracket)
        let users = root.kids[0]
        let s = b.scope(focus: users, isRoot: false, isAncestorOrSelf: anc)
        XCTAssertEqual(zip(b.segments, s.inScope).filter { $0.1 }.map { $0.0.name }, ["Library", "Movies", "Docs"])
        XCTAssertEqual(s.bracket!.lowerBound, 0, accuracy: 1e-12)
        XCTAssertEqual(s.bracket!.upperBound, 0.55, accuracy: 1e-9)
        // Deeper focus inside one branch keeps only that branch coloured.
        let lib = users.kids[0]
        let deep = b.scope(focus: lib, isRoot: false, isAncestorOrSelf: anc)
        XCTAssertEqual(deep.inScope.filter { $0 }.count, 1); XCTAssertTrue(deep.inScope[0])
        XCTAssertEqual(deep.bracket, b.segments[0].start...b.segments[0].end)
    }

    func testOtherBucketFollowsItsParentScope() {
        var kids = (0..<14).map { N(name: "f\($0)", own: Double(200 - $0)) }   // > 10 kids → 其他 bucket
        kids.append(N(name: "small", own: 1))
        let root = N(name: "r", kids: [N(name: "Users", kids: kids), N(name: "Apps", own: 100)])
        let (_, b) = bar(root)
        let other = b.segments.first { $0.kind == .other }!
        XCTAssertFalse(other.isClickable)
        XCTAssertEqual(other.parentNode?.name, "Users")
        let s = b.scope(focus: root.kids[0], isRoot: false, isAncestorOrSelf: { a, n in a.name == n.name || a.kids.contains { $0.name == n.name } })
        XCTAssertTrue(s.inScope[b.segments.firstIndex { $0.kind == .other }!])
        XCTAssertFalse(s.inScope[b.segments.firstIndex { $0.name == "Apps" }!])
    }

    func testScaleFloorIs075() {
        XCTAssertEqual(ChartModel<N>.scale(width: 2000, height: 456), 0.75, accuracy: 1e-12)
        XCTAssertEqual(ChartModel<N>.scale(width: 2000, height: 616), 0.96, accuracy: 1e-12)
    }

    /// P2-8: whatever the segment cap does to a container's children, the bar covers
    /// the scanned total (any uncovered remainder becomes a container-coloured,
    /// clickable `containerRest` segment right after the children).
    func testContainerRemainderKeepsTheBarComplete() {
        var kids = [N(name: "Library", own: 300), N(name: "Movies", own: 150)]
        kids += (0..<40).map { N(name: "t\($0)", own: 0.3 + Double($0) * 0.01) }
        let root = N(name: "r", kids: [N(name: "Users", kids: kids), N(name: "Apps", own: 100), N(name: "Sys", own: 20)])
        for cap in [3, 4, 5, 6, 8, 12, 150] {
            var cfg = ChartModel<N>.finderConfig
            cfg.maxSegments = cap
            let m = ChartModel(focus: root, config: cfg, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                               sizeText: { "\($0)" }, otherName: { "其他 \($0) 项" })
            let b = CapacityBarModel(root: m, volumeTotal: 1000, volumeAvailable: 400, name: { $0.name })
            let scannedSum = b.segments.filter { $0.kind != .systemGap }.reduce(0.0) { $0 + $1.bytes }
            XCTAssertEqual(scannedSum, m.layout.rootSize, accuracy: 1e-6, "cap \(cap): bar covers the scanned total")
            for (a, c) in zip(b.segments, b.segments.dropFirst()) { XCTAssertEqual(a.end, c.start, accuracy: 1e-12) }
            for r in b.segments where r.kind == .containerRest {
                XCTAssertEqual(r.light, SunburstPalette.fixed(.container, .light)); XCTAssertTrue(r.isClickable)
                XCTAssertEqual(r.name, "Users")
            }
        }
    }

    func testNoticeDuration() {
        XCTAssertEqual(CapacityNotice.duration(forText: "短"), 8)
        XCTAssertEqual(CapacityNotice.duration(forText: String(repeating: "字", count: 35)), 11)
        XCTAssertEqual(CapacityNotice.duration(forText: String(repeating: "x", count: 500)), 15)
    }
}
