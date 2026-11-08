import Foundation

/// Thread-safe set of (device, inode) pairs for files with link count > 1.
/// The first scanned instance of a pair "owns" the bytes; later instances are
/// recorded as duplicates. With concurrent traversal, which path counts as
/// "first" is scheduling-dependent, but the total is always counted once.
public final class HardLinkRegistry: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public let device: UInt64
        public let inode: UInt64
    }

    private let lock = NSLock()
    private var seen: Set<Key> = []
    private var duplicates = 0

    public init() {}

    /// Returns true if this is the first time the pair is seen.
    public func registerFirstSighting(device: UInt64, inode: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let inserted = seen.insert(Key(device: device, inode: inode)).inserted
        if !inserted { duplicates += 1 }
        return inserted
    }

    public var uniqueCount: Int { lock.lock(); defer { lock.unlock() }; return seen.count }
    public var duplicateCount: Int { lock.lock(); defer { lock.unlock() }; return duplicates }
}

/// Collects APFS clone-family members during the (concurrent) scan and
/// resolves them deterministically afterwards. Per (device, clone id) family
/// the member with the lowest inode (then path) is the "primary" and is
/// charged its full allocated size. Other members are charged only their
/// private bytes, but only when their ext flags say they may share blocks AND
/// their private size is known; otherwise they are charged in full
/// (conservative). Hard-link duplicates never reach this registry, so links
/// and clones are not double-subtracted. Results are estimates (see README).
public final class CloneRegistry: @unchecked Sendable {
    struct Member {
        let node: FileNode
        let fileID: UInt64
        let privateSize: UInt64?
        let eligible: Bool
    }
    private let lock = NSLock()
    private var families: [HardLinkRegistry.Key: [Member]] = [:]
    private var duplicates = 0
    private var savedBytes: UInt64 = 0

    public init() {}

    /// Records a clone-family member (thread-safe). No size decision yet.
    func add(node: FileNode, device: UInt64, cloneID: UInt64, fileID: UInt64, privateSize: UInt64?, eligible: Bool) {
        let m = Member(node: node, fileID: fileID, privateSize: privateSize, eligible: eligible)
        lock.lock(); families[HardLinkRegistry.Key(device: device, inode: cloneID), default: []].append(m); lock.unlock()
    }

    /// Applies the deterministic primary choice. Call once, after all workers
    /// finished and before aggregation.
    func resolve() {
        lock.lock(); defer { lock.unlock() }
        for (_, members) in families where members.count > 1 {
            let sorted = members.sorted { a, b in
                a.fileID != b.fileID ? a.fileID < b.fileID : a.node.path < b.node.path
            }
            for m in sorted.dropFirst() where m.eligible {
                guard let priv = m.privateSize else { continue }
                m.node.markCloneDuplicate(privateBytes: priv)
                duplicates += 1
                savedBytes &+= m.node.allocatedSize - m.node.actualSize
            }
        }
    }

    public var duplicateCount: Int { lock.lock(); defer { lock.unlock() }; return duplicates }
    /// Allocated bytes not charged because they are shared with an earlier clone.
    public var sharedBytes: UInt64 { lock.lock(); defer { lock.unlock() }; return savedBytes }
}
