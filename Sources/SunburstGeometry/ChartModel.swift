import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// OKLCH → sRGB (README §4.5, same matrices as the design's color.py).
public enum OKLCH {
    public static func rgb(_ l: Double, _ c: Double, _ hDeg: Double) -> RGB {
        let h = hDeg * Double.pi / 180
        let a = c * cos(h), b = c * sin(h)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let (L, M, S) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bb = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func enc(_ x: Double) -> Double {
            let v = max(0, min(1, x))
            let e = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            return (e * 255).rounded() / 255   // quantise like the design's hex output
        }
        return RGB(r: enc(r), g: enc(g), b: enc(bb))
    }
}

/// Segment roles of the Finder-style chart colouring (README §4.5).
public enum ChartRole: Equatable, Sendable { case root, child, container, other, protected }

/// The branch colouring formula. Pure; operates on a parent-linked segment list.
public enum SunburstPalette {
    public static let hues: [Double] = [250, 200, 155, 75, 45, 20, 350, 305, 275]
    public static let dominantShare = 0.5
    struct Params { let l0, c0, dL, dC: Double; let other, cont, prot: (Double, Double, Double) }
    static func params(_ m: ThemeMode) -> Params {
        m == .light
            ? Params(l0: 0.70, c0: 0.115, dL: 0.07, dC: 0.80, other: (0.84, 0, 0), cont: (0.80, 0.025, 250), prot: (0.80, 0, 0))
            : Params(l0: 0.525, c0: 0.100, dL: -0.045, dC: 0.85, other: (0.40, 0, 0), cont: (0.36, 0.022, 250), prot: (0.36, 0, 0))
    }
    static func hueLift(_ h: Double) -> Double {
        switch Int(h) % 360 { case 75: return 0.05; case 45: return 0.02; default: return 0 }
    }
    public static func ink(_ m: ThemeMode) -> RGB { m == .light ? RGB(0x1D1D1F) : RGB(0xFFFFFF) }
    public static func fixed(_ role: ChartRole, _ m: ThemeMode) -> RGB {
        let p = params(m)
        let t: (Double, Double, Double)
        switch role { case .container: t = p.cont; case .protected: t = p.prot; default: t = p.other }
        return OKLCH.rgb(t.0, t.1, t.2)
    }

    /// Input per segment (in an order where parents precede children).
    public struct Input: Sendable {
        public var parent: Int?
        public var depth: Int
        public var share: Double          // size / focus size
        public var hasChildren: Bool
        public var isOther: Bool
        public var isProtected: Bool
        public var sib: Int, nsib: Int
        public var startAngle: Double
        public init(parent: Int?, depth: Int, share: Double, hasChildren: Bool, isOther: Bool,
                    isProtected: Bool, sib: Int, nsib: Int, startAngle: Double) {
            self.parent = parent; self.depth = depth; self.share = share; self.hasChildren = hasChildren
            self.isOther = isOther; self.isProtected = isProtected; self.sib = sib; self.nsib = nsib
            self.startAngle = startAngle
        }
    }
    public struct Output: Equatable, Sendable {
        public var role: ChartRole
        public var hue: Double
        public var relDepth: Int
        public var light: RGB
        public var dark: RGB
    }

    public static func colorize(_ inp: [Input]) -> [Output] {
        var role = [ChartRole](repeating: .child, count: inp.count)
        var hue = [Double](repeating: 0, count: inp.count)
        var rd = [Int](repeating: 0, count: inp.count)
        var dom = [Bool](repeating: false, count: inp.count)
        var rootCandidates: [Int] = []
        for (i, s) in inp.enumerated() {
            if s.depth == 1 {
                dom[i] = s.share >= dominantShare && s.hasChildren
                if dom[i] { role[i] = .container; continue }
            } else if let p = s.parent, dom[p] {
            } else { role[i] = .child; continue }
            if s.isProtected { role[i] = .protected } else if s.isOther { role[i] = .other } else { rootCandidates.append(i) }
        }
        // Hue order = clockwise angular order (the design's DFS order).
        rootCandidates.sort { inp[$0].startAngle < inp[$1].startAngle }
        for (n, i) in rootCandidates.enumerated() { role[i] = .root; hue[i] = hues[n % hues.count] }
        var out: [Output] = []
        out.reserveCapacity(inp.count)
        for (i, s) in inp.enumerated() {
            if role[i] == .child, let p = s.parent {
                if role[p] == .other || role[p] == .protected || role[p] == .container || s.isOther || s.isProtected {
                    // Only the node's own (precomputed, already inherited) flag hatches it: an
                    // allowed exception below a system location (e.g. /usr/local) is neutral grey.
                    role[i] = s.isProtected ? .protected : .other
                } else {
                    hue[i] = hue[p] + (Double(s.sib) - Double(s.nsib - 1) / 2) * 7
                    rd[i] = rd[p] + 1
                }
            }
            func col(_ m: ThemeMode) -> RGB {
                let p = params(m)
                switch role[i] {
                case .root, .child:
                    let lift = (m == .light && role[i] == .root) ? hueLift(hue[i]) : 0
                    let odd = (s.sib % 2 == 1 && rd[i] > 0) ? 0.02 * (m == .light ? 1 : -1) : 0
                    let L = p.l0 + lift + p.dL * Double(rd[i]) + odd
                    let C = p.c0 * pow(p.dC, Double(rd[i]))
                    return OKLCH.rgb(L, C, hue[i])
                default: return fixed(role[i], m)
                }
            }
            out.append(Output(role: role[i], hue: hue[i], relDepth: rd[i], light: col(.light), dark: col(.dark)))
        }
        return out
    }
}

