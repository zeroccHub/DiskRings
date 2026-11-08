import XCTest
@testable import SunburstGeometry
@testable import DiskScanCore

/// Stale selection/hover outline after drilling (screenshot 1076b960: hollow wedge of
/// the previous level left at the bottom-left of the Downloads›backup view).
final class ChartOutlineStateTests: XCTestCase {
    func file(_ n: String, _ s: UInt64) -> FileNode { FileNode(name: n, kind: .file, logicalSize: s, allocatedSize: s, actualSize: s) }
    func dir(_ n: String, _ k: [FileNode]) -> FileNode { let d = FileNode(name: n, kind: .directory); d.setChildren(k); return d }
    func model(_ f: FileNode) -> ChartModel<FileNode> {
        ChartModel(focus: f, isProtected: { _ in false }, isHighRisk: { _ in false },
                   sizeText: { "\(Int($0)) B" }, otherName: { "其他 \($0) 项" })
    }
    /// Data › {Users › mac387 › Downloads › backup › {a, b}, Library, Applications}
    func tree() -> (root: FileNode, downloads: FileNode, backup: FileNode, a: FileNode) {
        let a = file("a.dmg", 300), backup = dir("backup", [a, file("b.zip", 212)])
        let downloads = dir("Downloads", [backup, file("x.pkg", 90)])
        let root = dir("/System/Volumes/Data", [dir("Users", [dir("mac387", [downloads, file("y", 50)])]),
                                                 dir("Library", [file("l", 400)]), file("Applications", 350)])
        root.aggregate()
        return (root, downloads, backup, a)
    }
    func idx(_ m: ChartModel<FileNode>, _ n: FileNode) -> Int? { m.sectors.firstIndex { $0.node === n } }

    func testNoStaleOutlineAfterDrillingIn() {
        let t = tree()
        let rootM = model(t.root)
        var st = ChartOutlineState<FileNode>()
        // Hover + select the outer "Downloads › backup"-style sector at the root level.
        let bi = try! XCTUnwrap(idx(rootM, t.backup) ?? idx(rootM, t.downloads))
        st.select(bi, in: rootM)
        // Hover a sector whose label is shortened/hidden, so it has a tooltip.
        let tipIdx = try! XCTUnwrap(rootM.sectors.indices.first { rootM.hoverTooltip($0, path: { $0.path }) != nil })
        st.hover(tipIdx, in: rootM, path: { $0.path })
        XCTAssertNotNil(st.outline); XCTAssertNotNil(st.hoverOutline); XCTAssertNotNil(st.tooltip)
        // Double-click: drill into backup → it becomes the centre, no sector for it.
        let drill = model(t.backup)
        XCTAssertNil(idx(drill, t.backup))
        st.layoutChanged(drill)
        XCTAssertNil(st.outline, "no hollow wedge from the previous level")
        XCTAssertNil(st.selectedIndex); XCTAssertNil(st.hoverOutline); XCTAssertNil(st.hoverIndex)
        XCTAssertNil(st.tooltip, "tooltip cleared")
        // Empty chart (new scan) also clears.
        st.select(0, in: drill); st.layoutChanged(nil); XCTAssertNil(st.outline)
    }

    func testSelectionKeptAndRecomputedWhenStillVisible() {
        let t = tree()
        let inner = model(t.downloads)
        var st = ChartOutlineState<FileNode>()
        let ai = try! XCTUnwrap(idx(inner, t.a))
        st.select(ai, in: inner)
        let before = st.outline!
        // Drill out to the root: a.dmg is still a sector (depth 3 › deeper ring) → kept, new geometry.
        let rootM = model(t.root)
        st.layoutChanged(rootM)
        if let ri = idx(rootM, t.a) {
            XCTAssertEqual(st.selectedIndex, ri)
            let s = rootM.sectors[ri]
            XCTAssertEqual(st.outline, .init(start: s.startAngle, end: s.endAngle, inner: s.innerRadius, outer: s.outerRadius))
            XCTAssertNotEqual(st.outline, before, "geometry recomputed for the new layout")
        } else {
            XCTAssertNil(st.outline, "not visible any more → cleared")
        }
        // Drill out one level where it is visible for sure (backup's ring 2).
        st.select(ai, in: inner)
        let mid = model(t.backup)
        st.layoutChanged(mid)
        let mi = try! XCTUnwrap(idx(mid, t.a))
        XCTAssertEqual(st.selectedIndex, mi)
        XCTAssertEqual(st.outline?.inner, mid.sectors[mi].innerRadius)
    }

    func testOutlineRecomputedAfterTierRelayoutAndTooltipCleared() {
        let t = tree()
        var m = model(t.root)
        var st = ChartOutlineState<FileNode>()
        let i = try! XCTUnwrap(idx(m, t.downloads) ?? idx(m, t.backup))
        st.select(i, in: m); st.hover(i, in: m, path: { $0.path })
        let o = st.outline
        XCTAssertTrue(m.applyLabelScale(0.76))
        st.layoutChanged(m)
        XCTAssertEqual(st.selectedIndex, i); XCTAssertEqual(st.outline, o)
        XCTAssertNil(st.tooltip); XCTAssertNil(st.hoverOutline)
        // Hover change semantics: same index is a no-op, out-of-range is nil.
        XCTAssertTrue(st.hover(i, in: m, path: { $0.path }))
        XCTAssertFalse(st.hover(i, in: m, path: { $0.path }))
        XCTAssertTrue(st.hover(999, in: m, path: { $0.path })); XCTAssertNil(st.hoverIndex); XCTAssertNil(st.tooltip)
        // Search locate: selecting a sector in the freshly built parent model.
        let parentM = model(t.backup)
        st.layoutChanged(parentM)
        st.select(idx(parentM, t.a), in: parentM)
        XCTAssertEqual(st.outline?.start, parentM.sectors[idx(parentM, t.a)!].startAngle)
    }
}
