import XCTest
@testable import SunburstGeometry

struct T: SunburstNode, Equatable {
    var name: String
    var own: Double = 0
    var kids: [T] = []
    var sunburstSize: Double { kids.isEmpty ? own : max(own, kids.reduce(0) { $0 + $1.sunburstSize }) }
    var sunburstChildren: [T] { kids }
}

final class SunburstLayoutTests: XCTestCase {
    let twoPi = 2 * Double.pi
    let cfg = SunburstConfig(centerRadius: 50, ringWidth: 20, maxDepth: 3, minSliceAngle: 0.05, minOtherAngle: 0.001)

    func testAnglesProportionalToSize() {
        let root = T(name: "root", kids: [T(name: "a", own: 3), T(name: "b", own: 1)])
        let l = SunburstLayout(root: root, config: cfg)
        XCTAssertEqual(l.segments.count, 2)
        XCTAssertEqual(l.segments[0].node?.name, "a")
        XCTAssertEqual(l.segments[0].startAngle, 0, accuracy: 1e-12)
        XCTAssertEqual(l.segments[0].endAngle, twoPi * 0.75, accuracy: 1e-12)
        XCTAssertEqual(l.segments[1].startAngle, twoPi * 0.75, accuracy: 1e-12)
        XCTAssertEqual(l.segments[1].endAngle, twoPi, accuracy: 1e-12)
        XCTAssertEqual(l.segments[0].innerRadius, 50)
        XCTAssertEqual(l.segments[0].outerRadius, 70)
        XCTAssertEqual(l.ringCount, 1)
    }

    func testNestedRingsStayInsideParentArcAndRespectMaxDepth() {
        func chain(_ d: Int) -> T { d == 0 ? T(name: "leaf", own: 10) : T(name: "n\(d)", kids: [chain(d - 1), T(name: "f\(d)", own: 10)]) }
        let l = SunburstLayout(root: chain(6), config: cfg)
        XCTAssertEqual(l.ringCount, 3)
        XCTAssertTrue(l.segments.allSatisfy { $0.depth <= 3 })
        for s in l.segments {
            guard let p = s.parentIndex else { XCTAssertEqual(s.depth, 1); continue }
            let parent = l.segments[p]
            XCTAssertEqual(parent.depth + 1, s.depth)
            XCTAssertGreaterThanOrEqual(s.startAngle, parent.startAngle - 1e-12)
            XCTAssertLessThanOrEqual(s.endAngle, parent.endAngle + 1e-12)
            XCTAssertEqual(s.innerRadius, parent.outerRadius)
            XCTAssertEqual(l.segments[s.rootSliceIndex].depth, 1)
        }
    }

    func testSmallSlicesMergeIntoOther() {
        var kids = [T(name: "big", own: 1000)]
        for i in 0..<10 { kids.append(T(name: "tiny\(i)", own: 1)) }      // each ~0.006 rad < 0.05
        let l = SunburstLayout(root: T(name: "r", kids: kids), config: cfg)
        XCTAssertEqual(l.segments.count, 2)
        let other = l.segments[1]
        XCTAssertTrue(other.isOther)
        guard case let .other(count, size) = other.content else { return XCTFail() }
        XCTAssertEqual(count, 10)
        XCTAssertEqual(size, 10)
        XCTAssertEqual(other.endAngle, twoPi, accuracy: 1e-9)
    }

    func testOtherBelowThresholdIsDropped() {
        let c = SunburstConfig(centerRadius: 50, ringWidth: 20, maxDepth: 2, minSliceAngle: 0.05, minOtherAngle: 0.04)
        let l = SunburstLayout(root: T(name: "r", kids: [T(name: "big", own: 100_000), T(name: "t", own: 1)]), config: c)
        XCTAssertEqual(l.segments.count, 1)
    }

