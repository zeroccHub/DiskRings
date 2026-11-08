import XCTest
@testable import SunburstGeometry

/// Designer label spec 2026-10-13: 10 pt floor via per-tier metrics, 6 cached scale tiers,
/// no relayout during live resize, truncation minima, “其他 N 项”, reverse-domain names.
final class LabelSpecTests: XCTestCase {
    typealias L = LabelLayout
    typealias N = ChartModelTests.N

    func testTierQuantization() {
        let cases: [(Double, Double)] = [(1.15, 1), (1.0, 1), (0.999, 0.95), (0.95, 0.95), (0.9, 0.9), (0.87, 0.85),
                                         (0.85, 0.85), (0.8, 0.8), (0.799, 0.75), (0.76, 0.75), (0.75, 0.75), (0.5, 0.75)]
        for (k, t) in cases { XCTAssertEqual(LabelMetrics.tier(for: k), t, accuracy: 1e-12, "k=\(k)") }
        var tiers = Set<Double>()
        for i in 0...80 { tiers.insert(LabelMetrics.tier(for: 0.7 + Double(i) * 0.00625)) }
        XCTAssertEqual(tiers.count, LabelMetrics.maxCachedTiers)
        XCTAssertEqual(tiers.sorted(), [0.75, 0.8, 0.85, 0.9, 0.95, 1])
    }

    func testFontFloorsOnScreen() {
        let b = LabelMetrics.forScale(1)
        XCTAssertEqual([b.nameFont, b.sizeFont, b.nameLine, b.sizeLine, b.padding], [11, 10, 14, 12, 2.5])
        for i in 0...40 {
            let k = 0.75 + Double(i) * 0.01, m = LabelMetrics.forScale(k)
            XCTAssertGreaterThanOrEqual(m.nameFont * k, 10 - 1e-9, "k=\(k)")
            XCTAssertGreaterThanOrEqual(m.sizeFont * k, 10 - 1e-9, "k=\(k)")
            XCTAssertGreaterThanOrEqual(m.nameLine * k, 13 - 1e-9)
            XCTAssertGreaterThanOrEqual(m.sizeLine * k, 12 - 1e-9)
            XCTAssertGreaterThanOrEqual(m.padding * k, 2 - 1e-9)
            XCTAssertGreaterThanOrEqual(m.nameFont * k, 11 * k - 1e-9)   // never smaller than the old 11·k
            if k < 1 { XCTAssertLessThan(m.sizeFont * k, 10.7, "within a tier ≤ 10.6 pt") }
        }
        let m = LabelMetrics.forScale(0.76)                                   // compact 960×640
        XCTAssertEqual(m.nameFont * 0.75, 10, accuracy: 1e-9); XCTAssertEqual(m.padding * 0.75, 2, accuracy: 1e-9)
        // Placed labels carry the tier's metrics.
        let l = L.place([.init(wedge: .init(start: 0, end: 1.2, inner: 100, outer: 164), name: "Documents",
                               sizeText: "81 GB", highRisk: false, allowText: true, importance: 1)], metrics: m)[0]
        XCTAssertEqual(l.tier, .nameAndSize)
        XCTAssertEqual(l.nameFont, m.nameFont); XCTAssertEqual(l.height, m.nameLine + m.sizeLine, accuracy: 1e-9)
    }

    func testTruncationMinima() {
        for room in stride(from: 20.0, through: 120, by: 2) {
            for c in L.nameCandidates("Developer Tools", prefix: "", font: 11, room: room) where c.hasSuffix("…") {
                XCTAssertGreaterThanOrEqual(c.dropLast().count, LabelMetrics.minLatinChars, c)
            }
            for c in L.nameCandidates("导出成片素材合集", prefix: "", font: 11, room: room) where c.hasSuffix("…") {
                XCTAssertGreaterThanOrEqual(c.dropLast().count, LabelMetrics.minCJKChars, c)
            }
        }
        // 3 letters + "…" (old minimum) is no longer offered.
        let w3 = L.width("Dev…", 11)
        XCTAssertTrue(L.nameCandidates("Developer", prefix: "", font: 11, room: w3 + 1).isEmpty)
        XCTAssertEqual(L.nameCandidates("Developer", prefix: "", font: 11, room: L.width("Deve…", 11) + 0.1), ["Deve…"])
        XCTAssertEqual(L.nameCandidates("导出成片", prefix: "", font: 11, room: L.width("导出…", 11) + 0.1), ["导出…"])
        XCTAssertTrue(L.nameCandidates("导出成片", prefix: "", font: 11, room: L.width("导…", 11) + 0.1).isEmpty)
    }

