import Foundation

/// One entry returned while listing a directory. Mirrors the subset of
/// attributes the scanner needs; produced by a platform-specific enumerator.
public struct DirectoryEntry: Sendable, Equatable {
    public var name: String
    public var kind: NodeKind
    public var device: UInt64
    public var fileID: UInt64
    public var linkCount: UInt32
    public var logicalSize: UInt64
    public var allocatedSize: UInt64
    /// Enumerator positively knows this directory is a mount point.
    public var isMountPoint: Bool
    /// APFS clone family id (ATTR_CMNEXT_CLONEID); nil if the volume/enumerator doesn't report it.
    public var cloneID: UInt64?
    /// Bytes not shared with any clone (ATTR_CMNEXT_PRIVATESIZE); nil if unknown.
    public var privateSize: UInt64?
    /// Extended flags (ATTR_CMNEXT_EXT_FLAGS, EF_*); nil if unknown.
    public var extFlags: UInt64?

    /// Whether this file may share data blocks with clones. If flags are
    /// unknown but a clone id is present, assume it may.
    public var mayShareBlocks: Bool {
        // Conservative: unknown flags or unknown private size => no dedup
        // (the file is charged its full allocated size; never under-counted).
        guard cloneID != nil, privateSize != nil, let f = extFlags else { return false }
        return f & (BulkAttr.efMayShareBlocks | BulkAttr.efSharesAllBlocks) != 0
    }

    public init(name: String, kind: NodeKind, device: UInt64, fileID: UInt64,
                linkCount: UInt32 = 1, logicalSize: UInt64 = 0, allocatedSize: UInt64 = 0,
                isMountPoint: Bool = false, cloneID: UInt64? = nil, privateSize: UInt64? = nil,
                extFlags: UInt64? = nil) {
        self.name = name
        self.kind = kind
        self.device = device
        self.fileID = fileID
        self.linkCount = linkCount
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isMountPoint = isMountPoint
        self.cloneID = cloneID
        self.privateSize = privateSize
        self.extFlags = extFlags
    }
}

public enum EnumeratorError: Error, Equatable, Sendable {
    /// errno-style failure opening/reading `path`.
    case posix(path: String, code: Int32)
    case notADirectory(path: String)
    case notFound(path: String)
}

/// Abstraction over the syscall layer. Implementations must be thread-safe:
/// the scan engine calls `entries(inDirectoryAt:)` from several worker
/// threads concurrently (each call for a different directory).
public protocol DirectoryEnumerator: Sendable {
    /// Attributes of the scan root itself (never follows a symlink).
    func rootEntry(at path: String) throws -> DirectoryEntry
    /// Immediate children of a directory (no "." / ".."), without following symlinks.
    func entries(inDirectoryAt path: String) throws -> [DirectoryEntry]
}

public enum PathUtil {
    public static func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }
}

/// The best enumerator for the current platform.
public enum DefaultEnumerator {
    public static func make() -> DirectoryEnumerator {
        #if canImport(Darwin)
        return BulkAttributeEnumerator()
        #else
        return PosixDirectoryEnumerator()
        #endif
    }
}
