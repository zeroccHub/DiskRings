import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Stable identity of a filesystem object, taken with `lstat` (never follows
/// symlinks). Used to make sure the item deleted is the item that was checked.
public struct FileIdentity: Equatable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }

    /// `lstat` identity of `path`, or nil if it can't be stat'ed.
    public static func of(_ path: String) -> FileIdentity? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return FileIdentity(device: DeviceID.key(st.st_dev), inode: UInt64(truncatingIfNeeded: st.st_ino))
    }
}

/// One conversion for `dev_t` everywhere (lstat, getattrlistbulk, deleter):
/// a 32-bit signed `dev_t` (Darwin) is reinterpreted bit-for-bit as unsigned
/// (`UInt32(bitPattern:)`), never sign-extended; 64-bit `dev_t` (Linux) is
/// taken as is. Both enumerators and the deleter therefore agree on keys.
public enum DeviceID {
    @inline(__always)
    public static func key<T: FixedWidthInteger>(_ dev: T) -> UInt64 {
        if T.bitWidth <= 32 { return UInt64(UInt32(truncatingIfNeeded: dev)) }
        return UInt64(truncatingIfNeeded: dev)
    }
}

/// Decides whether a path may be deleted. Pure Swift; every OS dependency
/// (mount table, file flags, symlink resolution, subtree inspection, home
/// folder) is injectable so the rules are unit-tested on Linux.
///
/// Canonical path (used both for the decision AND for the actual delete):
/// - paths containing a `..` component are refused outright (the kernel
///   resolves `a/lnk/..` relative to the symlink *target*, so a lexical
///   collapse could check a different path than the one deleted);
/// - `.` and `//` are dropped; the parent directory is resolved with
///   `realpath`; the last component is resolved to its on-disk spelling when
///   it is not a symlink (a symlink itself is what gets deleted, never its target);
/// - `/etc`, `/var`, `/tmp` map to `/private/...`; `/System/Volumes/Data/<x>`
///   maps to `/<x>` (firmlinks).
///
/// All rule comparisons are case-insensitive (APFS default; conservative on
/// case-sensitive volumes too). Blocking rules:
/// 1. `/`, any mount point, and any folder that CONTAINS a mount point.
/// 2. The home folder itself and any ancestor of it (its contents are allowed).
/// 3. Anything at or below a protected prefix, except at/below `/usr/local`.
/// 4. Any ancestor of a protected prefix.
/// 5. A few essential top-level folders themselves (contents allowed).
/// 6. Items carrying `SF_RESTRICTED` (SIP) or `SF_NOUNLINK`.
/// 7. (`preflight`) anything whose subtree crosses a device, contains a
///    restricted/no-unlink item, or can't be fully inspected.
///
/// Separately, `caution(for:)` flags items that are allowed but deserve an
/// extra, explicit confirmation (launchd jobs, app bundles in /Applications,
/// per-user temp/cache folders under /private/var/folders).
public struct DeletionGuard: @unchecked Sendable {
    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        case filesystemRoot
        case volumeRoot(String)
        case containsVolume(String)
        case homeFolder
        case containsHomeFolder
        case systemLocation(String)
        case containsProtected(String)
        case essentialFolder(String)
        case sipProtected
        case unsafePath(String)
        case containsOtherDevice(String)
        case containsRestricted(String)
        case contentsNotVerifiable(String)
        case changedSinceCheck(String)
        case cannotDelete(String, String)
        case cancelled

