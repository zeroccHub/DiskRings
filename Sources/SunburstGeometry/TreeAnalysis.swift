import Foundation
#if !SINGLE_MODULE
import DiskScanCore
#endif

/// Which size the sunburst rings use (View › Size Rings by Logical Size).
public enum SunburstSizing {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var value: SizeMetric = .actual
    }
    private static let box = Box()

    public static var metric: SizeMetric {
        get { box.lock.lock(); defer { box.lock.unlock() }; return box.value }
        set { box.lock.lock(); box.value = newValue; box.lock.unlock() }
    }
}

/// Bridges the scan tree into the pure geometry layout.
extension FileNode: SunburstNode, SunburstNamed {
    public var sunburstSize: Double { Double(contributedSize(SunburstSizing.metric)) }
    public var sunburstChildren: [FileNode] { children }
    public var sunburstName: String {
        let last = (name as NSString).lastPathComponent
        return last.isEmpty ? name : last
    }
    public var sunburstPath: String { path }
    public var sunburstIsDirectory: Bool { isDirectory }
    public var sunburstIsRestricted: Bool { isRestricted || isOtherFilesystem }
}

/// One background, iterative O(n) pass over the scanned tree that precomputes
/// what the results UI needs per directory, so the main thread never walks a
/// subtree or builds `FileNode.path` while drawing:
/// - the `BasketRisk` high-risk verdict (identical rules, see TreeAnalysisTests),
///   from inherited bits (under a `.app`, Library state) — O(1) for files via the parent;
/// - the number of hidden items (zero-size or unreadable) in each subtree.
/// Stores entries for directories only. Rebuild after deletions.
public final class TreeAnalysis: @unchecked Sendable {
    public struct Entry: Sendable {
        /// bit0 high-risk, bit1 path contains a `.app` component, bits 2-3 LibraryState.
        var flags: UInt8
        public var hiddenCount: UInt32
        public var isHighRisk: Bool { flags & 1 != 0 }
        var underApp: Bool { flags & 2 != 0 }
        var library: BasketRisk.LibraryState { BasketRisk.LibraryState(rawValue: (flags >> 2) & 3) ?? .none }
    }
    public let homeDirectory: String
    public private(set) var visited = 0
    /// Display-only protection flags (P1-3/P1-4), computed in this background pass.
    public private(set) var protection = ProtectionMap()
    private var entries: [ObjectIdentifier: Entry] = [:]

    init(homeDirectory: String) { self.homeDirectory = homeDirectory }

    static func isAppName(_ n: String) -> Bool {
        n.count >= 4 && n.utf8.suffix(4).map { $0 | 0x20 } == Array(".app".utf8)
    }
    /// Hidden from chart + outline: zero bytes, unreadable, or another filesystem.
    static func isHidden(_ n: FileNode) -> Bool { n.contributedSize(.actual) == 0 || n.isRestricted || n.isOtherFilesystem }

