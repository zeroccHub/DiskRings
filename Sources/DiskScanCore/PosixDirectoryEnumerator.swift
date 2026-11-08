import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Portable fallback enumerator: `opendir`/`readdir` + one `lstat` per entry.
/// Slower than the Darwin bulk enumerator (one syscall per file) but works on
/// Linux, which makes it useful for tests and for exercising the engine on the
/// build box. Never follows symlinks.
public struct PosixDirectoryEnumerator: DirectoryEnumerator {
    /// Optional clone info for regular files (path → clone id, private size,
    /// ext flags). Plain POSIX has no clone API; tests inject this to exercise
    /// the clone accounting end-to-end on Linux.
    public typealias CloneInfo = (cloneID: UInt64, privateSize: UInt64?, extFlags: UInt64?)
    public var cloneInfoProvider: (@Sendable (String) -> CloneInfo?)?

    public init(cloneInfoProvider: (@Sendable (String) -> CloneInfo?)? = nil) {
        self.cloneInfoProvider = cloneInfoProvider
    }

    public func rootEntry(at path: String) throws -> DirectoryEntry {
        try Self.lstatEntry(path: path, name: path)
    }

    public func entries(inDirectoryAt path: String) throws -> [DirectoryEntry] {
        // errno is cleared before each readdir: NULL + errno != 0 is a read
        // error (the folder is then reported unreadable), not end-of-folder.
        let names: [String]
        switch DirectoryListing.names(atPath: path) {
        case .success(let n): names = n
        case .failure(let e): throw EnumeratorError.posix(path: path, code: e.code)
        }
        var result: [DirectoryEntry] = []
        for name in names {
            // An entry that vanished between readdir and lstat is simply skipped.
            let full = PathUtil.join(path, name)
            if var e = try? Self.lstatEntry(path: full, name: name) {
                if e.kind == .file, let info = cloneInfoProvider?(full) {
                    e.cloneID = info.cloneID
                    e.privateSize = info.privateSize
                    e.extFlags = info.extFlags
                }
                result.append(e)
            }
        }
        return result
    }

    static func lstatEntry(path: String, name: String) throws -> DirectoryEntry {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            let code = errno
            if code == ENOENT { throw EnumeratorError.notFound(path: path) }
            throw EnumeratorError.posix(path: path, code: code)
        }
        let mode = UInt32(truncatingIfNeeded: st.st_mode) & 0o170000
        let kind: NodeKind
        switch mode {
        case 0o040000: kind = .directory
        case 0o100000: kind = .file
        case 0o120000: kind = .symlink
        default: kind = .other
        }
        let isDir = kind == .directory
        return DirectoryEntry(
            name: name,
            kind: kind,
            device: DeviceID.key(st.st_dev),
            fileID: UInt64(truncatingIfNeeded: st.st_ino),
            linkCount: UInt32(truncatingIfNeeded: st.st_nlink),
            // Directory "sizes" are ignored by the engine (it aggregates children).
            logicalSize: isDir ? 0 : UInt64(max(0, Int64(st.st_size))),
            allocatedSize: isDir ? 0 : UInt64(max(0, Int64(st.st_blocks))) * 512,
            isMountPoint: false
        )
    }
}
