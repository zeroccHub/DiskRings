import Foundation

/// Anything that can be laid out as a sunburst: a size and ordered children.
/// Children should be sorted the way they are to appear (clockwise).
public protocol SunburstNode {
    var sunburstSize: Double { get }
    var sunburstChildren: [Self] { get }
}

public struct RingSpec: Equatable, Sendable {
    public var inner: Double
    public var outer: Double
    public init(inner: Double, outer: Double) { self.inner = inner; self.outer = outer }
    public var mid: Double { (inner + outer) / 2 }
    public var width: Double { outer - inner }
}

public struct SunburstConfig: Equatable, Sendable {
    /// Radius of the central disc (represents the current/focused node).
    public var centerRadius: Double = 70
    /// Radial thickness of each ring (legacy uniform mode when `rings` is nil).
    public var ringWidth: Double = 38
    /// Number of rings drawn around the center (ignored when `rings` is set).
    public var maxDepth: Int = 5
    /// Slices narrower than this (radians) are merged into one "other" slice per parent.
    public var minSliceAngle: Double = 0.012
    /// "Other" slices narrower than this are not emitted at all.
    public var minOtherAngle: Double = 0.002
    /// Gap (radians) trimmed from each side of a segment, for visual separation.
    public var padAngle: Double = 0.0
    /// Per-ring radii. When set, overrides uniform `ringWidth`/`maxDepth`.
    public var rings: [RingSpec]? = nil
    /// Max individually shown children per parent (Finder chart: 10). `.max` = unlimited.
    public var maxKidsPerParent: Int = Int.max
    /// Minimum arc length in points at the ring mid-line; when > 0, used instead of / with minSliceAngle.
    public var minArcPoints: Double = 0
    /// Path-compression threshold (child/parent size). Values ≥ 1 disable compression.
    public var pathCompressRatio: Double = 1.01
    /// Tangential gap as arc length in points (Finder chart: 1.5). Converted per-radius when drawing.
    public var gapPoints: Double = 0
    /// Design scale factor.
    public var scale: Double = 1
    /// Hard cap on emitted segments (Finder chart: 150). Excess children merge into “其他”.
    public var maxSegments: Int = Int.max

    public init(centerRadius: Double = 70, ringWidth: Double = 38, maxDepth: Int = 5,
                minSliceAngle: Double = 0.012, minOtherAngle: Double = 0.002, padAngle: Double = 0,
                rings: [RingSpec]? = nil, maxKidsPerParent: Int = Int.max,
                minArcPoints: Double = 0, pathCompressRatio: Double = 1.01,
                gapPoints: Double = 0, scale: Double = 1) {
        self.centerRadius = centerRadius
        self.ringWidth = ringWidth
        self.maxDepth = maxDepth
        self.minSliceAngle = minSliceAngle
        self.minOtherAngle = minOtherAngle
        self.padAngle = padAngle
        self.rings = rings
        self.maxKidsPerParent = maxKidsPerParent
        self.minArcPoints = minArcPoints
        self.pathCompressRatio = pathCompressRatio
        self.gapPoints = gapPoints
        self.scale = scale
    }

    public var depthCount: Int { rings?.count ?? maxDepth }

    public var outerRadius: Double {
        if let rings, let last = rings.last { return last.outer }
        return centerRadius + ringWidth * Double(maxDepth)
    }

    public func radii(forDepth depth: Int) -> (inner: Double, outer: Double) {
        if let rings, depth >= 1, depth <= rings.count {
            let r = rings[depth - 1]
            return (r.inner, r.outer)
        }
        let inner = centerRadius + ringWidth * Double(depth - 1)
        return (inner, inner + ringWidth)
    }

    /// Legacy uniform rings.
    public static func fitting(diameter: Double, maxDepth: Int = 5) -> SunburstConfig {
        let radius = max(40, diameter / 2 - 4)
        let center = radius * 0.24
        let ring = (radius - center) / Double(max(1, maxDepth))
        return SunburstConfig(centerRadius: center, ringWidth: ring, maxDepth: maxDepth)
    }

}

