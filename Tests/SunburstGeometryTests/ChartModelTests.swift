import XCTest
@testable import SunburstGeometry

/// Finder-style chart: layout rules, README §4.5 colouring, hover dimming, label fit.
final class ChartModelTests: XCTestCase {
    struct N: SunburstNamed {
        var name: String
        var own: Double = 0
        var kids: [N] = []
        var restricted = false
        var locked = false
        var risky = false
        var sunburstSize: Double { kids.isEmpty ? own : kids.reduce(0) { $0 + $1.sunburstSize } }
        var sunburstChildren: [N] { kids }
        var sunburstName: String { name }
        var sunburstPath: String { "/" + name }
        var sunburstIsDirectory: Bool { !kids.isEmpty }
        var sunburstIsRestricted: Bool { restricted }
    }
    func model(_ root: N) -> ChartModel<N> {
        ChartModel(focus: root, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                   sizeText: { "\(Int($0)) B" }, otherName: { "其他 \($0) 项" })
    }
    let lightRoots = ["#64A3E3", "#1BB3BA", "#5DB37F", "#D8A354", "#E08C66", "#DD8081", "#D480A8", "#AF8CD8", "#8A98E6"]
    let darkRoots = ["#396EA2", "#007B81", "#327B50", "#8C611A", "#995636", "#9C5152", "#955172", "#785A99", "#5A65A4"]

    func testOKLCHMatchesDesignHex() {
        XCTAssertEqual(OKLCH.rgb(0.70, 0.115, 250).hex, "#64A3E3")
        XCTAssertEqual(OKLCH.rgb(0.77, 0.092, 243).hex, "#7FBBEB")
        XCTAssertEqual(SunburstPalette.fixed(.other, .light).hex, "#CACACA")
        XCTAssertEqual(SunburstPalette.fixed(.container, .light).hex, "#B2BFCE")
        XCTAssertEqual(SunburstPalette.fixed(.protected, .light).hex, "#BEBEBE")
        XCTAssertEqual(SunburstPalette.fixed(.other, .dark).hex, "#484848")
        XCTAssertEqual(SunburstPalette.fixed(.container, .dark).hex, "#353E48")
        XCTAssertEqual(SunburstPalette.fixed(.protected, .dark).hex, "#3D3D3D")
        XCTAssertEqual(SunburstPalette.ink(.light).hex, "#1D1D1F"); XCTAssertEqual(SunburstPalette.ink(.dark).hex, "#FFFFFF")
    }

    func testNineRootsTakeHueTableClockwise() {
        let root = N(name: "r", kids: (0..<9).map { N(name: "k\($0)", own: Double(100 - $0)) })
        let m = model(root)
        let roots = m.sectors.filter { $0.depth == 1 }.sorted { $0.startAngle < $1.startAngle }
        XCTAssertEqual(roots.map(\.color.role), Array(repeating: .root, count: 9))
        XCTAssertEqual(roots.map(\.color.light.hex), lightRoots)
        XCTAssertEqual(roots.map(\.color.dark.hex), darkRoots)
    }

    func testDominantRingOneBecomesContainerAndChildrenBecomeRoots() {
        let big = N(name: "Users", kids: [N(name: "a", own: 300), N(name: "b", own: 200), N(name: "c", own: 100)])
        let root = N(name: "r", kids: [big, N(name: "Apps", own: 200), N(name: "Sys", own: 100, locked: true)])
        let m = model(root)
        let users = m.sectors.first { $0.depth == 1 && $0.node?.name == "Users" }!
        XCTAssertEqual(users.color.role, .container)
        XCTAssertEqual(users.color.light.hex, "#B2BFCE")
        let sys = m.sectors.first { $0.node?.name == "Sys" }!
        XCTAssertEqual(sys.color.role, .protected); XCTAssertEqual(sys.labelLines, 0, "protected: lock only")
        let ordered = m.sectors.filter { $0.color.role == .root }.sorted { $0.startAngle < $1.startAngle }
        XCTAssertEqual(ordered.map { $0.node!.name }, ["a", "b", "c", "Apps"])
        XCTAssertEqual(ordered.map(\.color.light.hex), Array(lightRoots.prefix(4)))
    }

    func testChildrenShiftHueAndLightness() {
        let root = N(name: "r", kids: [N(name: "A", kids: (0..<3).map { N(name: "c\($0)", own: Double(30 - $0)) }),
                                       N(name: "B", own: 80), N(name: "C", own: 30)])
        let m = model(root)
        let kids = m.childrenOf[m.sectors.first { $0.node?.name == "A" }!.index]!.map { m.sectors[$0] }
        XCTAssertEqual(kids.map(\.color.hue), [243, 250, 257])
        XCTAssertEqual(kids[0].color.light.hex, "#7FBBEB")
        XCTAssertEqual(kids[1].color.light.hex, OKLCH.rgb(0.79, 0.092, 250).hex, "odd sibling +0.02 L in light")
        XCTAssertEqual(kids[1].color.dark.hex, OKLCH.rgb(0.46, 0.085, 250).hex, "odd sibling −0.02 L in dark")
    }

