import Foundation

/// What kind of filesystem object a node represents.
public enum NodeKind: UInt8, Sendable, Equatable {
    case file
    case directory
    case symlink
    case other      // sockets, fifos, devices, ...
}

/// A node in the scanned tree.
///
/// Threading model: while a scan is running, a directory node's `children`
/// array is written exactly once, by the worker that enumerates that
/// directory, *before* any of its sub-directories are queued. After the scan
/// finishes (`ScanEngine` returns), the tree is handed to the caller and must
/// only be mutated from one thread at a time (in the app: the main thread).
public final class FileNode: @unchecked Sendable {
    public let name: String
    public let kind: NodeKind
    public weak private(set) var parent: FileNode?
    public internal(set) var children: [FileNode] = []

    /// Device id and file id (inode) as reported by the filesystem.
    public let device: UInt64
    public let fileID: UInt64
    public let linkCount: UInt32

    /// For files: own sizes. For directories: aggregated sizes of the subtree
    /// (filled in by `aggregate()` after the scan).
    public internal(set) var logicalSize: UInt64
    public internal(set) var allocatedSize: UInt64
    /// Actual on-disk usage after APFS clone dedup: equals `allocatedSize`
    /// unless this file is a later member of a clone family, in which case it
    /// is only the file's private (unshared) bytes. Aggregated for directories.
    public internal(set) var actualSize: UInt64
    /// APFS clone family id, if known.
    public internal(set) var cloneID: UInt64?
    /// Number of non-directory items in the subtree (1 for a file).
    public internal(set) var itemCount: UInt64

    /// This file is an additional hard link to a (dev, inode) already counted
    /// elsewhere in the tree; it contributes 0 bytes to its ancestors.
    public internal(set) var isHardLinkDuplicate = false
    /// This file shares blocks with a clone family member counted elsewhere;
    /// `actualSize` holds only its private bytes.
    public internal(set) var isCloneDuplicate = false
    /// Directory could not be read (permissions, TCC, I/O error).
    public internal(set) var isRestricted = false
    /// Directory is a mount point of another filesystem and was not entered.
    public internal(set) var isOtherFilesystem = false
    /// Node was removed from disk via a deleter.
    public internal(set) var isDeleted = false

    public init(name: String, kind: NodeKind, device: UInt64 = 0, fileID: UInt64 = 0,
                linkCount: UInt32 = 1, logicalSize: UInt64 = 0, allocatedSize: UInt64 = 0,
                actualSize: UInt64? = nil, cloneID: UInt64? = nil) {
        self.name = name
        self.kind = kind
        self.device = device
        self.fileID = fileID
        self.linkCount = linkCount
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.actualSize = actualSize ?? allocatedSize
        self.cloneID = cloneID
        self.itemCount = kind == .directory ? 0 : 1
    }

    public var isDirectory: Bool { kind == .directory }

    /// Size this node contributes to its parent for the chosen metric.
    public func contributedSize(_ metric: SizeMetric) -> UInt64 {
        if isHardLinkDuplicate { return 0 }
        return size(metric)
    }

    public func size(_ metric: SizeMetric) -> UInt64 {
        switch metric {
        case .allocated: return allocatedSize
        case .logical: return logicalSize
        case .actual: return actualSize
        }
    }

    /// Full path, built by walking parent links. The root node's name is
    /// expected to be the absolute path it was scanned from.
    public var path: String {
        var parts: [String] = []
        var cur: FileNode? = self
        while let n = cur {
            parts.append(n.name)
            cur = n.parent
        }
        parts.reverse()
        guard var result = parts.first else { return "" }
        for p in parts.dropFirst() {
            if !result.hasSuffix("/") { result += "/" }
            result += p
        }
        return result
    }

    public var depth: Int {
        var d = 0
        var cur = parent
        while let c = cur { d += 1; cur = c.parent }
        return d
    }

    public func isAncestor(of other: FileNode) -> Bool {
        var cur = other.parent
        while let c = cur {
            if c === self { return true }
            cur = c.parent
        }
        return false
    }

    // MARK: - Tree building (internal)

    func setChildren(_ nodes: [FileNode]) {
        for n in nodes { n.parent = self }
        children = nodes
    }

    func markRestricted() { isRestricted = true }
    func markOtherFilesystem() { isOtherFilesystem = true }
    func markHardLinkDuplicate() { isHardLinkDuplicate = true }
    func markCloneDuplicate(privateBytes: UInt64) {
        isCloneDuplicate = true
        actualSize = min(allocatedSize, privateBytes)
    }

    /// Recompute directory sizes bottom-up (iterative post-order, safe for very
    /// deep trees) and sort each directory's children by actual size, largest first.
    public func aggregate() {
        var stack: [(FileNode, Bool)] = [(self, false)]
        while let (node, visited) = stack.popLast() {
            guard node.kind == .directory else { continue }
            if visited {
                var l: UInt64 = 0, a: UInt64 = 0, u: UInt64 = 0, c: UInt64 = 0
                for ch in node.children {
                    l &+= ch.contributedSize(.logical)
                    a &+= ch.contributedSize(.allocated)
                    u &+= ch.contributedSize(.actual)
                    c &+= ch.isHardLinkDuplicate ? 0 : ch.itemCount
                }
                node.logicalSize = l
                node.allocatedSize = a
                node.actualSize = u
                node.itemCount = c
                node.children.sort { lhs, rhs in
                    let ls = lhs.contributedSize(.actual), rs = rhs.contributedSize(.actual)
                    return ls != rs ? ls > rs : lhs.name < rhs.name
                }
            } else {
                stack.append((node, true))
                for ch in node.children where ch.kind == .directory {
                    stack.append((ch, false))
                }
            }
        }
    }

    /// Detach this node from its parent (after it was deleted from disk) and
    /// subtract its contribution from every ancestor.
    @discardableResult
    public func removeFromTree() -> Bool {
        guard let p = parent, let idx = p.children.firstIndex(where: { $0 === self }) else { return false }
        let dl = contributedSize(.logical)
        let da = contributedSize(.allocated)
        let du = contributedSize(.actual)
        let dc = isHardLinkDuplicate ? 0 : itemCount
        p.children.remove(at: idx)
        parent = nil
        isDeleted = true
        var cur: FileNode? = p
        while let c = cur {
            c.logicalSize = c.logicalSize >= dl ? c.logicalSize - dl : 0
            c.allocatedSize = c.allocatedSize >= da ? c.allocatedSize - da : 0
            c.actualSize = c.actualSize >= du ? c.actualSize - du : 0
            c.itemCount = c.itemCount >= dc ? c.itemCount - dc : 0
            cur = c.parent
        }
        return true
    }

    /// Find a descendant by path components relative to this node.
    public func descendant(atRelativePath components: [String]) -> FileNode? {
        var cur: FileNode = self
        for comp in components {
            guard let next = cur.children.first(where: { $0.name == comp }) else { return nil }
            cur = next
        }
        return cur
    }
}

public enum SizeMetric: Sendable {
    /// Bytes actually allocated on disk (default; what deleting would free).
    case allocated
    /// Logical file length.
    case logical
    /// On-disk usage with APFS clones counted once (default for display and
    /// deletion estimates). Equals `.allocated` on volumes without clone info.
    case actual
}