/// Rough display width (design `tw`): CJK ≈ 1 em, others ≈ 0.56 em.
public enum TextWidth {
    public static func estimate(_ s: String, fontSize: Double) -> Double {
        s.unicodeScalars.reduce(0.0) { $0 + ($1.value > 0x2E80 ? fontSize : fontSize * 0.56) }
    }
}

/// Everything the chart draws, computed once per (focus, metric, generation) in
/// design units (k = 1). Drawing, hover and appearance changes only read this.
public struct ChartModel<Node> {
    public struct Sector {
        public let index: Int
        public let depth: Int
        public let startAngle, endAngle, innerRadius, outerRadius: Double
        public let parent: Int?
        public let node: Node?            // nil for “其他”
        public let otherCount: Int
        public let size: Double
        public let name: String           // display (path-compressed) or “其他 N 项”
        public let sizeText: String
        public let isHighRisk: Bool
        public let isProtected: Bool
        public let color: SunburstPalette.Output
        /// Tiered in-ring label (LabelLayout) for the model's current scale tier; `.hidden` → hover tooltip.
        public internal(set) var label: SectorLabel
        /// 0 = no inner label, 1 = one line, 2 = name + size.
        public var labelLines: Int { label.tier == .nameAndSize ? 2 : (label.tier == .hidden ? 0 : 1) }
        /// Name text shown in the ring (`name` stays the full name for tooltips/VoiceOver).
        public var labelName: String { label.tier == .nameAndSize ? ChartModel.stripRisk(label.lines[0]) : name }
        /// Label text colour per appearance, picked for contrast against this sector's fill.
        public let inkLight: RGB
        public let inkDark: RGB
        public var isOther: Bool { node == nil }
        public var midAngle: Double { (startAngle + endAngle) / 2 }
        /// Angular width (radians), same meaning as `SunburstLayout.Segment.span`.
        public var span: Double { endAngle - startAngle }
    }
    public let layout: SunburstLayout<Node>
    public private(set) var sectors: [Sector]
    /// Label layouts per scale tier (≤ 6), shared by copies of this model.
    public let labelCache: LabelLayout.Cache
    /// Scale tier the sectors' labels were laid out for (LabelMetrics.tier).
    public private(set) var labelTier: Double = 1
    /// Swaps in the labels for the tier of scale `k` (cached; places at most once per tier).
    /// Returns true when the tier changed.
    @discardableResult
    public mutating func applyLabelScale(_ k: Double) -> Bool {
        let t = LabelMetrics.tier(for: k)
        guard t != labelTier else { return false }
        let labels = labelCache.labels(tier: t)
        for i in sectors.indices { sectors[i].label = labels[i] }
        labelTier = t
        return true
    }
    /// Children of each sector (and of the centre at key -1) in clockwise order.
    public let childrenOf: [Int: [Int]]

    /// Widest in-ring label box the view draws (SunburstView caps the group at this width).
    public static var labelMaxWidth: Double { 140 }
    /// Separator used by path compression ("Users › tester").
    public static var pathSeparator: String { " › " }

