import Foundation

/// A fake filesystem for tests and previews. Paths are absolute, "/"-separated.
/// Thread-safe (immutable after construction).
public final class InMemoryDirectoryEnumerator: DirectoryEnumerator, @unchecked Sendable {
    public enum FakeItem {
        case file(name: String, size: UInt64, allocated: UInt64? = nil, inode: UInt64? = nil, links: UInt32 = 1,
                  device: UInt64? = nil, cloneID: UInt64? = nil, privateSize: UInt64? = nil, extFlags: UInt64? = nil)
        case symlink(name: String)
        case dir(name: String, device: UInt64? = nil, unreadable: Bool = false, mountPoint: Bool = false, [FakeItem])
    }

    private var listings: [String: [DirectoryEntry]] = [:]
    private var unreadable: Set<String> = []
    private var roots: [String: DirectoryEntry] = [:]
    private var nextInode: UInt64 = 1000
    public private(set) var enumeratedDirectories = Counter()

    public final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        public var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// - Parameters:
    ///   - rootPath: absolute path of the fake root directory.
    ///   - device: default device id for everything not overriding it.
    public init(rootPath: String, device: UInt64 = 1, _ items: [FakeItem]) {
        roots[rootPath] = DirectoryEntry(name: rootPath, kind: .directory, device: device, fileID: 2)
        register(path: rootPath, device: device, items: items)
    }

    private func allocInode() -> UInt64 { nextInode += 1; return nextInode }

    private func register(path: String, device: UInt64, items: [FakeItem]) {
        var list: [DirectoryEntry] = []
        for item in items {
            switch item {
            case let .file(name, size, allocated, inode, links, dev, cloneID, privateSize, extFlags):
                list.append(DirectoryEntry(name: name, kind: .file, device: dev ?? device,
                                           fileID: inode ?? allocInode(), linkCount: links,
                                           logicalSize: size, allocatedSize: allocated ?? Self.roundUp(size),
                                           cloneID: cloneID, privateSize: privateSize, extFlags: extFlags))
            case let .symlink(name):
                list.append(DirectoryEntry(name: name, kind: .symlink, device: device,
                                           fileID: allocInode(), logicalSize: 20, allocatedSize: 0))
            case let .dir(name, dev, unread, mp, children):
                let d = dev ?? device
                list.append(DirectoryEntry(name: name, kind: .directory, device: d,
                                           fileID: allocInode(), isMountPoint: mp))
                let childPath = PathUtil.join(path, name)
                if unread { unreadable.insert(childPath) }
                register(path: childPath, device: d, items: children)
            }
        }
        listings[path] = list
    }

    static func roundUp(_ size: UInt64) -> UInt64 { (size + 4095) / 4096 * 4096 }

    public func rootEntry(at path: String) throws -> DirectoryEntry {
        guard let r = roots[path] else { throw EnumeratorError.notFound(path: path) }
        return r
    }

    public func entries(inDirectoryAt path: String) throws -> [DirectoryEntry] {
        enumeratedDirectories.increment()
        if unreadable.contains(path) { throw EnumeratorError.posix(path: path, code: 13 /* EACCES */) }
        guard let l = listings[path] else { throw EnumeratorError.notFound(path: path) }
        return l
    }
}