    func testZeroSizeAndEmpty() {
        XCTAssertTrue(SunburstLayout(root: T(name: "r"), config: cfg).segments.isEmpty)
        let l = SunburstLayout(root: T(name: "r", kids: [T(name: "z", own: 0), T(name: "a", own: 5)]), config: cfg)
        XCTAssertEqual(l.segments.map { $0.node?.name }, ["a"])
    }

    func testLayoutAngleConvention() {
        typealias L = SunburstLayout<T>
        XCTAssertEqual(L.layoutAngle(x: 0, y: 1), 0, accuracy: 1e-12)              // 12 o'clock
        XCTAssertEqual(L.layoutAngle(x: 1, y: 0), .pi / 2, accuracy: 1e-12)        // 3 o'clock (clockwise)
        XCTAssertEqual(L.layoutAngle(x: 0, y: -1), .pi, accuracy: 1e-12)
        XCTAssertEqual(L.layoutAngle(x: -1, y: 0), 3 * .pi / 2, accuracy: 1e-12)
        let p = L.point(angle: .pi / 2, radius: 10)
        XCTAssertEqual(p.x, 10, accuracy: 1e-9); XCTAssertEqual(p.y, 0, accuracy: 1e-9)
    }

    func testHitTesting() {
        // a: 0..π (right half), b: π..2π (left half); a has child a1 covering first half of a.
        let root = T(name: "r", kids: [T(name: "a", kids: [T(name: "a1", own: 5), ]), T(name: "b", own: 10)])
        let rootWithGap = T(name: "r", kids: [T(name: "a", own: 10, kids: [T(name: "a1", own: 5)]), T(name: "b", own: 10)])
        let l = SunburstLayout(root: rootWithGap, config: cfg)
        XCTAssertEqual(l.hitTest(Point2D(x: 0, y: 0)), .center)
        XCTAssertEqual(l.hitTest(Point2D(x: 49, y: 0)), .center)
        guard case let .segment(ia) = l.hitTest(Point2D(x: 60, y: 0)) else { return XCTFail() }
        XCTAssertEqual(l.segments[ia].node?.name, "a")
        guard case let .segment(ib) = l.hitTest(Point2D(x: -60, y: 0)) else { return XCTFail() }
        XCTAssertEqual(l.segments[ib].node?.name, "b")
        // Ring 2, upper-right quadrant (angle π/4) is a1.
        guard case let .segment(i1) = l.hitTest(Point2D(x: 55, y: 55)) else { return XCTFail() }  // r≈77.8
        XCTAssertEqual(l.segments[i1].node?.name, "a1")
        // Ring 2, lower-right (angle 3π/4) is the unused remainder of a → none.
        XCTAssertEqual(l.hitTest(Point2D(x: 55, y: -55)), .none)
        // Flipped coordinates mirror y.
        XCTAssertEqual(l.hitTest(Point2D(x: 55, y: -55), yUp: false), .segment(i1))
        // Outside all rings.
        XCTAssertEqual(l.hitTest(Point2D(x: 500, y: 0)), .none)
        _ = root
    }

    func testOutlineAndAnchorLieOnExpectedRadii() {
        let l = SunburstLayout(root: T(name: "r", kids: [T(name: "a", own: 1), T(name: "b", own: 3)]), config: cfg)
        for s in l.segments {
            let pts = l.outline(of: s)
            XCTAssertGreaterThan(pts.count, 4)
            let radii = pts.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }
            XCTAssertTrue(radii.allSatisfy { abs($0 - s.innerRadius) < 1e-9 || abs($0 - s.outerRadius) < 1e-9 })
            let a = l.anchor(of: s)
            XCTAssertEqual(l.hitTest(a), .segment(s.index))
        }
    }

    func testFittingConfig() {
        let c = SunburstConfig.fitting(diameter: 600, maxDepth: 5)
        XCTAssertEqual(c.outerRadius, 296, accuracy: 1e-9)
        XCTAssertGreaterThan(c.centerRadius, 0)
    }
}
