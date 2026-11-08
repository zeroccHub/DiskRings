import Foundation

/// Chip / confirm-dialog risk classification for items in the deletion basket.
/// Independent of `DeletionGuard` (which decides whether an item may be deleted
/// at all). This only decides whether a chip shows ⚠.
///
/// Rules (layout redesign §4.6 + Batch 1 decisions):
/// - Path under `~/Library` or `/Library` → high-risk, **except** `…/Library/Caches`
///   (and its descendants), which are markable as cleanable and NOT high-risk.
/// - Hidden name (last path component starts with `.`) → high-risk.
/// - Application bundle (`.app` path component, case-insensitive) → high-risk.
/// - Single item larger than 50 GB (actual on-disk bytes) → high-risk (⚠).
public enum BasketRisk {
    public static let largeItemThreshold: UInt64 = 50 * 1024 * 1024 * 1024

    public struct Verdict: Equatable, Sendable {
        public var isHighRisk: Bool
        /// Why the item is flagged (empty when not high-risk). Stable codes for tests / UI.
        public var reasons: [String]
        public init(isHighRisk: Bool, reasons: [String] = []) {
            self.isHighRisk = isHighRisk
            self.reasons = reasons
        }
    }

    /// Classifies a filesystem path. `homeDirectory` is the user's home (e.g. `/Users/tester`);
    /// pass `""` to skip the `~/Library` check. `sizeBytes` is the item's contributed actual size.
    public static func classify(path: String, sizeBytes: UInt64, homeDirectory: String) -> Verdict {
        var reasons: [String] = []
        let comps = path.split(separator: "/").map(String.init)
        let name = comps.last ?? ""

        if name.hasPrefix(".") { reasons.append("hidden") }
        if comps.contains(where: { $0.lowercased().hasSuffix(".app") }) { reasons.append("appBundle") }

        // `…/Library/Caches` is cleanable, not high-risk — no library reason there.
        if libraryState(path: path, homeDirectory: homeDirectory) == .library { reasons.append("library") }

        if sizeBytes > largeItemThreshold { reasons.append("over50GB") }

        return Verdict(isHighRisk: !reasons.isEmpty, reasons: reasons)
    }

    public static func classify(_ node: FileNode, homeDirectory: String) -> Verdict {
        classify(path: node.path, sizeBytes: node.contributedSize(.actual), homeDirectory: homeDirectory)
    }

    // MARK: - path helpers

    /// Where a path sits relative to the Library rule.
    public enum LibraryState: UInt8, Sendable { case none, library, caches }

    public static func libraryState(path: String, homeDirectory home: String) -> LibraryState {
        guard isLibraryPath(path, home: home) else { return .none }
        return isLibraryCaches(path, home: home) ? .caches : .library
    }


    private static func isLibraryPath(_ path: String, home: String) -> Bool {
        let p = normalize(path)
        if p == "/Library" || p.hasPrefix("/Library/") { return true }
        guard !home.isEmpty else { return false }
        let lib = normalize(home) + "/Library"
        return p == lib || p.hasPrefix(lib + "/")
    }

    /// `…/Library/Caches` and anything under it.
    private static func isLibraryCaches(_ path: String, home: String) -> Bool {
        let p = normalize(path)
        let candidates: [String] = {
            var c = ["/Library/Caches"]
            if !home.isEmpty { c.append(normalize(home) + "/Library/Caches") }
            return c
        }()
        for base in candidates {
            if p == base || p.hasPrefix(base + "/") { return true }
        }
        return false
    }

    private static func normalize(_ path: String) -> String {
        if path.count > 1 && path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }
}

/// Snapshot of the deletion basket for the danger-zone UI (chips + summary).
/// Wraps `DeletionList` data without changing delete behaviour.
public struct BasketSnapshot: Equatable, Sendable {
    public struct Chip: Equatable, Sendable {
        public var name: String
        public var path: String
        public var bytes: UInt64
        public var isHighRisk: Bool
        public var riskReasons: [String]
    }

    public var chips: [Chip]
    public var totalBytes: UInt64
    public var highRiskCount: Int

    public var isEmpty: Bool { chips.isEmpty }
    public var count: Int { chips.count }

    public init(chips: [Chip] = [], totalBytes: UInt64 = 0, highRiskCount: Int = 0) {
        self.chips = chips
        self.totalBytes = totalBytes
        self.highRiskCount = highRiskCount
    }

    public static func from(nodes: [FileNode], homeDirectory: String) -> BasketSnapshot {
        var chips: [Chip] = []
        var total: UInt64 = 0
        var high = 0
        for n in nodes {
            let v = BasketRisk.classify(n, homeDirectory: homeDirectory)
            let bytes = n.contributedSize(.actual)
            total &+= bytes
            if v.isHighRisk { high += 1 }
            chips.append(Chip(name: n.name, path: n.path, bytes: bytes,
                              isHighRisk: v.isHighRisk, riskReasons: v.reasons))
        }
        return BasketSnapshot(chips: chips, totalBytes: total, highRiskCount: high)
    }
}