public enum SegmentContent<Node> {
    case node(Node)
    /// Merged small slices: how many children and their total size.
    case other(count: Int, size: Double)
}

public struct SunburstSegment<Node> {
    public let index: Int
    /// 1 = innermost ring.
    public let depth: Int
    /// Layout angles in radians, measured clockwise from 12 o'clock, 0 ≤ start < end ≤ 2π.
    public let startAngle: Double
    public let endAngle: Double
    public let innerRadius: Double
    public let outerRadius: Double
    public let parentIndex: Int?
    /// Index of the depth-1 ancestor (or self), useful for colouring families.
    public let rootSliceIndex: Int
    public let size: Double
    public let content: SegmentContent<Node>

    public var span: Double { endAngle - startAngle }
    public var midAngle: Double { (startAngle + endAngle) / 2 }
    public var isOther: Bool { if case .other = content { return true } else { return false } }
    public var node: Node? { if case let .node(n) = content { return n } else { return nil } }
}

public enum SunburstHit: Equatable {
    case center
    case segment(Int)
    case none
}

public struct Point2D: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct SunburstLayout<Node> {
    public let config: SunburstConfig
    public let segments: [SunburstSegment<Node>]
    public let rootSize: Double
    /// Parallel to `segments`: display label (path-compressed or “其他 N 项”).
    public let displayNames: [String]
    /// Segment indices per ring (index 0 = depth 1), sorted by start angle.
    let rings: [[Int]]

    public static var fullTurn: Double { 2 * Double.pi }

    public var ringCount: Int { rings.count }
    public func segments(inRing depth: Int) -> [SunburstSegment<Node>] {
        guard depth >= 1, depth <= rings.count else { return [] }
        return rings[depth - 1].map { segments[$0] }
    }

    // MARK: Hit testing

    /// Hit-test a point given relative to the chart center, y axis pointing UP
    /// (AppKit default, non-flipped). Pass `yUp: false` for flipped coordinates.
    public func hitTest(_ p: Point2D, yUp: Bool = true) -> SunburstHit {
        let y = yUp ? p.y : -p.y
        let r = (p.x * p.x + y * y).squareRoot()
        if r < config.centerRadius { return .center }
        var depth = 0
        if let specs = config.rings {
            for (i, spec) in specs.enumerated() where r >= spec.inner && r <= spec.outer + 0.5 {
                depth = i + 1; break
            }
            if depth == 0 { return .none }
        } else {
            depth = Int(((r - config.centerRadius) / config.ringWidth).rounded(.down)) + 1
        }
        guard depth >= 1, depth <= rings.count else { return .none }
        let a = Self.layoutAngle(x: p.x, y: y)
        let ring = rings[depth - 1]
        // Binary search for the last segment with start <= a.
        var lo = 0, hi = ring.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if segments[ring[mid]].startAngle <= a { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard found >= 0 else { return .none }
        let s = segments[ring[found]]
        return a < s.endAngle ? .segment(s.index) : .none
    }

    /// Converts a y-up point to a layout angle (clockwise from 12 o'clock) in [0, 2π).
    public static func layoutAngle(x: Double, y: Double) -> Double {
        // atan2(x, y) is the clockwise angle from +y.
        var a = atan2(x, y)
        if a < 0 { a += fullTurn }
        if a >= fullTurn { a -= fullTurn }
        return a
    }

    /// Converts a layout angle + radius back to a y-up point.
    public static func point(angle: Double, radius: Double) -> Point2D {
        Point2D(x: radius * sin(angle), y: radius * cos(angle))
    }

    // MARK: Drawing helpers

    /// Polygon outline (y-up, relative to center) approximating the annular
    /// sector: outer arc start→end, then inner arc end→start. Suitable for CGPath.
    public func outline(of segment: SunburstSegment<Node>, pointsPerRadian: Double = 40) -> [Point2D] {
        let pad = min(config.padAngle, segment.span * 0.25)
        let a0 = segment.startAngle + pad, a1 = segment.endAngle - pad
        let steps = max(2, Int((a1 - a0) * pointsPerRadian) + 1)
        var pts: [Point2D] = []
        pts.reserveCapacity(steps * 2 + 2)
        for i in 0...steps {
            pts.append(Self.point(angle: a0 + (a1 - a0) * Double(i) / Double(steps), radius: segment.outerRadius))
        }
        for i in stride(from: steps, through: 0, by: -1) {
            pts.append(Self.point(angle: a0 + (a1 - a0) * Double(i) / Double(steps), radius: segment.innerRadius))
        }
        return pts
    }

    /// Point in the middle of a segment, for labels/tooltips.
    public func anchor(of segment: SunburstSegment<Node>) -> Point2D {
        Self.point(angle: segment.midAngle, radius: (segment.innerRadius + segment.outerRadius) / 2)
    }

}

extension SunburstLayout where Node: SunburstNode {
    // MARK: Layout

