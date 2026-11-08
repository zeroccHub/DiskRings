import Foundation

/// In-ring sunburst labels, computed with the ChartModel per scale tier (cached, ≤ 6 tiers) so
/// a redraw/hover/appearance change never re-measures. Tiers (default order rotatedNameFirst):
///   `.nameAndSize` horizontal two lines · `.rotated` one line along the arc, then radius
///   (name first) · `.sizeOnly` horizontal size · rotated size · `.hidden` (hover tooltip)
/// A candidate is accepted only if all 8 sample points of its box (corners + edge midpoints)
/// lie inside the sector shrunk by `LabelMetrics.padding`, and its box does not intersect any
/// already placed label (separating-axis test on oriented rectangles). Sectors are placed in
/// descending size, so big sectors win any conflict.
public enum LabelTier: Int, Sendable, Comparable {
    case nameAndSize = 0, sizeOnly, rotated, hidden
    public static func < (a: LabelTier, b: LabelTier) -> Bool { a.rawValue < b.rawValue }
}

/// Design numbers (designer spec 2026-10-13, README «Sunburst labels»). Values are in chart
/// units for one scale tier; on screen a value v is drawn at v·k. Screen targets (pt):
///   name font max(10, 11k) · size font max(10, 10k) · name line max(13, 14k)
///   size line max(12, 12k) · padding max(2, 2.5k) · box inset 1.5k.
/// Units are derived from the tier k_b ≤ k, so every label is ≥ 10 pt on screen.
public struct LabelMetrics: Equatable, Sendable {
    public var tier: Double
    public var nameFont: Double, sizeFont: Double
    public var nameLine: Double, sizeLine: Double
    public var padding: Double
    public static let boxInset: Double = 1.5     // horizontal text inset inside the box (units)
    public static let minLatinChars = 4          // truncation keeps ≥ 4 Latin letters …
    public static let minCJKChars = 2            // … or ≥ 2 CJK characters (CJK counts double)
    public static let minScreenFont: Double = 10
    public static let scaleFloor: Double = 0.75
    public static let tierStep: Double = 0.05
    public static let maxCachedTiers = 6         // 0.75 0.80 0.85 0.90 0.95 1.0(≥1)
    /// k ≥ 1 → 1 (metrics scale with k); k < 1 → floor to 0.05 steps, never below 0.75.
    public static func tier(for k: Double) -> Double {
        guard k < 1 else { return 1 }
        let n = (max(k, scaleFloor) / tierStep + 1e-9).rounded(.down)
        return max(scaleFloor, n / 20)
    }
    public static let base = LabelMetrics(tier: 1, nameFont: 11, sizeFont: 10, nameLine: 14, sizeLine: 12, padding: 2.5)
    public static func forScale(_ k: Double) -> LabelMetrics {
        let kb = tier(for: k)
        guard kb < 1 else { return base }
        return LabelMetrics(tier: kb, nameFont: max(10, 11 * kb) / kb, sizeFont: max(10, 10 * kb) / kb,
                            nameLine: max(13, 14 * kb) / kb, sizeLine: max(12, 12 * kb) / kb,
                            padding: max(2, 2.5 * kb) / kb)
    }
}

public struct SectorLabel: Equatable, Sendable {
    public var tier: LabelTier
    /// 1 or 2 lines (top first). Empty for `.hidden`.
    public var lines: [String]
    public var center: Point2D
    /// Text baseline angle, radians, counter-clockwise from +x (0 = horizontal).
    public var rotation: Double
    public var width: Double
    public var height: Double
    /// True when lines[0] is the full name (no shortening and not size-only/hidden).
    public var showsFullName: Bool
    /// Fonts / line heights (chart units) the view must draw with (from LabelMetrics).
    public var nameFont: Double, sizeFont: Double, nameLine: Double, sizeLine: Double
    /// True when the single line is the size text (sizeOnly or rotated size).
    public var isSizeLine: Bool
    public init(tier: LabelTier, lines: [String], center: Point2D, rotation: Double, width: Double, height: Double,
                showsFullName: Bool, metrics m: LabelMetrics = .base, isSizeLine: Bool = false) {
        self.tier = tier; self.lines = lines; self.center = center; self.rotation = rotation
        self.width = width; self.height = height; self.showsFullName = showsFullName
        nameFont = m.nameFont; sizeFont = m.sizeFont; nameLine = m.nameLine; sizeLine = m.sizeLine
        self.isSizeLine = isSizeLine
    }
    public static let hidden = SectorLabel(tier: .hidden, lines: [], center: Point2D(x: 0, y: 0), rotation: 0,
                                           width: 0, height: 0, showsFullName: false)