    /// Pure in-ring label fitting (unit-tested). Candidates in order: the full name, the last
    /// path component, the last component truncated at the TAIL ("Containe…"). Returns nil
    /// when not even 3 characters + "…" fit, so the sector gets no label.
    public static func fitLabel(_ name: String, highRisk: Bool, available: Double) -> String? {
        let prefix = highRisk ? "⚠ " : ""
        func fits(_ t: String) -> Bool { TextWidth.estimate(prefix + t, fontSize: 11) <= available }
        if fits(name) { return name }
        let last = name.components(separatedBy: pathSeparator).last ?? name
        if last != name, fits(last) { return last }
        var chars = Array(last)
        while chars.count > 3 {
            chars.removeLast()
            let t = String(chars) + "…"
            if fits(t) { return t }
        }
        return nil
    }

    static func stripRisk(_ t: String) -> String { t.hasPrefix("⚠ ") ? String(t.dropFirst(2)) : t }

    /// Hover tooltip for a sector whose label hides or shortens its name (nil when the
    /// label already shows the full name and size). Lines: name, path, size · share.
    public func hoverTooltip(_ index: Int, path: (Node) -> String) -> String? {
        guard sectors.indices.contains(index) else { return nil }
        let s = sectors[index]
        if s.label.tier == .nameAndSize && s.label.showsFullName { return nil }
        let share = layout.rootSize > 0 ? s.size / layout.rootSize * 100 : 0
        var lines = [s.name]
        if let n = s.node { lines.append(path(n)) }
        lines.append(s.sizeText + " · " + String(format: "%.1f%%", share))
        return lines.joined(separator: "\n")
    }

    public enum Step: Sendable { case previous, next, child, parent }
    /// Keyboard navigation (P2-11): ←/→ = previous/next sibling (wrapping, clockwise
    /// order), ↓ = first (largest) child sector, ↑ = parent sector. nil selection →
    /// the first ring-1 sector. Returns nil when there is nowhere to go.
    public func step(from sel: Int?, _ dir: Step) -> Int? {
        guard let i = sel, sectors.indices.contains(i) else { return childrenOf[-1]?.first }
        switch dir {
        case .previous, .next:
            let sibs = childrenOf[sectors[i].parent ?? -1] ?? [i]
            guard let at = sibs.firstIndex(of: i), sibs.count > 1 else { return nil }
            return sibs[(at + (dir == .next ? 1 : sibs.count - 1)) % sibs.count]
        case .child: return childrenOf[i]?.first
        case .parent: return sectors[i].parent
        }
    }

    public func ancestorOrSelf(_ a: Int, of s: Int) -> Bool {
        var cur: Int? = s
        while let c = cur { if c == a { return true }; cur = sectors[c].parent }
        return false
    }
    /// Opacity per sector for a hovered branch (1 inside, 0.42 outside); nil hover = all 1.
    public func opacities(hover: Int?) -> [Double] {
        guard let h = hover else { return Array(repeating: 1, count: sectors.count) }
        return sectors.map { ancestorOrSelf(h, of: $0.index) ? 1 : 0.42 }
    }

    /// Finder-style ring geometry (README §4.4) in design units.
    public static var finderConfig: SunburstConfig {
        var c = SunburstConfig(centerRadius: 92, ringWidth: 64, maxDepth: 3, minSliceAngle: 0.001,
                               minOtherAngle: 0.001, padAngle: 0,
                               rings: [RingSpec(inner: 100, outer: 164), RingSpec(inner: 168, outer: 224),
                                       RingSpec(inner: 228, outer: 276)],
                               maxKidsPerParent: 10, minArcPoints: 6, pathCompressRatio: 0.97,
                               gapPoints: 1.5, scale: 1)
        c.maxSegments = 150
        return c
    }
    /// View scale k = clamp(min(w, h − 40) / 600, 0.75, 1.15) (capacity-bar spec: floor 0.75).
    public static func scale(width: Double, height: Double) -> Double {
        min(1.15, max(0.75, min(width, height - 40) / 600))
    }
}

