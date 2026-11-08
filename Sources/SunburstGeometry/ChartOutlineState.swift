import Foundation

/// Selection outline, hover and tooltip of the sunburst, kept against ONE chart layout.
/// Whenever the layout changes (drill in/out, rebuild, label-tier relayout, search locate)
/// `layoutChanged` must be called: hover + tooltip are cleared, and the selection is kept only
/// if its node is still a sector of the new layout (its outline geometry is recomputed from
/// the new sector) — otherwise it is cleared. The view draws exactly `outline`.
public struct ChartOutlineState<Node: AnyObject> {
    /// Geometry of the outline the view must draw (nil = hidden).
    public struct Outline: Equatable, Sendable {
        public var start, end, inner, outer: Double
    }
    public private(set) var selectedIndex: Int?
    public private(set) var hoverIndex: Int?
    public private(set) var tooltip: String?
    public private(set) var outline: Outline?
    /// 1.5 pt hover stroke (simplify-plan #17), recomputed from the current layout; nil = none.
    public private(set) var hoverOutline: Outline?
    private weak var selectedNode: Node?
    public init() {}

    static func outline(_ s: ChartModel<Node>.Sector) -> Outline {
        Outline(start: s.startAngle, end: s.endAngle, inner: s.innerRadius, outer: s.outerRadius)
    }

    /// New/changed layout: drop hover + tooltip; keep the selection only if still visible.
    public mutating func layoutChanged(_ model: ChartModel<Node>?) {
        hoverIndex = nil
        tooltip = nil
        hoverOutline = nil
        guard let m = model, let n = selectedNode, let i = m.sectors.firstIndex(where: { $0.node === n }) else {
            selectedIndex = nil; selectedNode = nil; outline = nil
            return
        }
        selectedIndex = i
        outline = Self.outline(m.sectors[i])
    }

    public mutating func select(_ index: Int?, in model: ChartModel<Node>?) {
        guard let i = index, let m = model, m.sectors.indices.contains(i) else {
            selectedIndex = nil; selectedNode = nil; outline = nil; return
        }
        selectedIndex = i
        selectedNode = m.sectors[i].node
        outline = Self.outline(m.sectors[i])
    }

    /// Returns true when the hover changed.
    @discardableResult
    public mutating func hover(_ index: Int?, in model: ChartModel<Node>?, path: (Node) -> String) -> Bool {
        let idx = index.flatMap { i in model.map { $0.sectors.indices.contains(i) } == true ? i : nil }
        guard idx != hoverIndex else { return false }
        hoverIndex = idx
        tooltip = idx.flatMap { model?.hoverTooltip($0, path: path) }
        hoverOutline = idx.flatMap { i in model.map { Self.outline($0.sectors[i]) } }
        return true
    }
}