    /// Corners of the oriented box.
    public var corners: [Point2D] {
        let c = cos(rotation), s = sin(rotation), hw = width / 2, hh = height / 2
        return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].map { (u, v) in
            Point2D(x: center.x + u * c - v * s, y: center.y + u * s + v * c)
        }
    }
}

public enum LabelLayout {
    /// Geometry of one sector (layout angles: clockwise from 12 o'clock; y up).
    public struct Wedge: Sendable {
        public var start, end, inner, outer: Double
        public init(start: Double, end: Double, inner: Double, outer: Double) {
            self.start = start; self.end = end; self.inner = inner; self.outer = outer
        }
        var span: Double { end - start }
        var mid: Double { (start + end) / 2 }
    }
    public struct Input: Sendable {
        public var wedge: Wedge
        public var name: String
        public var sizeText: String
        public var highRisk: Bool
        public var allowText: Bool          // false for protected sectors (lock icon instead)
        public var importance: Double       // bytes; larger is placed first
        public var isOther: Bool            // “其他 N 项”: never truncated
        public init(wedge: Wedge, name: String, sizeText: String, highRisk: Bool, allowText: Bool, importance: Double,
                    isOther: Bool = false) {
            self.wedge = wedge; self.name = name; self.sizeText = sizeText; self.isOther = isOther
            self.highRisk = highRisk; self.allowText = allowText; self.importance = importance
        }
    }

    static func width(_ t: String, _ f: Double) -> Double { TextWidth.estimate(t, fontSize: f) + 2 * LabelMetrics.boxInset }

    /// Up to `LabelMetrics.maxCachedTiers` label layouts of one model, keyed by scale tier.
    /// Thread-safe; `builds` counts actual placements (tests: no relayout on a cache hit).
    public final class Cache: @unchecked Sendable {
        public let inputs: [Input]
        private let lock = NSLock()
        private var entries: [(tier: Double, labels: [SectorLabel])] = []
        public private(set) var builds = 0
        public init(inputs: [Input]) { self.inputs = inputs }
        public var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
        public var tiers: [Double] { lock.lock(); defer { lock.unlock() }; return entries.map(\.tier) }
        public func labels(tier: Double) -> [SectorLabel] {
            let t = LabelMetrics.tier(for: tier)
            lock.lock(); defer { lock.unlock() }
            if let i = entries.firstIndex(where: { $0.tier == t }) {
                let e = entries.remove(at: i); entries.append(e); return e.labels   // LRU
            }
            let l = LabelLayout.place(inputs, metrics: .forScale(t))
            builds += 1
            entries.append((t, l))
            if entries.count > LabelMetrics.maxCachedTiers { entries.removeFirst() }
            return l
        }
    }

    /// When to re-layout labels: only when the scale tier changes, and never during a live
    /// (drag) resize — the tier is checked again when the live resize ends.
    public struct RelayoutPolicy: Sendable {
        public private(set) var tier: Double
        public init(tier: Double = 1) { self.tier = LabelMetrics.tier(for: tier) }
        public mutating func reset(_ t: Double) { tier = LabelMetrics.tier(for: t) }
        /// Bounds changed. Returns the new tier to apply, or nil (unchanged tier / live resize).
        public mutating func boundsChanged(scale k: Double, inLiveResize: Bool) -> Double? {
            guard !inLiveResize else { return nil }
            return update(k)
        }
        public mutating func liveResizeEnded(scale k: Double) -> Double? { update(k) }
        private mutating func update(_ k: Double) -> Double? {
            let t = LabelMetrics.tier(for: k)
            guard t != tier else { return nil }
            tier = t; return t
        }
    }

