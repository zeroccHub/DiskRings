import XCTest
@testable import SunburstGeometry

final class LabelLayoutTests: XCTestCase {
    typealias L = LabelLayout
    func input(_ a0: Double, _ a1: Double, _ r0: Double, _ r1: Double, _ name: String = "Documents",
               _ size: String = "81 GB", importance: Double = 1, text: Bool = true) -> L.Input {
        .init(wedge: .init(start: a0, end: a1, inner: r0, outer: r1), name: name, sizeText: size,
              highRisk: false, allowText: text, importance: importance)
    }
    func testTierSelection() {
        // Big ring-1 wedge: name + size.
        XCTAssertEqual(L.place([input(0, 1.2, 92, 156)])[0].tier, .nameAndSize)
        // Wide arc but thin ring (20 pt): one line only → size.
        XCTAssertEqual(L.place([input(-0.5, 0.5, 200, 220)])[0].tier, .sizeOnly)   // top: horizontal fits
        // Same thin ring on the diagonal: horizontal box crosses the edges → along the arc.
        let t = L.place([input(0.3, 1.3, 200, 220)])[0]
        XCTAssertEqual(t.tier, .rotated); XCTAssertEqual(t.rotation, -0.8, accuracy: 1e-9)
        // Narrow wedge (≈14 pt arc at r 252) with a thick ring: rotated along the radius.
        let r = L.place([input(0.2, 0.29, 220, 284, "Caches")])[0]
        XCTAssertEqual(r.tier, .rotated); XCTAssertNotEqual(r.rotation, 0)
        XCTAssertGreaterThanOrEqual(r.rotation, -Double.pi / 2); XCTAssertLessThanOrEqual(r.rotation, Double.pi / 2)
        // Sliver: hidden.
        XCTAssertEqual(L.place([input(0, 0.02, 220, 284)])[0].tier, .hidden)
        // Protected (no text allowed): hidden.
        XCTAssertEqual(L.place([input(0, 1.2, 92, 156, text: false)])[0].tier, .hidden)
    }
    func testLabelsStayInsideTheirWedge() {
        for k in 0..<200 {
            let a0 = Double(k) * 0.031, span = 0.01 + Double(k % 17) * 0.05, ring = k % 3
            let w = input(a0, a0 + span, 92 + 64 * Double(ring), 156 + 64 * Double(ring), "Application Support")
            let l = L.place([w])[0]
            if l.tier == .hidden { continue }
            XCTAssertTrue(L.fits(l, w.wedge), "k=\(k) tier=\(l.tier)")
        }
    }
    func testNoCollisionsAcrossAFullChart() {
        // Three rings of alternating wide/narrow wedges (like a real drill view).
        var inputs: [L.Input] = []
        for ring in 0..<3 {
            var a = 0.0, i = 0
            while a < 2 * Double.pi - 0.01 {
                let span = min(2 * Double.pi - a, [0.9, 0.05, 0.2, 0.08, 0.4, 0.03][i % 6])
                inputs.append(input(a, a + span, 92 + 64 * Double(ring), 156 + 64 * Double(ring), "Folder \(ring)-\(i)",
                                    "\(i) GB", importance: span * 1000))
                a += span; i += 1
            }
        }
        let labels = L.place(inputs)
        let shown = labels.filter { $0.tier != .hidden }
        XCTAssertGreaterThan(shown.count, inputs.count / 2)
        for i in shown.indices { for j in shown.indices where j > i { XCTAssertFalse(L.overlaps(shown[i], shown[j])) } }
    }
    func testObstacleAndOverlapPrimitive() {
        let a = SectorLabel(tier: .sizeOnly, lines: ["x"], center: .init(x: 0, y: 0), rotation: 0, width: 20, height: 10, showsFullName: false)
        var b = a; b.center = .init(x: 15, y: 0)
        XCTAssertTrue(L.overlaps(a, b))
        b.center = .init(x: 25, y: 0); XCTAssertFalse(L.overlaps(a, b))
        b.rotation = .pi / 2; b.center = .init(x: 14, y: 0); XCTAssertTrue(L.overlaps(a, b))   // rotated 10 wide
        b.center = .init(x: 16, y: 0); XCTAssertFalse(L.overlaps(a, b))
        // An obstacle blocks a label that would otherwise fit.
        let w = input(0, 1.2, 92, 156)
        let free = L.place([w])[0]
        XCTAssertEqual(L.place([w], obstacles: [free])[0].tier, .hidden)
    }
    func testInkContrast() {
        for hex: UInt32 in [0xFFFFFF, 0x000000, 0x5AA9F0, 0x2E7D32, 0xE9E9EB, 0x8E8E93, 0xFFD60A, 0x30343B] {
            let fill = RGB(hex), ink = L.ink(on: fill)
            let other = ink == RGB(0x1D1D1F) ? RGB(0xFFFFFF) : RGB(0x1D1D1F)
            XCTAssertGreaterThanOrEqual(RGB.contrast(ink, fill), RGB.contrast(other, fill))
            XCTAssertGreaterThanOrEqual(RGB.contrast(ink, fill), 3.0, "fill \(String(hex, radix: 16))")
        }
    }

    /// Label placement is part of the model rebuild; 150 sectors (the layout cap) worst case.
    func testPlacementBenchmark() {
        var inputs: [L.Input] = []
        for ring in 0..<3 {
            for i in 0..<50 {
                let a = Double(i) * 2 * Double.pi / 50
                inputs.append(input(a, a + 2 * Double.pi / 50, 92 + 64 * Double(ring), 156 + 64 * Double(ring),
                                    "Application Support \(i)", "\(i) GB", importance: Double(150 - i)))
            }
        }
        _ = L.place(inputs)                                  // warm-up
        var xs: [Double] = []
        for _ in 0..<40 { let t0 = Date(); _ = L.place(inputs); xs.append(Date().timeIntervalSince(t0)) }
        print("LABELS 150 sectors place " + TimingBudget.check(xs, budget: 0.004, "place"))
    }
}