extension ChartModel where Node: SunburstNamed {
    public init(focus: Node, config: SunburstConfig = ChartModel.finderConfig, labelScale: Double = 1,
                isProtected: (Node) -> Bool, isHighRisk: (Node) -> Bool,
                sizeText: (Double) -> String, otherName: (Int) -> String) {
        let lay = SunburstLayout(root: focus, config: config)
        self.layout = lay
        var kids: [Int: [Int]] = [:]
        for s in lay.segments { kids[s.parentIndex ?? -1, default: []].append(s.index) }
        for k in kids.keys { kids[k]!.sort { lay.segments[$0].startAngle < lay.segments[$1].startAngle } }
        var sibIdx = [Int](repeating: 0, count: lay.segments.count)
        var nsib = [Int](repeating: 1, count: lay.segments.count)
        for (_, list) in kids { for (j, i) in list.enumerated() { sibIdx[i] = j; nsib[i] = list.count } }
        let total = max(lay.rootSize, 1)
        var prot = [Bool](repeating: false, count: lay.segments.count)
        var inputs: [SunburstPalette.Input] = []
        inputs.reserveCapacity(lay.segments.count)
        for s in lay.segments {
            if let n = s.node { prot[s.index] = isProtected(n) }
            inputs.append(.init(parent: s.parentIndex, depth: s.depth, share: s.size / total,
                                hasChildren: kids[s.index] != nil || (s.node.map { !$0.sunburstChildren.isEmpty } ?? false),
                                isOther: s.isOther, isProtected: prot[s.index],
                                sib: sibIdx[s.index], nsib: nsib[s.index], startAngle: s.startAngle))
        }
        let colors = SunburstPalette.colorize(inputs)
        // Pass 1: texts + label inputs; pass 2: tiered label placement (LabelLayout);
        // pass 3: sectors. All part of the cached model — redraw/hover/resize never re-measure.
        var names: [String] = [], sizes: [String] = [], risks: [Bool] = [], counts: [Int] = []
        var inputs2: [LabelLayout.Input] = []
        names.reserveCapacity(lay.segments.count); inputs2.reserveCapacity(lay.segments.count)
        for s in lay.segments {
            var name = lay.displayNames[s.index], count = 0
            if case let .other(c, _) = s.content { count = c; name = otherName(c) }
            let st = sizeText(s.size)
            let risk = s.node.map(isHighRisk) ?? false
            names.append(name); sizes.append(st); risks.append(risk); counts.append(count)
            inputs2.append(.init(wedge: .init(start: s.startAngle, end: s.endAngle, inner: s.innerRadius, outer: s.outerRadius),
                                 name: name, sizeText: st, highRisk: risk, allowText: !prot[s.index], importance: s.size,
                                 isOther: s.isOther))
        }
        let cache = LabelLayout.Cache(inputs: inputs2)
        let tier = LabelMetrics.tier(for: labelScale)
        let labels = cache.labels(tier: tier)
        var secs: [Sector] = []
        secs.reserveCapacity(lay.segments.count)
        for s in lay.segments {
            let i = s.index, lab = labels[i]
            secs.append(Sector(index: i, depth: s.depth, startAngle: s.startAngle, endAngle: s.endAngle,
                               innerRadius: s.innerRadius, outerRadius: s.outerRadius, parent: s.parentIndex,
                               node: s.node, otherCount: counts[i], size: s.size, name: names[i], sizeText: sizes[i],
                               isHighRisk: risks[i], isProtected: prot[i], color: colors[i], label: lab,
                               inkLight: LabelLayout.ink(on: colors[i].light), inkDark: LabelLayout.ink(on: colors[i].dark)))
        }
        self.sectors = secs
        self.childrenOf = kids
        self.labelCache = cache
        self.labelTier = tier
    }
}

/// Outline levels below the chart's rings use the chart's merge rule: hide
/// zero-size / unreadable, top `maxKids` by size, the rest becomes “其他 N 项”.
public enum OutlineRules {
    public struct Level<Node> {
        public var shown: [Node]
        public var otherCount: Int
        public var otherSize: Double
    }
    public static func children<N: SunburstNamed>(of node: N, maxKids: Int = 10) -> Level<N> {
        var visible = node.sunburstChildren.filter { $0.sunburstSize > 0 && !$0.sunburstIsRestricted }
        var presorted = true
        var prev = Double.infinity
        for c in visible { let v = c.sunburstSize; if v > prev { presorted = false; break }; prev = v }
        if !presorted { visible.sort { $0.sunburstSize > $1.sunburstSize } }
        let shown = Array(visible.prefix(maxKids))
        let rest = visible.dropFirst(maxKids)
        let restricted = node.sunburstChildren.filter { $0.sunburstIsRestricted && $0.sunburstSize > 0 }
        return Level(shown: shown, otherCount: rest.count + restricted.count,
                     otherSize: rest.reduce(0) { $0 + $1.sunburstSize } + restricted.reduce(0) { $0 + $1.sunburstSize })
    }
}