    /// Is the point inside the wedge shrunk by `pad`?
    static func inside(_ p: Point2D, _ w: Wedge, pad: Double) -> Bool {
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        guard r >= w.inner + pad, r <= w.outer - pad else { return false }
        if w.span >= 2 * Double.pi - 1e-9 { return true }
        var a = atan2(p.x, p.y); if a < 0 { a += 2 * Double.pi }
        // angular distance of p from the wedge's start/end rays, as a length at radius r
        func norm(_ x: Double) -> Double { var y = x.truncatingRemainder(dividingBy: 2 * Double.pi); if y < 0 { y += 2 * Double.pi }; return y }
        let fromStart = norm(a - w.start)
        guard fromStart <= w.span else { return false }
        let fromEnd = w.span - fromStart
        return r * sin(min(fromStart, Double.pi / 2)) >= pad && r * sin(min(fromEnd, Double.pi / 2)) >= pad
    }

    static func fits(_ l: SectorLabel, _ w: Wedge, pad: Double = LabelMetrics.base.padding) -> Bool {
        fits(Box(l), w, pad: pad)
    }

    /// Allocation-free oriented box used by the placement hot path.
    struct Box {
        var cx, cy, hw, hh, c, s: Double
        init(cx: Double, cy: Double, w: Double, h: Double, rot: Double) {
            self.cx = cx; self.cy = cy; hw = w / 2; hh = h / 2; c = cos(rot); s = sin(rot)
        }
        init(_ l: SectorLabel) { self.init(cx: l.center.x, cy: l.center.y, w: l.width, h: l.height, rot: l.rotation) }
        var radius: Double { (hw * hw + hh * hh).squareRoot() }
        /// Half-extent of the box projected on unit axis (nx, ny).
        @inline(__always) func extent(_ nx: Double, _ ny: Double) -> Double {
            hw * abs(c * nx + s * ny) + hh * abs(-s * nx + c * ny)
        }
    }

    /// 8 samples (corners + edge midpoints) inside the shrunk wedge; early exit on first miss.
    static func fits(_ b: Box, _ w: Wedge, pad: Double) -> Bool {
        @inline(__always) func at(_ u: Double, _ v: Double) -> Bool {
            inside(Point2D(x: b.cx + u * b.c - v * b.s, y: b.cy + u * b.s + v * b.c), w, pad: pad)
        }
        let hw = b.hw, hh = b.hh
        return at(-hw, -hh) && at(hw, -hh) && at(hw, hh) && at(-hw, hh)
            && at(0, -hh) && at(hw, 0) && at(0, hh) && at(-hw, 0)
    }

    /// Separating-axis test for two oriented rectangles (no allocation).
    static func overlaps(_ a: Box, _ b: Box) -> Bool {
        let dx = a.cx - b.cx, dy = a.cy - b.cy
        let rr = a.radius + b.radius
        if dx * dx + dy * dy >= rr * rr { return false }
        for (nx, ny) in [(a.c, a.s), (-a.s, a.c), (b.c, b.s), (-b.s, b.c)] as [(Double, Double)] {
            if abs(dx * nx + dy * ny) >= a.extent(nx, ny) + b.extent(nx, ny) { return false }
        }
        return true
    }
    public static func overlaps(_ a: SectorLabel, _ b: SectorLabel) -> Bool { overlaps(Box(a), Box(b)) }

    /// Reverse-domain roots whose first segment is dropped before truncating.
    public static let reverseDomainRoots: Set<String> = ["com", "org", "net", "io", "cn", "me", "dev"]
    /// "com.tencent.xinWeChat" → "tencent.xinWeChat" (≥ 3 segments, known root); else unchanged.
    public static func dropReverseDomainRoot(_ s: String) -> String {
        guard let dot = s.firstIndex(of: "."), reverseDomainRoots.contains(s[..<dot].lowercased()) else { return s }
        let rest = s[s.index(after: dot)...]
        guard rest.contains("."), !rest.hasPrefix(".") else { return s }
        return String(rest)
    }
    static func isCJK(_ ch: Character) -> Bool { ch.unicodeScalars.first.map { $0.value > 0x2E80 } ?? false }

