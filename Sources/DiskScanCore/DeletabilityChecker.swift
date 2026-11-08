import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Cancellation token for deletion (same semantics as scanning).
public typealias DeletionCancellation = ScanCancellation

/// Decides, BEFORE anything is removed, whether an item can be deleted
/// completely (all-or-nothing pre-pass). It walks the subtree with `lstat`
/// only (symlinks are never followed) and checks:
///
/// - every directory whose entries would be unlinked (the item's parent, and
///   for permanent deletion every non-empty directory inside the item) is
///   writable+searchable for the effective user (`faccessat(W_OK|X_OK, AT_EACCESS)`)
///   and readable (it must be listed);
/// - the sticky-bit rule: in a directory with `S_ISVTX`, an entry can only be
///   removed by root, the entry's owner or the directory's owner;
/// - file flags on every entry and directory: `UF_IMMUTABLE`, `UF_APPEND`,
///   `SF_IMMUTABLE`, `SF_APPEND`, `SF_RESTRICTED`, `SF_NOUNLINK`;
/// - no directory on another device (mount points).
///
/// For a move to the Trash only the top-level item is checked (its parent and
/// flags; for a directory also write access to the directory itself, which a
/// cross-directory rename needs to update `..`).
/// Reads all entry names of an open directory, telling end-of-directory from
/// a read error: `errno` is cleared before every `readdir` call and checked
/// when it returns NULL. `step` performs one `errno = 0; readdir(d)` and
/// returns the name (nil at NULL) and the errno observed right after.
public enum DirectoryListing {
    public static func drain(_ step: () -> (name: String?, errno: Int32)) -> Result<[String], DirectoryReadError> {
        var names: [String] = []
        while true {
            let (name, err) = step()
            guard let name else {
                return err == 0 ? .success(names) : .failure(DirectoryReadError(code: err))
            }
            if name != "." && name != ".." { names.append(name) }
        }
    }

    /// Live: `opendir`/`readdir`/`closedir` on `path`.
    public static func names(atPath path: String) -> Result<[String], DirectoryReadError> {
        errno = 0
        guard let d = opendir(path) else { return .failure(DirectoryReadError(code: errno, atOpen: true)) }
        defer { closedir(d) }
        return drain {
            errno = 0
            guard let ent = readdir(d) else { return (nil, errno) }
            let n = withUnsafePointer(to: &ent.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            return (n, 0)
        }
    }
}

public struct DirectoryReadError: Error, Equatable, Sendable {
    public let code: Int32
    public var atOpen = false
    public init(code: Int32, atOpen: Bool = false) { self.code = code; self.atOpen = atOpen }
}

/// Which ACL deny to look for.
public enum ACLDenyKind: Sendable, Equatable {
    /// `ACL_DELETE` deny on the entry itself.
    case deleteSelf
    /// `ACL_DELETE_CHILD` deny on a folder (its entries can't be removed).
    case deleteChild
}

public struct DeletabilityChecker: Sendable {
    public static let ufImmutable: UInt32 = 0x0000_0002
    public static let ufAppend: UInt32    = 0x0000_0004
    public static let sfImmutable: UInt32 = 0x0002_0000
    public static let sfAppend: UInt32    = 0x0004_0000
    public static let blockingFlags: UInt32 = ufImmutable | ufAppend | sfImmutable | sfAppend
        | DeletionGuard.sfRestricted | DeletionGuard.sfNoUnlink
    static let folderBlockingFlags: UInt32 = ufImmutable | ufAppend | sfImmutable | sfAppend

    public static let fullDiskAccessHint = ReasonText.Detail.fullDiskAccess

    /// `st_flags` for a path (lstat). Live: Darwin `st_flags`; nil elsewhere.
    public var flags: @Sendable (String) -> UInt32?
    /// Effective-access test (`faccessat(..., AT_EACCESS)` by default).
    public var canWriteAndSearch: @Sendable (String) -> Bool
    /// True if the path carries an ACL deny of that kind (any qualifier —
    /// conservative). Live: `acl_get_link_np` on Darwin; false elsewhere.
    public var aclDenies: @Sendable (String, ACLDenyKind) -> Bool
    /// Directory listing (injectable to simulate read errors).
    public var listDirectory: @Sendable (String) -> Result<[String], DirectoryReadError>
    public var effectiveUID: UInt32
    public var limit: Int