    func testOtherLabelIsNeverTruncated() {
        let other = "其他 12 项"
        XCTAssertEqual(L.nameCandidates(other, prefix: "", font: 11, room: 500, isOther: true), [other])
        for room in stride(from: 10.0, to: L.width(other, 11), by: 3) {
            XCTAssertTrue(L.nameCandidates(other, prefix: "", font: 11, room: room, isOther: true).isEmpty)
        }
        // In narrow wedges an “other” sector falls back to the size or hides — never “其他 12…”.
        for i in 0..<60 {
            let a = Double(i) * 0.1, span = 0.05 + Double(i % 10) * 0.04
            let l = L.place([.init(wedge: .init(start: a, end: a + span, inner: 100 + Double(i % 3) * 68, outer: 164 + Double(i % 3) * 56),
                                   name: other, sizeText: "7.7 GB", highRisk: false, allowText: true, importance: 1, isOther: true)],
                            metrics: .forScale(0.76))[0]
            for line in l.lines { XCTAssertFalse(line.contains("…"), line); XCTAssertTrue(line == other || line == "7.7 GB", line) }
        }
    }

    func testReverseDomainRule() {
        XCTAssertEqual(L.dropReverseDomainRoot("com.tencent.xinWeChat"), "tencent.xinWeChat")
        XCTAssertEqual(L.dropReverseDomainRoot("org.mozilla.firefox"), "mozilla.firefox")
        XCTAssertEqual(L.dropReverseDomainRoot("Com.Apple.Safari"), "Apple.Safari")
        XCTAssertEqual(L.dropReverseDomainRoot("com.apple"), "com.apple")              // < 3 segments
        XCTAssertEqual(L.dropReverseDomainRoot("Documents"), "Documents")
        XCTAssertEqual(L.dropReverseDomainRoot("photo.backup.zip"), "photo.backup.zip")  // unknown root
        let c = L.nameCandidates("Containers › com.tencent.xinWeChat", prefix: "", font: 11, room: 70)
        XCTAssertFalse(c.isEmpty)
        for n in c { XCTAssertFalse(n.hasPrefix("com."), n) }
        XCTAssertTrue(c[0].hasPrefix("tencent"), c[0])
        // Full name still wins when it fits.
        XCTAssertEqual(L.nameCandidates("com.tencent.xinWeChat", prefix: "", font: 11, room: 500).first, "com.tencent.xinWeChat")
    }

    func testDefaultOrderIsRotatedNameFirst() {
        // Thin ring on the diagonal: the old spec order gives size; default now keeps a rotated name.
        let i = L.Input(wedge: .init(start: 0.3, end: 1.3, inner: 200, outer: 222), name: "Docs",
                        sizeText: "81 GB", highRisk: false, allowText: true, importance: 1)
        let d = L.place([i])[0]
        XCTAssertEqual(d.tier, .rotated); XCTAssertEqual(d.lines, ["Docs"])
    }

    func testCacheHoldsSixTiersAndNeverRelaysOutOnHit() {
        var inputs: [L.Input] = []
        for i in 0..<40 {
            let a = Double(i) * 2 * Double.pi / 40
            inputs.append(.init(wedge: .init(start: a, end: a + 2 * Double.pi / 40, inner: 100, outer: 164),
                                name: "Folder \(i)", sizeText: "\(i) GB", highRisk: false, allowText: true, importance: Double(40 - i)))
        }
        let cache = L.Cache(inputs: inputs)
        for _ in 0..<3 { for i in 0...100 { _ = cache.labels(tier: 0.6 + Double(i) * 0.006) } }
        XCTAssertEqual(cache.count, 6); XCTAssertEqual(cache.builds, 6)
        XCTAssertEqual(Set(cache.tiers), [0.75, 0.8, 0.85, 0.9, 0.95, 1])
        // Same tier → identical labels, no new placement.
        XCTAssertEqual(cache.labels(tier: 0.87), cache.labels(tier: 0.89)); XCTAssertEqual(cache.builds, 6)
    }