    /// Name candidates, longest first, that are at most `room` wide: the full name, the last
    /// path component, the component without its reverse-domain root, then tail truncations
    /// ("tencent.x…") keeping ≥ 4 Latin letters or ≥ 2 CJK characters. “其他 N 项” (`isOther`)
    /// is only ever offered in full.
    static func nameCandidates(_ name: String, prefix: String, font: Double, room: Double,
                               isOther: Bool = false, limit: Int = .max) -> [String] {
        var out: [String] = []
        if width(prefix + name, font) <= room { out.append(name) }
        if isOther || out.count >= limit { return out }
        let last = name.range(of: " › ", options: .backwards).map { String(name[$0.upperBound...]) } ?? name
        if last != name, width(prefix + last, font) <= room { out.append(last) }
        let base = dropReverseDomainRoot(last)
        if base != last, width(prefix + base, font) <= room { out.append(base) }
        if out.count >= limit { return out }
        // Tail truncations of `base` + "…" at shrinking widths (room · 1, 0.8, 0.64, …): the
        // chord is only an upper bound, the wedge shape decides which one fits.
        var target = room, prevCount = Int.max
        let ell = width(prefix + "…", font)
        while target >= ell {
            var used = ell, cut = "", n = 0, weight = 0
            for ch in base {
                let cjk = isCJK(ch)
                let w = ch.unicodeScalars.reduce(0.0) { $0 + ($1.value > 0x2E80 ? font : font * 0.56) }
                if used + w > target { break }
                used += w; cut.append(ch); n += 1; weight += cjk ? 2 : 1
            }
            // ≥ 4 Latin letters, or ≥ 2 CJK characters (a CJK character weighs 2).
            if weight < LabelMetrics.minLatinChars { break }
            if n < base.count && n < prevCount {
                out.append(cut + "…"); prevCount = n
                if out.count >= limit { break }
            }
            target *= 0.8
        }
        return out
    }

    /// Where to try a horizontal box: the mid angle first, then (for wide wedges) the angle
    /// inside the wedge whose radius is closest to vertical (12 or 6 o'clock), where a
    /// horizontal box uses the ring thickness least, then the 1/3 and 2/3 points.
    static func horizontalCenters(_ w: Wedge, rm: Double) -> [Point2D] {
        var angles = [w.mid]
        if w.span > 0.35 {
            let margin = min(w.span / 4, 0.3)
            let lo = w.start + margin, hi = w.end - margin
            for target in [0.0, Double.pi, 2 * Double.pi] {
                let a = min(max(target, lo), hi)
                if abs(a - w.mid) > 0.05 { angles.append(a) }
            }
            angles.append(w.start + w.span / 3); angles.append(w.start + 2 * w.span / 3)
        }
        return angles.map { Point2D(x: rm * sin($0), y: rm * cos($0)) }
    }

    /// Readable baseline angle (radians, CCW from +x) in (-π/2, π/2].
    static func readable(_ a: Double) -> Double {
        var r = atan2(sin(a), cos(a))
        if r > Double.pi / 2 + 1e-9 { r -= Double.pi } else if r <= -Double.pi / 2 - 1e-9 { r += Double.pi }
        return r
    }

    /// Tier order. `.rotatedNameFirst` (default, designer 2026-10-13): name+size → rotated
    /// name (tangent, then radial) → size only → rotated size → hidden. `.spec` = earlier
    /// brief order (name+size → size → rotated name/size → hidden).
    public enum Order: Sendable { case spec, rotatedNameFirst }

