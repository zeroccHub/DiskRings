import Foundation

/// Coalesces high-rate progress values into at most one pending main-thread hop.
/// `offer` is O(1) and returns true only when the caller must schedule a hop;
/// the hop calls `take()` and gets the newest value.
public final class ProgressCoalescer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: T?
    private var pending = false
    public private(set) var offered = 0
    public private(set) var scheduled = 0
    public init() {}
    public func offer(_ v: T) -> Bool {
        lock.lock(); defer { lock.unlock() }
        offered += 1
        latest = v
        if pending { return false }
        pending = true
        scheduled += 1
        return true
    }
    public func take() -> T? {
        lock.lock(); defer { lock.unlock() }
        pending = false
        let v = latest; latest = nil
        return v
    }
}

/// In-memory synthetic trees for benchmarks/tests (never touches disk).
public enum SyntheticTree {
    /// Builds a tree with roughly `targetNodes` nodes: directories with `dirFanout`
    /// sub-directories and `filesPerDir` files each, breadth-first, then aggregates.
    /// Names include cache-like folders and varied extensions so the heuristics work.
    public static func build(rootPath: String = "/System/Volumes/Data", targetNodes: Int,
                             dirFanout: Int = 6, filesPerDir: Int = 9) -> FileNode {
        let root = FileNode(name: rootPath, kind: .directory)
        var count = 1
        var queue: [FileNode] = [root]
        var qi = 0
        let dirNames = ["Library", "Caches", "Users", "Documents", "node_modules", "Photos", "src", "Cache_Data", "tmp", "Music"]
        let exts = ["jpg", "mp3", "pdf", "zip", "swift", "dat", "mov", "txt", "js", "bin"]
        var serial: UInt64 = 1
        while qi < queue.count, count < targetNodes {
            let dir = queue[qi]; qi += 1
            var kids: [FileNode] = []
            kids.reserveCapacity(dirFanout + filesPerDir)
            for f in 0..<filesPerDir where count < targetNodes {
                serial &+= 1
                let size = UInt64(1024 + (serial &* 2654435761) % 4_000_000)
                kids.append(FileNode(name: "f\(f).\(exts[Int(serial % UInt64(exts.count))])", kind: .file,
                                     fileID: serial, logicalSize: size, allocatedSize: size))
                count += 1
            }
            for d in 0..<dirFanout where count < targetNodes {
                serial &+= 1
                let n = FileNode(name: dirNames[Int(serial % UInt64(dirNames.count))] + "\(d)", kind: .directory, fileID: serial)
                kids.append(n); queue.append(n)
                count += 1
            }
            dir.setChildren(kids)
        }
        root.aggregate()
        return root
    }

    /// Small hand-built trees for tests: a directory when `kids` is non-nil.
    public static func node(_ name: String, size: UInt64 = 0, _ kids: [FileNode]? = nil) -> FileNode {
        guard let kids else {
            return FileNode(name: name, kind: .file, fileID: nextID(), logicalSize: size, allocatedSize: size)
        }
        let d = FileNode(name: name, kind: .directory, fileID: nextID())
        d.setChildren(kids)
        return d
    }
    /// Aggregates sizes of a hand-built tree (call once on the root).
    public static func finish(_ root: FileNode) -> FileNode { root.aggregate(); return root }

    private final class Counter: @unchecked Sendable { let lock = NSLock(); var v: UInt64 = 1 << 40 }
    private static let counter = Counter()
    private static func nextID() -> UInt64 {
        counter.lock.lock(); defer { counter.lock.unlock() }
        counter.v += 1; return counter.v
    }
}