    public init(flags: @escaping @Sendable (String) -> UInt32? = DeletabilityChecker.liveFlags,
                canWriteAndSearch: @escaping @Sendable (String) -> Bool = DeletabilityChecker.liveCanWriteAndSearch,
                aclDenies: @escaping @Sendable (String, ACLDenyKind) -> Bool = DeletabilityChecker.liveACLDenies,
                listDirectory: @escaping @Sendable (String) -> Result<[String], DirectoryReadError> = { DirectoryListing.names(atPath: $0) },
                effectiveUID: UInt32 = UInt32(geteuid()),
                limit: Int = 2_000_000) {
        self.flags = flags
        self.canWriteAndSearch = canWriteAndSearch
        self.aclDenies = aclDenies
        self.listDirectory = listDirectory
        self.effectiveUID = effectiveUID
        self.limit = limit
    }

    public static let live = DeletabilityChecker()

    /// Returns the first problem, `.cancelled` if `cancellation` fired, or nil.
    /// `progress` gets (entries checked so far, current path) about every 256
    /// entries and once at the end.
    public func check(_ path: String, recursive: Bool,
                      cancellation: DeletionCancellation? = nil,
                      progress: ((Int, String) -> Void)? = nil) -> DeletionGuard.SubtreeIssue? {
        let item = ScanEngine.normalize(path)
        var st = stat()
        guard lstat(item, &st) == 0 else {
            return errno == EPERM ? .notDeletable(item, Self.fullDiskAccessHint) : nil   // vanished: the deleter reports it
        }
        let parent = DeletionGuard.parent(of: item)
        var pst = stat()
        guard lstat(parent, &pst) == 0 else { return Self.statFailure(parent, errno) }
        // Per-folder verdicts (flags, ACL delete_child, write+search) are
        // computed once per folder, not once per entry.
        var folderCache: [String: DeletionGuard.SubtreeIssue?] = [:]
        func folderIssue(_ dir: String) -> DeletionGuard.SubtreeIssue? {
            if let cached = folderCache[dir] { return cached }
            let v = checkFolderAllowsRemoval(dir)
            folderCache[dir] = .some(v)
            return v
        }
        if let issue = folderIssue(parent) ?? canRemoveEntry(item, st, sticky: pst) { return issue }
        let isDir = Self.isDir(st)
        if !recursive {
            if isDir && !canWriteAndSearch(item) {
                return .notDeletable(item, ReasonText.Detail.folderNotWritableToMove)
            }
            return nil
        }
        guard isDir else { return nil }
        let rootDev = DeviceID.key(st.st_dev)
        var stack: [(String, stat)] = [(item, st)]
        var visited = 0
        while let (dir, dst) = stack.popLast() {
            if cancellation?.isCancelled == true { return .cancelled }
            let names: [String]
            switch listDirectory(dir) {
            case .success(let n): names = n
            case .failure(let e):
                if e.code == EPERM { return .notDeletable(dir, Self.fullDiskAccessHint) }
                if e.atOpen { return .unreadable(dir) }
                return .notDeletable(dir, "folder could not be read completely (\(String(cString: strerror(e.code))))")
            }
            if !names.isEmpty, let issue = folderIssue(dir) { return issue }
            for name in names {
                let child = PathUtil.join(dir, name)
                var cs = stat()
                guard lstat(child, &cs) == 0 else { return Self.statFailure(child, errno) }
                visited += 1
                if visited > limit { return .unreadable(dir) }
                if visited % 256 == 0 {
                    if cancellation?.isCancelled == true { return .cancelled }
                    progress?(visited, child)
                }
                if let issue = canRemoveEntry(child, cs, sticky: dst) { return issue }
                if Self.isDir(cs) {
                    if DeviceID.key(cs.st_dev) != rootDev { return .otherDevice(child) }
                    stack.append((child, cs))
                }
            }
        }
        progress?(visited, item)
        return nil
    }

