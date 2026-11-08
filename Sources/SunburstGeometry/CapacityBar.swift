import Foundation

/// Top capacity bar (simplify-v2/capacity-bar README). Pure model, built ONCE per
/// root-level chart model (cache key = scan root + treeGeneration) plus the volume
/// capacity read once when the scan finishes. Drill-down, hover and resize never
/// rebuild it: they use `scope(...)` (cheap, ≤ ~15 segments) and the view's frames.
public struct CapacityBarModel<Node> {
    public enum Kind: Equatable, Sendable { case branch, protected, other, systemGap, containerRest }

    public struct Segment {
        public let kind: Kind
        /// Sector index in the root-level ChartModel (nil for the system gap).
        public let sector: Int?
        public let node: Node?
        /// For “其他 N 项” buckets: the node whose children were merged.
        public let parentNode: Node?
        public let name: String
        public let bytes: Double
        /// Fractions of the bar's full width (= volume capacity), 0…1.
        public let start: Double
        public let end: Double
        public let light: RGB
        public let dark: RGB
        /// Branches, protected and the container remainder navigate; 其他 / 系统与快照 do not.
        public var isClickable: Bool { kind == .branch || kind == .protected || kind == .containerRest }
    }

    public enum LegendKind: Equatable, Sendable {
        case branch(Int)            // segment index
        case folded([Int])          // “+N 项”: segment indices
        case protected, other, systemGap, free
    }
    public struct LegendItem: Equatable {
        public let kind: LegendKind
        public let bytes: Double
        public init(kind: LegendKind, bytes: Double) { self.kind = kind; self.bytes = bytes }
    }

    public let segments: [Segment]
    public let total: Double
    public let used: Double
    public let scanned: Double
    public var free: Double { max(0, total - used) }
    /// Legend before width fitting (branches < `foldShare` of the disk already folded).
    public let legend: [LegendItem]

    public static var foldShare: Double { 0.03 }

    /// - Parameters:
    ///   - root: the chart model of the scan root (root level; never a drilled focus).
    ///   - volumeTotal / volumeAvailable: read once at scan end; nil for plain folders
    ///     (then the bar spans the scanned total and has no free track).
    ///   - name: legend/tooltip name per sector (the app maps the two Libraries to
    ///     `~/Library` / `/Library`).
    public init(root: ChartModel<Node>, volumeTotal: Double?, volumeAvailable: Double?,
                name: (ChartModel<Node>.Sector) -> String) {
        let scanned = root.layout.rootSize
        let total: Double, used: Double
        if let t = volumeTotal, t > 0, let a = volumeAvailable {
            used = max(0, t - a)
            total = max(t, scanned)
        } else {
            used = scanned; total = scanned
        }
        self.total = total; self.used = used; self.scanned = scanned
        let width = max(total, 1)

        // Branch roots in clockwise order: ring-1 sectors, a container replaced by its children.
        // `-(i+1)` marks “the part of container i not covered by its children” (P2-8).
        var order: [Int] = []
        for i in root.childrenOf[-1] ?? [] {
            if root.sectors[i].color.role == .container, let kids = root.childrenOf[i], !kids.isEmpty {
                order.append(contentsOf: kids)
                let rest = root.sectors[i].size - kids.reduce(0) { $0 + root.sectors[$1].size }
                if rest > total * 0.001 { order.append(-(i + 1)) }
            } else {
                order.append(i)
            }
        }
        var segs: [Segment] = []
        var x = 0.0
        for i in order {
            if i < 0 {
                let c = root.sectors[-i - 1]
                let rest = c.size - (root.childrenOf[-i - 1] ?? []).reduce(0) { $0 + root.sectors[$1].size }
                let f = rest / width
                segs.append(Segment(kind: .containerRest, sector: c.index, node: c.node, parentNode: nil,
                                    name: name(c), bytes: rest, start: x, end: x + f,
                                    light: SunburstPalette.fixed(.container, .light), dark: SunburstPalette.fixed(.container, .dark)))
                x += f
                continue
            }
            let s = root.sectors[i]
            let kind: Kind = s.isOther ? .other : (s.isProtected ? .protected : .branch)
            let light: RGB, dark: RGB
            switch kind {
            case .branch: light = s.color.light; dark = s.color.dark
            case .other: light = SunburstPalette.fixed(.other, .light); dark = SunburstPalette.fixed(.other, .dark)
            default: light = SunburstPalette.fixed(.protected, .light); dark = SunburstPalette.fixed(.protected, .dark)
            }
            let parentNode = s.parent.flatMap { root.sectors[$0].node }
            let f = s.size / width
            segs.append(Segment(kind: kind, sector: i, node: s.node, parentNode: parentNode,
                                name: s.isOther ? s.name : name(s), bytes: s.size, start: x, end: x + f,
                                light: light, dark: dark))
            x += f
        }
        // Used beyond what the scan saw (system volume, APFS snapshots, unreadable folders).
        let gap = used - scanned
        if gap > max(1, total * 0.001) {
            let f = gap / width
            segs.append(Segment(kind: .systemGap, sector: nil, node: nil, parentNode: nil, name: "",
                                bytes: gap, start: x, end: x + f,
                                light: SunburstPalette.fixed(.other, .light), dark: SunburstPalette.fixed(.other, .dark)))
        }
        self.segments = segs

        // Legend: big branches individually, small ones folded; the rest always shown.
        var items: [LegendItem] = []
        var folded: [Int] = []
        var foldedBytes = 0.0, otherBytes = 0.0, protBytes = 0.0, gapBytes = 0.0
        for (j, s) in segs.enumerated() {
            switch s.kind {
            case .branch, .containerRest:
                if s.bytes / width >= Self.foldShare { items.append(.init(kind: .branch(j), bytes: s.bytes)) }
                else { folded.append(j); foldedBytes += s.bytes }
            case .other: otherBytes += s.bytes
            case .protected: protBytes += s.bytes
            case .systemGap: gapBytes += s.bytes
            }
        }
        if protBytes > 0 { items.append(.init(kind: .protected, bytes: protBytes)) }
        if otherBytes > 0 { items.append(.init(kind: .other, bytes: otherBytes)) }
        if !folded.isEmpty { items.append(.init(kind: .folded(folded), bytes: foldedBytes)) }
        if gapBytes > 0 { items.append(.init(kind: .systemGap, bytes: gapBytes)) }
        if total > used { items.append(.init(kind: .free, bytes: total - used)) }
        self.legend = items
    }