    func testNoRelayoutDuringLiveResize() {
        let root = N(name: "root", kids: (0..<12).map { N(name: "Folder \($0)", own: Double(100 - $0 * 7)) })
        var m = ChartModel(focus: root, labelScale: 1, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                           sizeText: { "\(Int($0)) B" }, otherName: { "其他 \($0) 项" })
        XCTAssertEqual(m.labelCache.builds, 1)
        var p = L.RelayoutPolicy(tier: m.labelTier)
        // Drag from k 1.15 down to 0.75: nothing is re-laid out while the drag is live.
        for i in 0...40 {
            let k = 1.15 - Double(i) * 0.01
            if let t = p.boundsChanged(scale: k, inLiveResize: true) { m.applyLabelScale(t) }
        }
        XCTAssertEqual(m.labelCache.builds, 1); XCTAssertEqual(m.labelTier, 1)
        // Drag ends at 0.76 → one relayout to tier 0.75.
        if let t = p.liveResizeEnded(scale: 0.76) { m.applyLabelScale(t) }
        XCTAssertEqual(m.labelTier, 0.75); XCTAssertEqual(m.labelCache.builds, 2)
        for s in m.sectors where s.label.tier != .hidden { XCTAssertGreaterThanOrEqual(s.label.sizeFont * 0.76, 10) }
        // Same tier after another drag or a non-live resize → no relayout.
        XCTAssertNil(p.liveResizeEnded(scale: 0.78))
        XCTAssertNil(p.boundsChanged(scale: 0.79, inLiveResize: false))
        // Non-live resize into a new tier applies immediately; back to a cached tier = no placement.
        if let t = p.boundsChanged(scale: 1.1, inLiveResize: false) { m.applyLabelScale(t) }
        XCTAssertEqual(m.labelTier, 1); XCTAssertEqual(m.labelCache.builds, 2)
        // Hover/appearance never touch labels: applying the current tier is a no-op.
        XCTAssertFalse(m.applyLabelScale(1.05))
    }

    /// Rebuild (model + labels for the current tier) stays ≤ 8 ms at every tier.
    func testRebuildBenchmarkPerTier() {
        func dir(_ name: String, _ depth: Int, _ seed: Int) -> N {
            if depth == 0 { return N(name: name, own: Double(1 + (seed * 37) % 97)) }
            let n = [3, 6, 12][depth - 1]       // 12 × 6 × 3: ≈ 150 sectors, label-heavy
            return N(name: name, kids: (0..<n).map { dir("com.example.\(name)-\($0)", depth - 1, seed * 13 + $0) })
        }
        let root = dir("root", 3, 1)
        var xs: [Double] = []
        for k in [1.15, 1.0, 0.95, 0.9, 0.87, 0.8, 0.76] {
            for _ in 0..<5 {
                let t0 = Date()
                let m = ChartModel(focus: root, labelScale: k, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                                   sizeText: { "\(Int($0)) GB" }, otherName: { "其他 \($0) 项" })
                xs.append(Date().timeIntervalSince(t0))
                XCTAssertGreaterThan(m.sectors.count, 50)
            }
        }
        let m0 = ChartModel(focus: root, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                            sizeText: { "\(Int($0)) GB" }, otherName: { "其他 \($0) 项" })
        var placeWorst = 0.0
        for k in [1.0, 0.76] { for _ in 0..<5 {
            let t0 = Date(); _ = L.place(m0.labelCache.inputs, metrics: .forScale(k))
            placeWorst = max(placeWorst, Date().timeIntervalSince(t0))
        } }
        print(String(format: "LABELS rebuild per tier: %@ (labels alone worst %.2fms, %d sectors)",
                     TimingBudget.check(xs, budget: 0.008, "rebuild"), placeWorst * 1000, m0.sectors.count))
    }
}