    static func statFailure(_ path: String, _ code: Int32) -> DeletionGuard.SubtreeIssue {
        code == EPERM ? .notDeletable(path, fullDiskAccessHint) : .unreadable(path)
    }

    /// Folder-level conditions for removing ANY entry from `dir`.
    private func checkFolderAllowsRemoval(_ dir: String) -> DeletionGuard.SubtreeIssue? {
        if let f = flags(dir), f & Self.folderBlockingFlags != 0 {
            return .notDeletable(dir, "folder is " + Self.flagText(f) + " (entries can't be removed)")
        }
        if aclDenies(dir, .deleteChild) {
            return .notDeletable(dir, ReasonText.Detail.folderACLDenyChild)
        }
        if !canWriteAndSearch(dir) {
            return .notDeletable(dir, ReasonText.Detail.folderReadOnly)
        }
        return nil
    }

    /// Entry-level conditions (flags, ACL delete deny, sticky bit of its folder).
    private func canRemoveEntry(_ entry: String, _ est: stat, sticky dst: stat) -> DeletionGuard.SubtreeIssue? {
        if let f = flags(entry), f & Self.blockingFlags != 0 {
            if f & (DeletionGuard.sfRestricted | DeletionGuard.sfNoUnlink) != 0 { return .restricted(entry) }
            return .notDeletable(entry, Self.flagText(f))
        }
        if aclDenies(entry, .deleteSelf) {
            return .notDeletable(entry, ReasonText.Detail.entryACLDeny)
        }
        let sticky = (UInt32(truncatingIfNeeded: dst.st_mode) & 0o1000) != 0
        if sticky && effectiveUID != 0
            && UInt32(est.st_uid) != effectiveUID && UInt32(dst.st_uid) != effectiveUID {
            return .notDeletable(entry, ReasonText.Detail.stickyOtherUser)
        }
        return nil
    }

    static func flagText(_ f: UInt32) -> String {
        var parts: [String] = []
        if f & ufImmutable != 0 { parts.append("locked (uchg)") }
        if f & ufAppend != 0 { parts.append("append-only (uappnd)") }
        if f & sfImmutable != 0 { parts.append("system-immutable (schg)") }
        if f & sfAppend != 0 { parts.append("system-append-only (sappnd)") }
        return parts.isEmpty ? "flagged" : parts.joined(separator: ", ")
    }

    static func isDir(_ st: stat) -> Bool { (UInt32(truncatingIfNeeded: st.st_mode) & 0o170000) == 0o040000 }

    public static let liveFlags: @Sendable (String) -> UInt32? = { path in
        #if canImport(Darwin)
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return UInt32(st.st_flags)
        #else
        return nil
        #endif
    }

    public static let liveCanWriteAndSearch: @Sendable (String) -> Bool = { path in
        faccessat(AT_FDCWD, path, W_OK | X_OK, AT_EACCESS) == 0
    }

    /// Darwin: scans the extended ACL (`acl_get_link_np`, never follows a
    /// symlink) for an `ACL_EXTENDED_DENY` entry carrying `ACL_DELETE` or
    /// `ACL_DELETE_CHILD`. Any qualifier counts (conservative: we don't
    /// resolve group membership). Linux: no NFSv4-style ACLs here; false.
    public static let liveACLDenies: @Sendable (String, ACLDenyKind) -> Bool = { path, kind in
        #if canImport(Darwin)
        guard let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var which = ACL_FIRST_ENTRY.rawValue
        while acl_get_entry(acl, Int32(which), &entry) == 0, let e = entry {
            which = ACL_NEXT_ENTRY.rawValue
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(e, &tag) == 0, tag == ACL_EXTENDED_DENY else { continue }
            var perms: acl_permset_t?
            guard acl_get_permset(e, &perms) == 0, let ps = perms else { continue }
            let perm = kind == .deleteSelf ? ACL_DELETE : ACL_DELETE_CHILD
            if acl_get_perm_np(ps, perm) == 1 { return true }
        }
        return false
        #else
        return false
        #endif
    }
}