    func testOtherAndRestrictedAreGreyAndNeverRoots() {
        var kids = (0..<14).map { N(name: "k\($0)", own: Double(100 - $0)) }
        kids.append(N(name: "secret", own: 50, restricted: true))
        let m = model(N(name: "r", kids: kids))
        let other = m.sectors.first { $0.isOther }!
        XCTAssertEqual(other.color.role, .other); XCTAssertEqual(other.color.light.hex, "#CACACA")
        XCTAssertEqual(other.otherCount, 5); XCTAssertEqual(other.name, "其他 5 项")
        XCTAssertEqual(m.sectors.filter { $0.depth == 1 && !$0.isOther }.count, 10)
        XCTAssertFalse(m.sectors.contains { $0.node?.name == "secret" })
    }

    func testSegmentCapAndUnsortedInput() {
        // 12 × 12 × 12 would be 1,884 segments uncapped.
        func lvl(_ d: Int, _ p: String) -> [N] {
            (0..<12).map { i in d == 0 ? N(name: "\(p)\(i)", own: Double(1 + i)) : N(name: "\(p)\(i)", kids: lvl(d - 1, "\(p)\(i)/")) }
        }
        let m = model(N(name: "r", kids: lvl(3, "")))
        XCTAssertLessThanOrEqual(m.sectors.count, 150)
        // Unsorted children still rank largest-first.
        let flat = model(N(name: "r", kids: lvl(0, "f")))
        let first = flat.sectors.filter { $0.depth == 1 }.min { $0.startAngle < $1.startAngle }!
        XCTAssertEqual(first.node?.name, "f11")
    }

    func testPathCompression() {
        let homeUser = N(name: "tester", kids: [N(name: "a", own: 60), N(name: "b", own: 40)])
        let m = model(N(name: "r", kids: [N(name: "Users", kids: [homeUser]), N(name: "x", own: 1)]))
        XCTAssertTrue(m.sectors.contains { $0.name == "Users › tester" }, m.sectors.map(\.name).description)
    }

    func testHoverDimsOutsideBranchOnly() {
        let root = N(name: "r", kids: [N(name: "A", kids: [N(name: "a1", own: 5), N(name: "a2", own: 5)]), N(name: "B", own: 10)])
        let m = model(root)
        let a = m.sectors.first { $0.node?.name == "A" }!.index
        let op = m.opacities(hover: a)
        for s in m.sectors {
            let inA = s.node?.name.hasPrefix("a") == true || s.index == a
            XCTAssertEqual(op[s.index], inA ? 1 : 0.42, s.name)
        }
        XCTAssertEqual(Set(m.opacities(hover: nil)), [1])
        // Hit test in design units: 12 o'clock on ring 1 is A.
        XCTAssertEqual(m.layout.hitTest(Point2D(x: 1, y: 130)), .segment(a))
        XCTAssertEqual(m.layout.hitTest(Point2D(x: 0, y: 10)), .center)
    }

    func testLabelsOnlyWhenTheyFitAndRiskPrefix() {
        let root = N(name: "r", kids: [N(name: "Documents", own: 80, risky: true), N(name: "t", own: 0.2)])
        let m = model(root)
        let doc = m.sectors.first { $0.node?.name == "Documents" }!
        XCTAssertEqual(doc.labelLines, 2); XCTAssertTrue(doc.isHighRisk)
        let small = m.sectors.first { $0.node?.name == "t" }
        XCTAssertEqual(small?.labelLines ?? 0, 0)
    }

    func testScaleClamp() {
        XCTAssertEqual(ChartModel<N>.scale(width: 600, height: 640), 1)
        XCTAssertEqual(ChartModel<N>.scale(width: 300, height: 300), 0.75)
        XCTAssertEqual(ChartModel<N>.scale(width: 2000, height: 2000), 1.15)
    }
}

final class OutlineRulesTests: XCTestCase {
    typealias N = ChartModelTests.N
    func testTopTenPlusOtherHidesZeroAndCountsRestricted() {
        var kids = (0..<13).map { N(name: "k\($0)", own: Double(1 + $0)) }
        kids.append(N(name: "zero", own: 0))
        kids.append(N(name: "locked", own: 3, restricted: true))
        let lvl = OutlineRules.children(of: N(name: "r", kids: kids))
        XCTAssertEqual(lvl.shown.map(\.name), (3..<13).reversed().map { "k\($0)" })
        XCTAssertEqual(lvl.otherCount, 4)          // k0…k2 + locked
        XCTAssertEqual(lvl.otherSize, 1 + 2 + 3 + 3)
    }