    /// Returns nil when `isCancelled()` turns true (checked every 4096 nodes).
    /// `protectionGuard`: a pure snapshot guard (`ProtectionMap.snapshotGuard()`); nil = no
    /// protection flags (tests that don't care).
    public static func build(root: FileNode, homeDirectory: String, protectionGuard: DeletionGuard? = nil,
                             isCancelled: () -> Bool = { false }) -> TreeAnalysis? {
        let a = TreeAnalysis(homeDirectory: homeDirectory)
        if let g = protectionGuard {
            guard let m = ProtectionMap.build(root: root, guard: g, isCancelled: isCancelled) else { return nil }
            a.protection = m
        }
        let home = homeDirectory.count > 1 && homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        let libRoots: Set<String> = home.isEmpty ? ["/Library"] : ["/Library", home + "/Library"]
        let cacheRoots: Set<String> = Set(libRoots.map { $0 + "/Caches" })
        struct Frame {
            let node: FileNode
            let flags: UInt8          // underApp + library bits (inherited part)
            let path: String?         // exact path while short enough to matter
            var idx = 0
            var hidden: UInt32 = 0
        }
        func selfFlags(_ n: FileNode, inherited: UInt8, path: String?, libState: BasketRisk.LibraryState) -> UInt8 {
            var f = inherited & 2
            if isAppName(n.name) { f |= 2 }
            f |= libState.rawValue << 2
            let high = n.name.hasPrefix(".") || f & 2 != 0 || libState == .library
                || n.contributedSize(.actual) > BasketRisk.largeItemThreshold
            return f | (high ? 1 : 0)
        }
        func childState(_ parentFlags: UInt8, childPath: String?) -> BasketRisk.LibraryState {
            let ps = BasketRisk.LibraryState(rawValue: (parentFlags >> 2) & 3) ?? .none
            guard let p = childPath else { return ps }
            if ps == .none, libRoots.contains(p) { return .library }
            if ps == .library, cacheRoots.contains(p) { return .caches }
            return ps
        }
        let limit = max(home.count, 16) + 24
        let rootPath = root.path
        let rootFlags = selfFlags(root, inherited: rootPath.split(separator: "/").contains { isAppName(String($0)) } ? 2 : 0,
                                  path: rootPath, libState: BasketRisk.libraryState(path: rootPath, homeDirectory: home))
        var stack = [Frame(node: root, flags: rootFlags, path: rootPath.count <= limit ? rootPath : nil)]
        var counter = 0
        while !stack.isEmpty {
            let top = stack.count - 1
            let node = stack[top].node
            let i = stack[top].idx
            if i < node.children.count {
                stack[top].idx = i + 1
                let child = node.children[i]
                counter += 1
                if counter & 4095 == 0, isCancelled() { return nil }
                if child.isDirectory {
                    var cp: String? = nil
                    if let pp = stack[top].path {
                        let joined = pp.hasSuffix("/") ? pp + child.name : pp + "/" + child.name
                        if joined.count <= limit { cp = joined }
                    }
                    let st = childState(stack[top].flags, childPath: cp)
                    let f = selfFlags(child, inherited: stack[top].flags, path: cp, libState: st)
                    if child.children.isEmpty {
                        let h: UInt32 = isHidden(child) ? 1 : 0
                        a.entries[ObjectIdentifier(child)] = Entry(flags: f, hiddenCount: 0)
                        stack[top].hidden &+= h
                    } else {
                        stack.append(Frame(node: child, flags: f, path: cp))
                        if isHidden(child) { stack[stack.count - 1].hidden = 1 }
                    }
                } else if isHidden(child) {
                    stack[top].hidden &+= 1
                }
            } else {
                let fr = stack.removeLast()
                // The node's own hidden bit was pre-seeded into its frame; report
                // descendants only for itself, and include it for the parent.
                let selfHidden: UInt32 = (fr.node !== root && isHidden(fr.node)) ? 1 : 0
                a.entries[ObjectIdentifier(fr.node)] = Entry(flags: fr.flags, hiddenCount: fr.hidden &- selfHidden)
                if let p = stack.indices.last { stack[p].hidden &+= fr.hidden }
            }
        }
        a.visited = counter + 1
        return a
    }

    public func protectionKind(_ n: FileNode) -> ProtectionKind { protection.kind(n) }

    public func entry(_ n: FileNode) -> Entry? { entries[ObjectIdentifier(n)] }

    /// Same verdict as `BasketRisk.classify(n, homeDirectory:).isHighRisk`, O(1).
    public func isHighRisk(_ n: FileNode) -> Bool {
        if let e = entry(n) { return e.isHighRisk }
        if n.name.hasPrefix(".") || Self.isAppName(n.name) || n.contributedSize(.actual) > BasketRisk.largeItemThreshold { return true }
        if let p = n.parent, let pe = entry(p) { return pe.underApp || pe.library == .library }
        return BasketRisk.classify(n, homeDirectory: homeDirectory).isHighRisk
    }

    /// Zero-size or unreadable items below `n` (not counting `n`).
    public func hiddenCount(_ n: FileNode) -> Int { Int(entry(n)?.hiddenCount ?? 0) }
}