        public var description: String {
            switch self {
            case .filesystemRoot: return "Protected: filesystem root"
            case .volumeRoot(let p): return "Protected: volume root (\(p))"
            case .containsVolume(let p): return "Protected: contains the mounted volume \(p)"
            case .homeFolder: return "Protected: your home folder"
            case .containsHomeFolder: return "Protected: contains your home folder"
            case .systemLocation(let p): return "Protected: system location (\(p))"
            case .containsProtected(let p): return "Protected: contains system location \(p)"
            case .essentialFolder(let p): return "Protected: essential folder (\(p))"
            case .sipProtected: return "SIP-protected (restricted / no-unlink flag)"
            case .unsafePath(let why): return "Refused: unsafe path (\(why))"
            case .containsOtherDevice(let p): return "Refused: contains another volume or mount (\(p))"
            case .containsRestricted(let p): return "Refused: contains a SIP-protected item (\(p))"
            case .contentsNotVerifiable(let p): return "Refused: contents could not be fully checked (\(p))"
            case .changedSinceCheck(let p): return "Refused: item changed since it was checked (\(p))"
            case .cannotDelete(let p, let why): return "Refused: can't be deleted completely — \(why) (\(p))"
            case .cancelled: return "Cancelled"
            }
        }
    }

    /// Allowed, but needs an extra explicit confirmation with this warning.
    public enum Caution: Equatable, Sendable, CustomStringConvertible {
        case launchdJob(String)
        case applicationBundle(String)
        case systemTempFolders(String)

        public var description: String {
            switch self {
            case .launchdJob(let p):
                return "Background service definition (\(p)). Removing it can break or disable software (VPNs, drivers, updaters, security tools); the change takes effect at next login/boot."
            case .applicationBundle(let p):
                return "Application bundle (\(p)). Deleting an app does not remove its helpers or data, and some apps need a vendor uninstaller."
            case .systemTempFolders(let p):
                return "Per-user system caches and temp files (\(p)). Running apps may crash or lose state; macOS recreates what it needs after a restart."
            }
        }
    }

    /// Result of `evaluate`: the canonical path the decision applies to (and
    /// that must be deleted), the blocking reason, and an optional caution.
    public struct Verdict: Equatable, Sendable {
        public let canonicalPath: String
        public let reason: Reason?
        public let caution: Caution?
        /// `lstat` identity at evaluation time (nil if unknown).
        public let identity: FileIdentity?
    }

    /// What a subtree inspection found.
    public enum SubtreeIssue: Equatable, Sendable {
        case otherDevice(String)
        case restricted(String)
        case unreadable(String)
        /// Can't be removed completely (path, human-readable why).
        case notDeletable(String, String)
        case cancelled
    }

    /// Paths at or below these are blocked.
    public static let defaultProtectedPrefixes = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple", "/private/etc",
        // additions:
        "/private/var/vm",      // swap & sleep image
        "/private/var/root",    // root's home
        "/dev",
        "/Library/Developer/CommandLineTools", // the toolchain this app is built with
    ]
    /// Paths at or below these are allowed even if under a protected prefix.
    public static let defaultAllowedExceptions = ["/usr/local"]
    /// Folders that are blocked themselves (their contents are fine).
    public static let defaultEssentialFolders = [
        "/Applications", "/Library", "/Users", "/Volumes", "/private", "/private/var", "/private/tmp",
        "/opt", "/cores",
    ]
    /// At or below these: allowed, with an extra confirmation.
    public static let launchdFolders = ["/Library/LaunchDaemons", "/Library/LaunchAgents"]
    public static let systemTempFolder = "/private/var/folders"
    /// Top-level symlinks on macOS.
    public static let aliasPrefixes: [(String, String)] = [
        ("/etc", "/private/etc"), ("/var", "/private/var"), ("/tmp", "/private/tmp"),
    ]
    /// APFS Data volume; `/System/Volumes/Data/X` is the same item as `/X` via firmlinks.
    public static let dataVolumePrefix = "/System/Volumes/Data"

    /// `SF_RESTRICTED` and `SF_NOUNLINK` from `<sys/stat.h>`.
    public static let sfRestricted: UInt32 = 0x0008_0000
    public static let sfNoUnlink: UInt32 = 0x0010_0000

    public var protectedPrefixes: [String]
    public var allowedExceptions: [String]
    public var essentialFolders: [String]
    public var homeDirectory: String
    public var mountPoints: () -> [String]
    /// `st_flags` of the item itself (lstat); nil if unknown/unsupported.
    public var fileFlags: (String) -> UInt32?
    /// Canonicalizes a directory path (resolving symlinks); identity in tests.
    public var resolveDirectory: (String) -> String
    /// On-disk spelling of an existing non-symlink item (case, Unicode form);
    /// returns the input when unknown. Identity in tests.
    public var resolveItem: (String) -> String
    /// Inspects everything below a directory (no symlink following); nil = clean.
    public var inspectSubtree: (String) -> SubtreeIssue?
    /// `lstat` identity; nil when unknown (tests).
    public var identify: (String) -> FileIdentity?
    /// All-or-nothing deletability pre-pass (permissions, sticky bit, uchg/schg/
    /// append flags). Args: path, recursive (permanent delete) or top-level only
    /// (Trash), cancellation. Live: `DeletabilityChecker`. Default: nothing found.
    public var checkDeletable: (String, Bool, DeletionCancellation?) -> SubtreeIssue?
    /// True when a recursive `checkDeletable` already checks devices, SIP flags
    /// and readability (live), so `inspectSubtree` needn't walk again.
    public var deletabilityCoversSubtree = false

    public init(homeDirectory: String,
                mountPoints: @escaping () -> [String] = { [] },
                fileFlags: @escaping (String) -> UInt32? = { _ in nil },
                resolveDirectory: @escaping (String) -> String = { $0 },
                resolveItem: @escaping (String) -> String = { $0 },
                inspectSubtree: @escaping (String) -> SubtreeIssue? = { _ in nil },
                identify: @escaping (String) -> FileIdentity? = { _ in nil },
                checkDeletable: @escaping (String, Bool, DeletionCancellation?) -> SubtreeIssue? = { _, _, _ in nil },
                protectedPrefixes: [String] = DeletionGuard.defaultProtectedPrefixes,
                allowedExceptions: [String] = DeletionGuard.defaultAllowedExceptions,
                essentialFolders: [String] = DeletionGuard.defaultEssentialFolders) {
        self.homeDirectory = homeDirectory
        self.mountPoints = mountPoints
        self.fileFlags = fileFlags
        self.resolveDirectory = resolveDirectory
        self.resolveItem = resolveItem
        self.inspectSubtree = inspectSubtree
        self.identify = identify
        self.checkDeletable = checkDeletable
        self.protectedPrefixes = protectedPrefixes
        self.allowedExceptions = allowedExceptions
        self.essentialFolders = essentialFolders
    }

    /// Guard wired to the real system.
    public static func live() -> DeletionGuard {
        var g = DeletionGuard(homeDirectory: realDirectory(NSHomeDirectory()),
                      mountPoints: liveMountPoints,
                      fileFlags: liveFileFlags,
                      resolveDirectory: realDirectory,
                      resolveItem: liveResolveItem,
                      inspectSubtree: { liveInspectSubtree($0) },
                      identify: FileIdentity.of,
                      checkDeletable: { DeletabilityChecker.live.check($0, recursive: $1, cancellation: $2) })
        g.deletabilityCoversSubtree = true
        return g
    }

    // MARK: Checking

    /// Fast check (no subtree walk): why `path` must not be deleted, or nil.
    public func check(_ path: String) -> Reason? { evaluate(path).reason }

    public func isDeletable(_ path: String) -> Bool { check(path) == nil }

    /// Full decision for `path`. With `preflight`, folders are additionally
    /// inspected recursively (rule 7) — use that right before deleting.
    public func evaluate(_ path: String, preflight: Bool = false, recursive: Bool = true,
                         cancellation: DeletionCancellation? = nil) -> Verdict {
        let given = Self.normalize(path)
        if Self.hasDotDot(path) {
            return Verdict(canonicalPath: given, reason: .unsafePath("contains '..'"), caution: nil, identity: nil)
        }
        if given == "/" { return Verdict(canonicalPath: "/", reason: .filesystemRoot, caution: nil, identity: nil) }
        // `real` is what gets deleted; `canonical` (aliases + firmlinks mapped)
        // only drives the rules. On macOS both name the same object.
        let real = resolvedPath(given)
        let canonical = Self.mapFirmlinks(Self.applyAliases(real))
        let ck = Self.key(canonical)
        func verdict(_ c: String, _ r: Reason?, _ caution: Caution? = nil) -> Verdict {
            Verdict(canonicalPath: real, reason: r, caution: r == nil ? caution : nil, identity: r == nil ? identify(real) : nil)
        }
        if ck == "/" { return verdict(canonical, .filesystemRoot) }

        // 1. volume roots and folders containing a mount point
        let mountList = mountPoints().map { Self.normalize($0) }
        let mounts = mountList.map { Self.key(Self.mapFirmlinks(Self.applyAliases($0))) }
        let gk = Self.key(given)
        if Set(mounts).contains(ck) || Set(mounts).contains(gk) || ck == Self.key(Self.dataVolumePrefix) {
            return verdict(canonical, .volumeRoot(given))
        }
        if let i = mounts.firstIndex(where: { $0 != "/" && Self.isStrictAncestor(ck, of: $0) }) {
            return verdict(canonical, .containsVolume(mountList[i]))
        }

        // 2. home
        let home = Self.key(canonicalize(Self.normalize(homeDirectory)))
        if ck == home { return verdict(canonical, .homeFolder) }
        if Self.isStrictAncestor(ck, of: home) { return verdict(canonical, .containsHomeFolder) }

        // 3./4. protected prefixes
        for prefix in protectedPrefixes {
            let pk = Self.key(prefix)
            if Self.isAtOrBelow(ck, pk) {
                if allowedExceptions.contains(where: { Self.isAtOrBelow(ck, Self.key($0)) }) { continue }
                return verdict(canonical, .systemLocation(prefix))
            }
            if Self.isStrictAncestor(ck, of: pk) { return verdict(canonical, .containsProtected(prefix)) }
        }
        // 5. essential folders
        if let e = essentialFolders.first(where: { Self.key($0) == ck }) { return verdict(canonical, .essentialFolder(e)) }

        // 6. flags of the item itself
        if let flags = fileFlags(real), flags & (Self.sfRestricted | Self.sfNoUnlink) != 0 {
            return verdict(canonical, .sipProtected)
        }

        // 7. subtree
        if preflight {
            if cancellation?.isCancelled == true { return verdict(canonical, .cancelled) }
            // Permanent delete: the cancellable deletability walk also covers devices,
            // SIP flags and readability; the device/SIP walk runs as well when the
            // deletability check is top-level only (Trash) or not wired (tests).
            let deletable = checkDeletable(real, recursive, cancellation)
            let skipWalk = deletable != nil || (recursive && deletabilityCoversSubtree)
            let issues: [SubtreeIssue?] = skipWalk ? [deletable] : [inspectSubtree(real)]
            for issue in issues {
                switch issue {
                case nil: continue
                case .otherDevice(let p)?: return verdict(canonical, .containsOtherDevice(p))
                case .restricted(let p)?: return verdict(canonical, .containsRestricted(p))
                case .unreadable(let p)?: return verdict(canonical, .contentsNotVerifiable(p))
                case .notDeletable(let p, let why)?: return verdict(canonical, .cannotDelete(p, why))
                case .cancelled?: return verdict(canonical, .cancelled)
                }
            }
        }
        return verdict(canonical, nil, Self.caution(forKey: ck, canonical: real))
    }

    /// Caution for an allowed path (see type docs), nil if none.
    public func caution(for path: String) -> Caution? {
        let v = evaluate(path)
        return v.caution
    }

    static func caution(forKey ck: String, canonical: String) -> Caution? {
        for f in launchdFolders where isAtOrBelow(ck, key(f)) { return .launchdJob(canonical) }
        if isAtOrBelow(ck, key(systemTempFolder)) { return .systemTempFolders(canonical) }
        // /Applications/<X>.app or anything inside it
        let apps = key("/Applications") + "/"
        if ck.hasPrefix(apps) {
            let first = ck.dropFirst(apps.count).split(separator: "/").first.map(String.init) ?? ""
            if first.hasSuffix(".app") { return .applicationBundle(canonical) }
        }
        return nil
    }

    /// The real path that is checked and deleted: parent resolved with
    /// `realpath`, last component in its on-disk spelling (not followed if it
    /// is a symlink). Input must be normalized and free of `..`.
    public func resolvedPath(_ normalized: String) -> String {
        guard normalized != "/" else { return "/" }
        let parent = Self.parent(of: normalized)
        let resolvedParent = Self.normalize(resolveDirectory(parent))
        let p = PathUtil.join(resolvedParent, Self.lastComponent(of: normalized))
        let resolved = Self.normalize(resolveItem(p))
        // Only accept a spelling change of the last component in the same parent.
        return Self.key(Self.parent(of: resolved)) == Self.key(resolvedParent) ? resolved : p
    }

    /// Rule-comparison form: `resolvedPath` with aliases and firmlinks mapped.
    public func canonicalize(_ normalized: String) -> String {
        Self.mapFirmlinks(Self.applyAliases(resolvedPath(normalized)))
    }

    // MARK: Path helpers (pure)

    /// Case-folded comparison key.
    static func key(_ p: String) -> String { p.lowercased() }

    static func hasDotDot(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    /// Absolute-path normalization: drops `//`, `.` and a trailing `/`.
    /// `..` is collapsed lexically here only for display; `evaluate` refuses
    /// any path that contains it.
    public static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(comp)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Case-insensitive prefix replacement for the macOS top-level aliases.
    public static func applyAliases(_ p: String) -> String {
        for (alias, target) in aliasPrefixes {
            if let rest = dropPrefixCI(p, alias) { return target + rest }
        }
        return p
    }

    static func mapFirmlinks(_ p: String) -> String {
        if let rest = dropPrefixCI(p, dataVolumePrefix), !rest.isEmpty { return applyAliases(rest) }
        return p
    }

    /// If `p` equals `prefix` or starts with `prefix + "/"` (case-insensitive),
    /// returns the remainder ("" or "/..."), else nil.
    static func dropPrefixCI(_ p: String, _ prefix: String) -> String? {
        let pk = key(p), xk = key(prefix)
        if pk == xk { return "" }
        guard pk.hasPrefix(xk + "/"), p.count >= prefix.count else { return nil }
        return String(p.dropFirst(prefix.count))
    }

    static func isAtOrBelow(_ p: String, _ prefix: String) -> Bool {
        p == prefix || p.hasPrefix(prefix + "/")
    }

    static func isStrictAncestor(_ p: String, of other: String) -> Bool {
        p == "/" ? other != "/" : other.hasPrefix(p + "/")
    }

    static func parent(of p: String) -> String {
        guard let idx = p.lastIndex(of: "/"), idx != p.startIndex else { return "/" }
        return String(p[..<idx])
    }

    static func lastComponent(of p: String) -> String {
        guard let idx = p.lastIndex(of: "/") else { return p }
        return String(p[p.index(after: idx)...])
    }

    // MARK: Live providers

    static func realDirectory(_ dir: String) -> String {
        guard let r = realpath(dir, nil) else { return dir }
        defer { free(r) }
        return String(cString: r)
    }

    /// On-disk spelling of a non-symlink item. On Darwin `F_GETPATH` returns
    /// the real case; elsewhere `realpath` (which also normalizes).
    static func liveResolveItem(_ path: String) -> String {
        var st = stat()
        guard lstat(path, &st) == 0 else { return path }
        if (UInt32(truncatingIfNeeded: st.st_mode) & 0o170000) == 0o120000 { return path } // symlink: keep
        #if canImport(Darwin)
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd >= 0 {
            defer { close(fd) }
            var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(fd, F_GETPATH, &buf) == 0 { return String(cString: buf) }
        }
        #endif
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }

    static func liveFileFlags(_ path: String) -> UInt32? {
        #if canImport(Darwin)
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return UInt32(st.st_flags)
        #else
        return nil
        #endif
    }

    /// Walks the subtree with `lstat` only (symlinks are not followed) and
    /// reports the first device change, restricted/no-unlink item, or
    /// unreadable directory. `limit` bounds the walk; exceeding it is reported
    /// as `.unreadable` (conservative).
    static func liveInspectSubtree(_ root: String, limit: Int = 2_000_000) -> SubtreeIssue? {
        var st = stat()
        guard lstat(root, &st) == 0 else { return nil }   // vanished: deleter will report
        guard (UInt32(truncatingIfNeeded: st.st_mode) & 0o170000) == 0o040000 else { return nil }
        let rootDev = DeviceID.key(st.st_dev)
        var stack = [root]
        var visited = 0
        while let dir = stack.popLast() {
            guard case .success(let names) = DirectoryListing.names(atPath: dir) else { return .unreadable(dir) }
            for name in names {
                visited += 1
                if visited > limit { return .unreadable(dir) }
                let child = PathUtil.join(dir, name)
                var cs = stat()
                guard lstat(child, &cs) == 0 else { return .unreadable(child) }
                #if canImport(Darwin)
                if UInt32(cs.st_flags) & (sfRestricted | sfNoUnlink) != 0 { return .restricted(child) }
                #endif
                guard (UInt32(truncatingIfNeeded: cs.st_mode) & 0o170000) == 0o040000 else { continue }
                // Mount points are directories. (Only directories are compared:
                // overlay filesystems report a different st_dev for regular files.)
                if DeviceID.key(cs.st_dev) != rootDev { return .otherDevice(child) }
                stack.append(child)
            }
        }
        return nil
    }

    static func liveMountPoints() -> [String] {
        #if os(macOS)
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])?.map { $0.path } ?? []
        #else
        guard let text = try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count > 1 else { return nil }
            return String(fields[1]).replacingOccurrences(of: "\\040", with: " ")
        }
        #endif
    }
}