    /// P2-11 keyboard navigation: ←/→ wrap among siblings, ↓ first child, ↑ parent.
    func testKeyboardSteps() {
        let root = N(name: "r", kids: [N(name: "a", kids: [N(name: "a1", own: 30), N(name: "a2", own: 20)]),
                                       N(name: "b", own: 40), N(name: "c", own: 10)])
        let m = ChartModel(focus: root, isProtected: { $0.locked }, isHighRisk: { $0.risky },
                           sizeText: { "\(Int($0)) B" }, otherName: { "其他 \($0) 项" })
        let ring1 = m.childrenOf[-1]!
        XCTAssertEqual(m.step(from: nil, .next), ring1.first)
        let a = m.sectors.first { $0.node?.name == "a" }!.index
        XCTAssertEqual(m.step(from: a, .next), ring1[(ring1.firstIndex(of: a)! + 1) % ring1.count])
        XCTAssertEqual(m.step(from: a, .previous), ring1[(ring1.firstIndex(of: a)! + ring1.count - 1) % ring1.count])
        let child = m.step(from: a, .child)!
        XCTAssertEqual(m.sectors[child].node?.name, "a1", "largest child first")
        XCTAssertEqual(m.step(from: child, .parent), a)
        XCTAssertNil(m.step(from: a, .parent))
        XCTAssertNil(m.step(from: m.sectors.first { $0.node?.name == "b" }!.index, .child))
    }
}

final class InRingLabelTests: XCTestCase {
    typealias M = ChartModel<ChartModelTests.N>
    func testPrefersFullThenLastComponentThenTail() {
        XCTAssertEqual(M.fitLabel("Data", highRisk: false, available: 100), "Data")
        let long = "Containers › com.apple.kMac › Data"
        XCTAssertEqual(M.fitLabel(long, highRisk: false, available: 40), "Data")
        let t = M.fitLabel("com.apple.Safari.SafeBrowsing", highRisk: false, available: 60)
        XCTAssertNotNil(t); XCTAssertTrue(t!.hasSuffix("…")); XCTAssertTrue(t!.hasPrefix("com"))
        XCTAssertNil(M.fitLabel("Developer", highRisk: false, available: 8))
    }
    func testNeverMiddleTruncatesAndFitsBudget() {
        for name in ["Users › tester", "Containers › com.apple.kMac › Data", "Library", "非常长的中文文件夹名称示例"] {
            for avail in stride(from: 5.0, through: 160, by: 5) {
                guard let l = M.fitLabel(name, highRisk: true, available: avail) else { continue }
                XCTAssertLessThanOrEqual(TextWidth.estimate("⚠ " + l, fontSize: 11), avail)
                let mid = l.dropFirst().dropLast()
                XCTAssertFalse(mid.contains("…"), "middle truncation: \(l)")
            }
        }
    }
}

extension ChartModelTests {
    func testModelLabelsAreConsistentAndHiddenOnesGetTooltips() {
        let root = N(name: "home", kids: [
            N(name: "Documents", own: 81), N(name: "Library", kids: (0..<12).map { N(name: "Container \($0)", own: Double(20 - $0)) }),
            N(name: "Movies", own: 40)] + (0..<25).map { N(name: "tiny\($0)", own: 0.4) })
        let m = model(root)
        var shown: [SectorLabel] = []
        for s in m.sectors {
            let tip = m.hoverTooltip(s.index, path: { $0.sunburstPath })
            if s.label.tier == .nameAndSize && s.label.showsFullName { XCTAssertNil(tip) }
            else {
                XCTAssertNotNil(tip, s.name)
                XCTAssertTrue(tip!.hasPrefix(s.name)); XCTAssertTrue(tip!.contains(s.sizeText)); XCTAssertTrue(tip!.contains("%"))
            }
            XCTAssertEqual(s.labelLines, s.label.tier == .nameAndSize ? 2 : (s.label.tier == .hidden ? 0 : 1))
            if s.label.tier != .hidden { shown.append(s.label) }
        }
        for i in shown.indices { for j in shown.indices where j > i { XCTAssertFalse(LabelLayout.overlaps(shown[i], shown[j])) } }
        let d = m.sectors.first { $0.name == "Documents" }!
        XCTAssertNotEqual(d.label.tier, .hidden)
    }
}
