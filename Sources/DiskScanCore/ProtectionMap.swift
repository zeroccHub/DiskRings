import Foundation

/// How a `DeletionGuard.Reason` should be SHOWN (it never changes what may be deleted):
/// - `.subtree`: SIP / system locations — the item and everything below it are
///   protected (chart: grey hatch + lock, inherited by descendants; 「系统保护」).
/// - `.selfOnly`: the folder itself can't be deleted (home, volume roots, folders that
///   contain home / a volume / a system location, essential folders) but its contents
///   can — normal colours in the chart, 「🔒 受保护」 only on its own list row.
public enum ProtectionKind: UInt8, Sendable, Equatable {
    case none = 0, selfOnly = 1, subtree = 2
}

extension DeletionGuard.Reason {
    public var protectionKind: ProtectionKind {
        switch self {
        case .systemLocation, .sipProtected, .containsRestricted: return .subtree
        default: return .selfOnly
        }
    }
}

/// Display-only protection flags for a scanned tree, computed ONCE in the background
/// analysis pass (P1-3/P1-4): the mount list and the canonical home are read once per
/// analysis; only the few nodes on the path to a rule key (protected prefixes,
/// essential folders, mounts, home, allowed exceptions) are evaluated, with the
/// existing pure `DeletionGuard.evaluate` rules. Chart rebuilds and the outline only
/// read this map — no realpath / getfsstat / lstat on the main thread.
/// The live `DeletionGuard` check before adding to the delete zone and before deleting
/// is unchanged and remains authoritative.
public struct ProtectionMap: @unchecked Sendable {
    /// Explicit verdicts. `.none` entries are overrides below a `.subtree` ancestor
    /// (e.g. `/usr/local` under `/usr`); `.selfOnly` does not affect descendants.
    private var explicit: [ObjectIdentifier: ProtectionKind] = [:]
    public private(set) var evaluated = 0

    public init() {}

    /// O(depth) lookup: own verdict, else the nearest inheriting ancestor verdict.
    public func kind(_ n: FileNode) -> ProtectionKind {
        if let k = explicit[ObjectIdentifier(n)] { return k }
        var p = n.parent
        while let x = p {
            if let k = explicit[ObjectIdentifier(x)], k != .selfOnly { return k }
            p = x.parent
        }
        return .none
    }

    /// A guard snapshot for display classification: home canonicalized and mounts
    /// listed once (call this off the main thread); item flags via lstat only for
    /// the handful of evaluated nodes; no subtree walks, no identity lookups.
    public static func snapshotGuard(homeDirectory: String = NSHomeDirectory()) -> DeletionGuard {
        let mounts = DeletionGuard.liveMountPoints()
        return DeletionGuard(homeDirectory: DeletionGuard.realDirectory(homeDirectory),
                             mountPoints: { mounts },
                             fileFlags: DeletionGuard.liveFileFlags)
    }

    /// Returns nil when cancelled.
    public static func build(root: FileNode, guard g: DeletionGuard,
                             isCancelled: () -> Bool = { false }) -> ProtectionMap? {
        func canon(_ p: String) -> String {
            DeletionGuard.key(DeletionGuard.mapFirmlinks(DeletionGuard.applyAliases(DeletionGuard.normalize(p))))
        }
        var keys = Set<String>()
        for p in g.protectedPrefixes + g.essentialFolders + g.allowedExceptions + [DeletionGuard.dataVolumePrefix] { keys.insert(canon(p)) }
        for m in g.mountPoints() { keys.insert(canon(m)) }
        keys.insert(canon(g.homeDirectory))
        let exceptionKeys = g.allowedExceptions.map(canon)
        let keyList = Array(keys)
        func leadsToKey(_ ck: String) -> Bool { keyList.contains { DeletionGuard.isStrictAncestor(ck, of: $0) } }

        var map = ProtectionMap()
        var stack: [(FileNode, String)] = [(root, root.path)]
        while let (node, path) = stack.popLast() {
            if isCancelled() { return nil }
            map.evaluated += 1
            let ck = canon(path)
            let kind = g.check(path)?.protectionKind ?? .none
            let underSubtree = map.kind(node) == .subtree && map.explicit[ObjectIdentifier(node)] == nil
            if kind != .none || underSubtree { map.explicit[ObjectIdentifier(node)] = kind }
            // Descend only toward rule keys; below a .subtree verdict only toward an exception.
            let descend = kind == .subtree
                ? exceptionKeys.contains { DeletionGuard.isStrictAncestor(ck, of: $0) }
                : leadsToKey(ck)
            guard descend, node.isDirectory else { continue }
            for c in node.children where c.isDirectory {
                stack.append((c, path.hasSuffix("/") ? path + c.name : path + "/" + c.name))
            }
        }
        return map
    }
}