    public init(root: Node, config: SunburstConfig = SunburstConfig()) {
        self.init(root: root, config: config, nameOf: { _ in "" }, pathOf: { _ in "" },
                  isDirectory: { _ in true }, isRestricted: { _ in false })
    }
}

extension SunburstLayout where Node: SunburstNamed {
    public init(root: Node, config: SunburstConfig = SunburstConfig()) {
        self.init(root: root, config: config,
                  nameOf: { $0.sunburstName }, pathOf: { $0.sunburstPath },
                  isDirectory: { $0.sunburstIsDirectory }, isRestricted: { $0.sunburstIsRestricted })
    }
}

extension SunburstLayout where Node: SunburstNode {
    /// Core layout. `nameOf` / path helpers enable path compression and richer “其他” labels;
    /// pass empty nameOf for legacy behaviour (displayNames become "").
    public init(root: Node, config: SunburstConfig,
                nameOf: (Node) -> String,
                pathOf: (Node) -> String,
                isDirectory: (Node) -> Bool,
                isRestricted: (Node) -> Bool) {
        typealias N = Node
        self.config = config
        let total = max(0, root.sunburstSize)
        self.rootSize = total
        var segs: [SunburstSegment<N>] = []
        var names: [String] = []
        let depthLimit = config.depthCount
        var rings: [[Int]] = Array(repeating: [], count: max(0, depthLimit))

        typealias Pending = (node: N, start: Double, span: Double, depth: Int, parent: Int?, rootSlice: Int?, label: String)
        let rootLabel = nameOf(root)
        _ = pathOf // reserved for future path-based merge hints
        var queue: [Pending] = [(node: root, start: 0, span: Self.fullTurn, depth: 0, parent: nil, rootSlice: nil, label: rootLabel)]
        var qi = 0

        func compress(_ node: N) -> (N, String) {
            var n = node
            var parts = [nameOf(n)]
            guard config.pathCompressRatio < 1 else { return (n, parts[0]) }
            while true {
                let kids = n.sunburstChildren.filter { $0.sunburstSize > 0 }
                guard let big = kids.max(by: { $0.sunburstSize < $1.sunburstSize }) else { break }
                let parentSize = max(n.sunburstSize, 1)
                guard big.sunburstSize / parentSize >= config.pathCompressRatio,
                      isDirectory(big), !big.sunburstChildren.isEmpty else { break }
                parts.append(nameOf(big))
                n = big
            }
            return (n, parts.joined(separator: " › "))
        }

        while qi < queue.count {
            let item = queue[qi]; qi += 1
            let childDepth = item.depth + 1
            guard childDepth <= depthLimit else { continue }
            let parentSize = item.node.sunburstSize
            guard parentSize > 0 else { continue }
            // Segment cap reached: stop expanding (no partial child sets, no extra “其他”).
            guard segs.count + 1 < config.maxSegments else { continue }
            let (inner, outer) = config.radii(forDepth: childDepth)
            let midR = (inner + outer) / 2
            let children = item.node.sunburstChildren
            // Largest-first for maxKids ranking. The scanner already sorts children by
            // actual size, so only sort when the order is off (e.g. logical metric).
            var presorted = true
            var prev = Double.infinity
            for c in children { let v = c.sunburstSize; if v > prev { presorted = false; break }; prev = v }
            let ordered = presorted ? children : children.sorted { $0.sunburstSize > $1.sunburstSize }

            var shown: [(node: N, size: Double)] = []
            var otherCount = 0, otherSize = 0.0

            for (rank, child) in ordered.enumerated() {
                let size = max(0, child.sunburstSize)
                let restricted = isRestricted(child)
                let span = item.span * min(1, size / parentSize)
                let arcLen = span * midR
                let tooSmallAngle = span < config.minSliceAngle
                let tooSmallArc = config.minArcPoints > 0 && arcLen < config.minArcPoints
                let tooLate = rank >= config.maxKidsPerParent
                    || segs.count + shown.count + 1 >= config.maxSegments
                let zero = size <= 0
                if zero || restricted || tooSmallAngle || tooSmallArc || tooLate {
                    if size > 0 || restricted {
                        otherCount += 1
                        otherSize += size
                    }
                    continue
                }
                shown.append((child, size))
            }

            var cursor = item.start
            func emit(_ content: SegmentContent<N>, size: Double, start: Double, span: Double, label: String) -> Int {
                let idx = segs.count
                let end = min(start + span, Self.fullTurn)
                segs.append(SunburstSegment(index: idx, depth: childDepth, startAngle: start, endAngle: end,
                                            innerRadius: inner, outerRadius: outer, parentIndex: item.parent,
                                            rootSliceIndex: item.rootSlice ?? idx, size: size, content: content))
                names.append(label)
                rings[childDepth - 1].append(idx)
                return idx
            }

            for slot in shown {
                let child = slot.node
                let span = item.span * min(1, slot.size / parentSize)
                let (comp, label) = compress(child)
                let idx = emit(.node(comp), size: slot.size, start: cursor, span: span, label: label)
                queue.append((node: comp, start: cursor, span: span, depth: childDepth,
                               parent: idx, rootSlice: item.rootSlice ?? idx, label: label))
                cursor += span
            }

            if otherCount > 0 {
                let otherSpan = item.span * min(1, otherSize / parentSize)
                // If size-based span is 0 but we had restricted empty nodes, skip.
                let arcLen = otherSpan * midR
                let angleOK = otherSpan >= config.minOtherAngle
                // Spec: “其他” itself < 3pt → don't draw.
                let drawOther = angleOK && (config.minArcPoints <= 0 || arcLen >= 3 * max(config.scale, 0.35))
                if drawOther && otherSpan > 0 && segs.count < config.maxSegments {
                    let label = "OTHER:\(otherCount)"  // localized in the view
                    _ = emit(.other(count: otherCount, size: otherSize), size: otherSize,
                             start: cursor, span: otherSpan, label: label)
                }
            }
        }
        for i in rings.indices { rings[i].sort { segs[$0].startAngle < segs[$1].startAngle } }
        while let last = rings.last, last.isEmpty { rings.removeLast() }
        self.segments = segs
        self.displayNames = names
        self.rings = rings
    }
}

/// Optional naming / flags for richer layout (path compression, merge of unreadable items).
public protocol SunburstNamed: SunburstNode {
    var sunburstName: String { get }
    var sunburstPath: String { get }
    var sunburstIsDirectory: Bool { get }
    /// Unreadable / no-permission — merged into “其他”.
    var sunburstIsRestricted: Bool { get }
}

extension SunburstNamed {
    public var sunburstIsRestricted: Bool { false }
}