    static func firstFit(_ i: Input, placed: [Box], order: Order, m: LabelMetrics) -> SectorLabel? {
        let w = i.wedge
        let rm = (w.inner + w.outer) / 2
        let mid = Point2D(x: rm * sin(w.mid), y: rm * cos(w.mid))
        let risk = i.highRisk ? "⚠ " : ""
        let sizeW = width(i.sizeText, m.sizeFont)
        let ln = m.nameLine, ls = m.sizeLine
        // Geometry first (allocation-free); a SectorLabel is only built for the winner.
        func ok(_ c: Point2D, _ bw: Double, _ bh: Double, _ rot: Double) -> Bool {
            let b = Box(cx: c.x, cy: c.y, w: bw, h: bh, rot: rot)
            guard fits(b, w, pad: m.padding) else { return false }
            for p in placed where overlaps(p, b) { return false }
            return true
        }
        let thickness = w.outer - w.inner - 2 * m.padding
        let arc = 2 * rm * sin(min(Double.pi / 2, w.span / 2))            // chord at mid radius
        let minBox = min(ln, ls)
        // Name candidates for the arc-wide room (shared by horizontal + tangent), lazily.
        var arcNames: [String]?
        func namesForArc() -> [String] {
            if let n = arcNames { return n }
            let n = nameCandidates(i.name, prefix: risk, font: m.nameFont, room: arc, isOther: i.isOther); arcNames = n; return n
        }
        // 1. name + size, horizontal
        if thickness >= ln + ls || arc >= ln + ls {
            let centers = horizontalCenters(w, rm: rm)
            for n in namesForArc() {
                let bw = max(width(risk + n, m.nameFont), sizeW)
                for c in centers where ok(c, bw, ln + ls, 0) {
                    return SectorLabel(tier: .nameAndSize, lines: [risk + n, i.sizeText], center: c, rotation: 0,
                                       width: bw, height: ln + ls, showsFullName: n == i.name, metrics: m)
                }
            }
        }
        func sizeOnly() -> SectorLabel? {
            ok(mid, sizeW, ls, 0) ? SectorLabel(tier: .sizeOnly, lines: [i.sizeText], center: mid, rotation: 0, width: sizeW,
                                                height: ls, showsFullName: false, metrics: m, isSizeLine: true) : nil
        }
        func rotatedSize(_ rot: Double) -> SectorLabel? {
            ok(mid, sizeW, ls, rot) ? SectorLabel(tier: .rotated, lines: [i.sizeText], center: mid, rotation: rot, width: sizeW,
                                                  height: ls, showsFullName: false, metrics: m, isSizeLine: true) : nil
        }
        if order == .spec, let s = sizeOnly() { return s }
        let tangent = readable(-w.mid), radial = readable(Double.pi / 2 - w.mid)
        for (rot, isArc) in [(tangent, true), (radial, false)] {
            let room = isArc ? arc : thickness
            if room >= minBox {
                let n = isArc ? namesForArc().first
                              : nameCandidates(i.name, prefix: risk, font: m.nameFont, room: room, isOther: i.isOther, limit: 1).first
                if let n {
                    let bw = width(risk + n, m.nameFont)
                    if ok(mid, bw, ln, rot) {
                        return SectorLabel(tier: .rotated, lines: [risk + n], center: mid, rotation: rot,
                                           width: bw, height: ln, showsFullName: n == i.name, metrics: m)
                    }
                }
            }
            if order == .spec, let l = rotatedSize(rot) { return l }
        }
        if order == .rotatedNameFirst {
            if let s = sizeOnly() { return s }
            if let l = rotatedSize(tangent) ?? rotatedSize(radial) { return l }
        }
        return nil
    }

    /// Places labels for all sectors with the metrics of one scale tier. Result is indexed like `inputs`.
    public static func place(_ inputs: [Input], metrics m: LabelMetrics = .base, obstacles: [SectorLabel] = [],
                             order: Order = .rotatedNameFirst) -> [SectorLabel] {
        var result = [SectorLabel](repeating: .hidden, count: inputs.count)
        var placed = obstacles.map(Box.init)
        placed.reserveCapacity(inputs.count + obstacles.count)
        let byImportance = inputs.indices.sorted { inputs[$0].importance > inputs[$1].importance }
        let minBox = min(m.nameLine, m.sizeLine) + 2 * m.padding
        for idx in byImportance {
            let inp = inputs[idx]
            guard inp.allowText, inp.wedge.span > 0 else { continue }
            let rm = (inp.wedge.inner + inp.wedge.outer) / 2
            // Quick reject: thinner than one line both ways → hidden.
            if inp.wedge.span * rm < minBox, inp.wedge.outer - inp.wedge.inner < minBox { continue }
            if let l = firstFit(inp, placed: placed, order: order, m: m) { result[idx] = l; placed.append(Box(l)) }
        }
        return result
    }

    /// Label ink with the higher WCAG contrast against the sector fill.
    public static func ink(on fill: RGB) -> RGB {
        let dark = RGB(0x1D1D1F), light = RGB(0xFFFFFF)
        return RGB.contrast(dark, fill) >= RGB.contrast(light, fill) ? dark : light
    }
}