/// Which path to scan when the user clicks a volume.
public enum VolumeScanTarget {
    /// For the boot volume (`/`), the read-only System volume holds little the
    /// user can delete; the user's data lives on the Data volume mounted at
    /// `/System/Volumes/Data`. Scan that when it exists.
    public static func path(forVolumeAt volumePath: String, isRootFileSystem: Bool,
                            fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        if isRootFileSystem && fileExists(DeletionGuard.dataVolumePrefix) { return DeletionGuard.dataVolumePrefix }
        return volumePath
    }
}

/// User-facing paths. Scanning the startup disk uses the Data volume mount
/// (`/System/Volumes/Data`), whose contents are firmlinked to `/` — show
/// `/Users/x` rather than `/System/Volumes/Data/Users/x`. Display only: all
/// checks and deletes keep using the real path.
public enum DisplayPath {
    public static func forUser(_ path: String) -> String {
        let prefix = DeletionGuard.dataVolumePrefix
        guard path.hasPrefix(prefix + "/") else { return path }
        return String(path.dropFirst(prefix.count))
    }

    /// Same mapping for paths embedded in messages (reasons, errors).
    public static func inText(_ text: String) -> String {
        text.replacingOccurrences(of: DeletionGuard.dataVolumePrefix + "/", with: "/")
    }
}