    /// Legend that fits `width` on ONE line (never wraps): keep folding the smallest
    /// shown branch into “+N 项” until it fits. 其他 / 系统保护 / 可用 always stay.
    public func fittedLegend(width: Double, itemWidth: (LegendItem) -> Double, spacing: Double = 14) -> [LegendItem] {
        var items = legend
        func fits() -> Bool {
            items.map(itemWidth).reduce(0, +) + spacing * Double(max(0, items.count - 1)) <= width
        }
        while !fits() {
            let branches = items.enumerated().compactMap { (i, it) -> (Int, Double)? in
                if case .branch = it.kind { return (i, it.bytes) } else { return nil } }
            guard let smallest = branches.min(by: { $0.1 < $1.1 }) else { break }
            guard case let .branch(seg) = items[smallest.0].kind else { break }
            let bytes = items[smallest.0].bytes
            items.remove(at: smallest.0)
            if let f = items.firstIndex(where: { if case .folded = $0.kind { return true } else { return false } }),
               case let .folded(list) = items[f].kind {
                items[f] = .init(kind: .folded((list + [seg]).sorted()), bytes: items[f].bytes + bytes)
            } else {
                let at = items.firstIndex(where: { $0.kind == .systemGap || $0.kind == .free }) ?? items.count
                items.insert(.init(kind: .folded([seg]), bytes: bytes), at: at)
            }
        }
        return items
    }

    public struct Scope: Equatable {
        /// Per segment: true = keep its colour (inside the current focus or containing it).
        public let inScope: [Bool]
        /// Bracket range (fractions) under the in-scope run; nil at the scan root.
        public let bracket: ClosedRange<Double>?
    }

    /// Drill-down marking. `isAncestorOrSelf(a, b)` = a is b or one of b's ancestors.
    /// At the scan root everything is in scope and there is no bracket.
    public func scope(focus: Node?, isRoot: Bool, isAncestorOrSelf: (Node, Node) -> Bool) -> Scope {
        guard let focus, !isRoot else {
            return Scope(inScope: Array(repeating: true, count: segments.count), bracket: nil)
        }
        var flags: [Bool] = []
        var lo = Double.infinity, hi = -Double.infinity
        for s in segments {
            var on = false
            if let n = s.node { on = isAncestorOrSelf(focus, n) || isAncestorOrSelf(n, focus) }
            else if let p = s.parentNode { on = isAncestorOrSelf(focus, p) }
            flags.append(on)
            if on { lo = min(lo, s.start); hi = max(hi, s.end) }
        }
        return Scope(inScope: flags, bracket: lo <= hi ? lo...hi : nil)
    }
}

/// Capacity-bar notice timing (UI review P2-5): clamp(8 s + 1 s per 10 characters, 8, 15).
public enum CapacityNotice {
    public static func duration(forText text: String) -> Double {
        min(15, max(8, 8 + Double(text.count / 10)))
    }
}
