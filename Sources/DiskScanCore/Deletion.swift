import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum DeletionError: Error, Equatable, Sendable {
    case posix(path: String, operation: String, code: Int32)
    case trashUnavailable
    case refusedRoot(String)
    case privilegedHelperNotImplemented
    case underlying(path: String, description: String)
    /// Refused by `DeletionGuard` (checked again right before deleting).
    case blocked(path: String, reason: DeletionGuard.Reason)
    /// Needs the extra confirmation described by the caution.
    case needsConfirmation(path: String, caution: DeletionGuard.Caution)
    /// Failed AFTER removal started (I/O error, or the tree changed after the
    /// pre-pass): `removedEntries` entries inside `path` are already gone.
    case partiallyDeleted(path: String, removedEntries: Int, cause: String)
    /// Cancelled before this item was touched.
    case cancelled
}

extension DeletionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .posix(let p, let op, let code):
            let base = "\(op) failed for \(p): \(String(cString: strerror(code))) (errno \(code))"
            return code == EPERM ? base + ". " + DeletabilityChecker.fullDiskAccessHint : base
        case .trashUnavailable: return "The Trash is not available on this system"
        case .refusedRoot(let p): return "Refused to delete \(p)"
        case .privilegedHelperNotImplemented: return "Administrator deletion is not implemented"
        case .underlying(let p, let d): return "\(p): \(d)"
        case .blocked(let p, let r): return "\(p): \(r.description)"
        case .needsConfirmation(let p, let c): return "\(p): needs extra confirmation — \(c.description)"
        case .partiallyDeleted(let p, let n, let cause): return "\(p): PARTIALLY deleted (\(n) entries removed) — \(cause). Rescan this folder."
        case .cancelled: return "Cancelled before this item was touched"
        }
    }
}

/// Removes an item from disk. Implementations must not follow symlinks.
public protocol ItemDeleting: Sendable {
    func deleteItem(atPath path: String) throws
    /// Deletes `path` only if its `lstat` identity still equals `expected`
    /// (nil = no identity known). The default re-checks right before calling
    /// `deleteItem(atPath:)`; `PosixRecursiveDeleter` checks on the open fd.
    func deleteItem(atPath path: String, expected: FileIdentity?) throws
    /// True if the item's whole subtree is unlinked here (permanent delete), so
    /// the all-or-nothing pre-pass must check every folder inside it. False for
    /// a single rename (Trash). Default: true (conservative).
    var deletesRecursively: Bool { get }
    /// Like `deleteItem(atPath:expected:)`, with cancellation (honoured only
    /// before removal starts) and progress for any pre-removal re-check.
    func deleteItem(atPath path: String, expected: FileIdentity?, context: DeletionContext) throws
}

/// Cancellation + progress handed to a deleter for its pre-removal re-check.
public struct DeletionContext: Sendable {
    public var cancellation: DeletionCancellation?
    /// (entries re-checked so far, current path)
    public var progress: (@Sendable (Int, String) -> Void)?
    /// Called once, right before the first removal (point of no return).
    public var willStartRemoval: (@Sendable () -> Void)?
    public init(cancellation: DeletionCancellation? = nil, progress: (@Sendable (Int, String) -> Void)? = nil,
                willStartRemoval: (@Sendable () -> Void)? = nil) {
        self.cancellation = cancellation; self.progress = progress; self.willStartRemoval = willStartRemoval
    }
}

extension ItemDeleting {
    public var deletesRecursively: Bool { true }

    public func deleteItem(atPath path: String, expected: FileIdentity?, context: DeletionContext) throws {
        if context.cancellation?.isCancelled == true { throw DeletionError.cancelled }
        context.willStartRemoval?()
        try deleteItem(atPath: path, expected: expected)
    }

    public func deleteItem(atPath path: String, expected: FileIdentity?) throws {
        if let expected, FileIdentity.of(path) != expected {
            throw DeletionError.blocked(path: path, reason: .changedSinceCheck(path))
        }
        try deleteItem(atPath: path)
    }
}

/// Records original→Trash URLs from `trashItem` so the UI can offer an 8s Undo.
public final class TrashUndoLog: @unchecked Sendable {
    public struct Pair: Sendable {
        public var original: URL
        public var trashed: URL
        public init(original: URL, trashed: URL) { self.original = original; self.trashed = trashed }
    }
    private let lock = NSLock()
    private var _pairs: [Pair] = []
    public init() {}
    public func record(original: URL, trashed: URL) {
        lock.lock(); _pairs.append(Pair(original: original, trashed: trashed)); lock.unlock()
    }
    public var pairs: [Pair] { lock.lock(); defer { lock.unlock() }; return _pairs }
    public func clear() { lock.lock(); _pairs.removeAll(); lock.unlock() }
}

/// Safer default on macOS: move to the user's Trash (recoverable).
public struct TrashDeleter: ItemDeleting {
    public let undoLog: TrashUndoLog?
    public init(undoLog: TrashUndoLog? = nil) { self.undoLog = undoLog }
    public var deletesRecursively: Bool { false }
    public func deleteItem(atPath path: String) throws {
        #if os(macOS)
        do {
            let original = URL(fileURLWithPath: path)
            var resulting: NSURL?
            try FileManager.default.trashItem(at: original, resultingItemURL: &resulting)
            if let trashed = resulting as URL? {
                undoLog?.record(original: original, trashed: trashed)
            }
        } catch {
            throw DeletionError.underlying(path: path, description: error.localizedDescription)
        }
        #else
        throw DeletionError.trashUnavailable
        #endif
    }
}

/// Permanent deletion, depth-first, using directory file descriptors:
/// `openat(O_NOFOLLOW|O_DIRECTORY)`, `fstatat(AT_SYMLINK_NOFOLLOW)` and
/// `unlinkat(dirfd, name, 0 / AT_REMOVEDIR)`. Every step works relative to an
/// already-open, already-verified directory, so a path component swapped for a
/// symlink after the check can't redirect the delete. Never follows symlinks,
/// never descends into another device (refuses with EXDEV), and verifies the
/// top item's (dev, inode) against the identity captured at check time.
///
/// All-or-nothing: before the first unlink, `DeletabilityChecker` walks the
/// whole item (write+search access on every folder whose entries are removed,
/// sticky-bit ownership, uchg/uappnd/schg/sappnd/restricted/no-unlink flags,
/// other devices, readability). If anything would fail, nothing is removed.
/// A failure after removal started is reported as `partiallyDeleted`.
public struct PosixRecursiveDeleter: ItemDeleting {
    public var checker: DeletabilityChecker
    public init(checker: DeletabilityChecker = .live) { self.checker = checker }

    public func deleteItem(atPath path: String) throws {
        try deleteItem(atPath: path, expected: nil)
    }

    public func deleteItem(atPath path: String, expected: FileIdentity?) throws {
        try deleteItem(atPath: path, expected: expected, context: DeletionContext())
    }

    public func deleteItem(atPath path: String, expected: FileIdentity?, context: DeletionContext) throws {
        let p = ScanEngine.normalize(path)
        if p == "/" { throw DeletionError.refusedRoot(p) }
        let parent = DeletionGuard.parent(of: p)
        let name = DeletionGuard.lastComponent(of: p)
        let pfd = open(parent, O_RDONLY | O_DIRECTORY)
        guard pfd >= 0 else { throw DeletionError.posix(path: parent, operation: "open", code: errno) }
        defer { close(pfd) }
        var st = stat()
        guard fstatat(pfd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw DeletionError.posix(path: p, operation: "lstat", code: errno)
        }
        let id = FileIdentity(device: DeviceID.key(st.st_dev), inode: UInt64(truncatingIfNeeded: st.st_ino))
        if let expected, expected != id {
            throw DeletionError.blocked(path: p, reason: .changedSinceCheck(p))
        }
        // All-or-nothing re-check: cancellable, with progress; nothing removed yet.
        switch checker.check(p, recursive: true, cancellation: context.cancellation, progress: context.progress) {
        case nil: break
        case .cancelled?: throw DeletionError.cancelled
        case let issue?: throw DeletionError.blocked(path: p, reason: DeletionGuard.Reason(issue))
        }
        context.willStartRemoval?()
        var removed = 0
        do {
            try remove(dirfd: pfd, name: name, path: p, st: st, device: id.device, removed: &removed)
        } catch let e as DeletionError where removed > 0 {
            throw DeletionError.partiallyDeleted(path: p, removedEntries: removed, cause: e.description)
        }
    }

    private static func isDir(_ st: stat) -> Bool {
        (UInt32(truncatingIfNeeded: st.st_mode) & 0o170000) == 0o040000
    }

    private func remove(dirfd: Int32, name: String, path: String, st: stat, device: UInt64, removed: inout Int) throws {
        guard Self.isDir(st) else {
            guard unlinkat(dirfd, name, 0) == 0 else { throw DeletionError.posix(path: path, operation: "unlink", code: errno) }
            removed += 1
            return
        }
        if DeviceID.key(st.st_dev) != device {
            throw DeletionError.posix(path: path, operation: "cross-device", code: EXDEV)
        }
        let fd = openat(dirfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw DeletionError.posix(path: path, operation: "open", code: errno) }
        // The opened directory must be the one we stat'ed.
        var ost = stat()
        guard fstat(fd, &ost) == 0, ost.st_ino == st.st_ino, DeviceID.key(ost.st_dev) == DeviceID.key(st.st_dev) else {
            close(fd)
            throw DeletionError.blocked(path: path, reason: .changedSinceCheck(path))
        }
        // fdopendir takes ownership of a duplicate; keep `fd` for *at calls.
        let names: [String]
        do { names = try Self.listNames(fd: fd, path: path) } catch { close(fd); throw error }
        do {
            for n in names {
                var cst = stat()
                guard fstatat(fd, n, &cst, AT_SYMLINK_NOFOLLOW) == 0 else {
                    if errno == ENOENT { continue }
                    throw DeletionError.posix(path: PathUtil.join(path, n), operation: "lstat", code: errno)
                }
                try remove(dirfd: fd, name: n, path: PathUtil.join(path, n), st: cst, device: device, removed: &removed)
            }
        } catch { close(fd); throw error }
        close(fd)
        guard unlinkat(dirfd, name, AT_REMOVEDIR) == 0 else {
            throw DeletionError.posix(path: path, operation: "rmdir", code: errno)
        }
        removed += 1
    }

    private static func listNames(fd: Int32, path: String) throws -> [String] {
        let dupfd = dup(fd)
        guard dupfd >= 0, let d = fdopendir(dupfd) else {
            let e = errno
            if dupfd >= 0 { close(dupfd) }
            throw DeletionError.posix(path: path, operation: "opendir", code: e)
        }
        defer { closedir(d) }
        let result = DirectoryListing.drain {
            errno = 0
            guard let ent = readdir(d) else { return (nil, errno) }
            let n = withUnsafePointer(to: &ent.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            return (n, 0)
        }
        switch result {
        case .success(let names): return names
        case .failure(let e): throw DeletionError.posix(path: path, operation: "readdir", code: e.code)
        }
    }
}

/// Interface for deleting items the current user cannot remove (root-owned,
/// SIP-adjacent, other users' files). A real implementation would talk to a
/// separately installed, code-signed privileged helper over XPC.
public protocol PrivilegedDeleting: Sendable {
    /// Whether a helper is installed and reachable.
    var isAvailable: Bool { get }
    func deleteItemPrivileged(atPath path: String) async throws
}

/// Placeholder. TODO: implement a privileged helper (e.g. via SMAppService
/// daemon registration + NSXPCConnection with a minimal, path-validated
/// protocol and code-signing requirements on both ends). Intentionally not
/// implemented in this delivery.
public struct UnimplementedPrivilegedDeleter: PrivilegedDeleting {
    public init() {}
    public var isAvailable: Bool { false }
    public func deleteItemPrivileged(atPath path: String) async throws {
        throw DeletionError.privilegedHelperNotImplemented
    }
}

/// The deletion list: a staging list of nodes the user intends to delete.
/// Main-actor isolated: it mutates the shared tree (sizes, children), which
/// the UI reads on the main thread.
@MainActor
public final class DeletionList {
    public private(set) var items: [FileNode] = []
    /// Protection rules; consulted when adding and again right before each deletion.
    public var deletionGuard: DeletionGuard?

    public init(deletionGuard: DeletionGuard? = DeletionGuard.live()) {
        self.deletionGuard = deletionGuard
    }

    /// Why `node` can't be deleted, or nil.
    public func blockedReason(for node: FileNode) -> DeletionGuard.Reason? {
        deletionGuard?.check(node.path)
    }

    /// Extra-confirmation warning for an allowed node, or nil.
    public func caution(for node: FileNode) -> DeletionGuard.Caution? {
        deletionGuard?.caution(for: node.path)
    }

    /// Items not blocked by the guard.
    public var deletableItems: [FileNode] { items.filter { blockedReason(for: $0) == nil } }

    /// Allowed items that need the extra confirmation.
    public var cautionItems: [(node: FileNode, caution: DeletionGuard.Caution)] {
        items.compactMap { n in caution(for: n).map { (n, $0) } }
    }

    public func contains(_ node: FileNode) -> Bool { items.contains { $0 === node } }

    /// Adds a node. If an ancestor is already collected, nothing happens; if
    /// descendants are collected, they are replaced by this node.
    @discardableResult
    public func add(_ node: FileNode) -> Bool {
        if node.parent == nil { return false }           // never collect a scan root
        if blockedReason(for: node) != nil { return false }
        if contains(node) { return false }
        if items.contains(where: { $0.isAncestor(of: node) }) { return false }
        items.removeAll { node.isAncestor(of: $0) }
        items.append(node)
        return true
    }

    public func remove(_ node: FileNode) { items.removeAll { $0 === node } }
    public func removeAll() { items.removeAll() }

    public func totalSize(_ metric: SizeMetric = .actual) -> UInt64 {
        items.reduce(0) { $0 &+ $1.contributedSize(metric) }
    }

    public struct Outcome {
        public var deleted: [FileNode] = []
        public var failed: [(node: FileNode, error: Error)] = []
        public var freedBytes: UInt64 = 0
        /// Items never touched because the run was cancelled.
        public var notAttempted: [FileNode] = []
        public var cancelled = false
        /// Items whose removal started but did not finish (see `partiallyDeleted`).
        public var partial: [FileNode] { failed.compactMap { f in
            if case DeletionError.partiallyDeleted? = f.error as? DeletionError { return f.node }; return nil } }
    }

    /// Deletes every collected item with `deleter`, falling back to
    /// `privileged` (if available) on permission errors. Successfully deleted
    /// nodes are removed from the tree (ancestor sizes updated) and from the list.
    ///
    /// Per item, OFF the main actor: full guard evaluation including the
    /// recursive pre-scan (other devices, SIP/immutable/append flags,
    /// unreadable or read-only folders, sticky-bit ownership refuse the WHOLE
    /// item), then the delete on the guard's canonical path with the (dev,
    /// inode) captured by that evaluation. Tree/list updates happen back on the
    /// main actor. Items with a caution are skipped (`needsConfirmation`)
    /// unless `confirmedCautions`.
    ///
    /// Cancellation is honoured before each item and during its pre-scan,
    /// never in the middle of removing an item. Remaining items are reported
    /// in `notAttempted`.
    public func deleteAll(using deleter: ItemDeleting,
                          privileged: PrivilegedDeleting? = nil,
                          confirmedCautions: Bool = false,
                          cancellation: DeletionCancellation? = nil,
                          progress: (@Sendable (DeletionProgress) -> Void)? = nil) async -> Outcome {
        var outcome = Outcome()
        let snapshot = items
        let gd = deletionGuard
        let stamper = ProgressStamper(progress)
        for (i, node) in snapshot.enumerated() {
            if cancellation?.isCancelled == true {
                outcome.cancelled = true
                outcome.notAttempted = Array(snapshot[i...])
                break
            }
            let path = node.path
            let size = node.contributedSize(.actual)
            stamper.emit(DeletionProgress(phase: .checking, itemIndex: i + 1, itemCount: snapshot.count,
                                          currentPath: path, deletedCount: outcome.deleted.count))
            let result = await Self.deleteOne(path: path, guard: gd, deleter: deleter, privileged: privileged,
                                              confirmedCautions: confirmedCautions, cancellation: cancellation,
                                              stamper: stamper, index: i + 1, count: snapshot.count,
                                              deletedSoFar: outcome.deleted.count)
            switch result {
            case .success:
                node.removeFromTree()
                outcome.deleted.append(node)
                outcome.freedBytes &+= size
            case .failure(DeletionError.cancelled):
                outcome.cancelled = true
                outcome.notAttempted = Array(snapshot[i...])
            case .failure(let error):
                outcome.failed.append((node, error))
            }
            if outcome.cancelled { break }
        }
        stamper.emit(DeletionProgress(phase: .finished, itemIndex: snapshot.count, itemCount: snapshot.count,
                                      currentPath: "", deletedCount: outcome.deleted.count))
        let deletedSet = outcome.deleted.map { ObjectIdentifier($0) }
        items.removeAll { deletedSet.contains(ObjectIdentifier($0)) }
        return outcome
    }
}

/// Progress of `DeletionList.deleteAll` (delivered on a background thread).
public struct DeletionProgress: Sendable, Equatable {
    /// checking = guard pre-scan; verifying = the deleter's own all-or-nothing
    /// re-check; deleting = removal in progress (not cancellable).
    public enum Phase: Sendable, Equatable { case checking, verifying, deleting, finished }
    public var phase: Phase
    /// 1-based index of the current top-level item.
    public var itemIndex: Int
    public var itemCount: Int
    public var currentPath: String
    public var deletedCount: Int
    /// Entries re-checked so far in the current item (verifying phase).
    public var entriesChecked: Int
    /// Strictly increasing per `deleteAll` run; consumers drop anything not
    /// newer than what they already showed (see `ProgressSequencer`).
    public var sequence: Int
    public init(phase: Phase, itemIndex: Int, itemCount: Int, currentPath: String, deletedCount: Int,
                entriesChecked: Int = 0, sequence: Int = 0) {
        self.phase = phase; self.itemIndex = itemIndex; self.itemCount = itemCount
        self.currentPath = currentPath; self.deletedCount = deletedCount
        self.entriesChecked = entriesChecked; self.sequence = sequence
    }
}

/// Stamps progress events with a monotonic sequence number (thread-safe).
public final class ProgressStamper: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0
    private let sink: (@Sendable (DeletionProgress) -> Void)?
    public init(_ sink: (@Sendable (DeletionProgress) -> Void)?) { self.sink = sink }
    public func emit(_ p: DeletionProgress) {
        guard let sink else { return }
        lock.lock()
        next += 1
        var stamped = p
        stamped.sequence = next
        sink(stamped)            // delivered under the lock: callers see sequence order == call order
        lock.unlock()
    }
}

/// Consumer side: accepts only events newer than the last accepted one.
public struct ProgressSequencer: Sendable {
    public private(set) var lastSequence = 0
    public init() {}
    public mutating func accept(_ p: DeletionProgress) -> Bool {
        guard p.sequence > lastSequence else { return false }
        lastSequence = p.sequence
        return true
    }
}

extension DeletionList {
    /// Explicitly OFF the main thread: the work runs in `Task.detached`, which
    /// never inherits the caller's actor in any Swift version or language
    /// mode. (A plain `nonisolated async` function also runs off the main actor
    /// today, but Swift 6.2's NonisolatedNonsendingByDefault would make it
    /// inherit the caller; `@concurrent` would say this directly but needs the
    /// Swift 6.2 compiler, and the Mac toolchain in use is 6.1.2.) The `assert` checks
    /// the guarantee in debug builds; tests check it too.
    nonisolated static func deleteOne(path: String, guard gd: DeletionGuard?, deleter: ItemDeleting,
                                      privileged: PrivilegedDeleting?, confirmedCautions: Bool,
                                      cancellation: DeletionCancellation?, stamper: ProgressStamper,
                                      index: Int, count: Int, deletedSoFar: Int) async -> Result<Void, Error> {
        await Task.detached(priority: .userInitiated) { () async -> Result<Void, Error> in
            assert(!Thread.isMainThread, "deletion work must not run on the main thread")
            return await performOne(path: path, guard: gd, deleter: deleter, privileged: privileged,
                                    confirmedCautions: confirmedCautions, cancellation: cancellation,
                                    stamper: stamper, index: index, count: count, deletedSoFar: deletedSoFar)
        }.value
    }

    nonisolated static func performOne(path: String, guard gd: DeletionGuard?, deleter: ItemDeleting,
                                       privileged: PrivilegedDeleting?, confirmedCautions: Bool,
                                       cancellation: DeletionCancellation?, stamper: ProgressStamper,
                                       index: Int, count: Int, deletedSoFar: Int) async -> Result<Void, Error> {
        var target = path
        var expected: FileIdentity? = nil
        do {
            if let g = gd {
                let v = g.evaluate(path, preflight: true, recursive: deleter.deletesRecursively, cancellation: cancellation)
                if v.reason == .cancelled { throw DeletionError.cancelled }
                if let reason = v.reason { throw DeletionError.blocked(path: path, reason: reason) }
                if let c = v.caution, !confirmedCautions { throw DeletionError.needsConfirmation(path: path, caution: c) }
                target = v.canonicalPath      // decide and delete the SAME path
                expected = v.identity
            }
            stamper.emit(DeletionProgress(phase: .verifying, itemIndex: index, itemCount: count,
                                          currentPath: path, deletedCount: deletedSoFar))
            // A deleter that gets past its re-check does not look at cancellation again.
            let context = DeletionContext(cancellation: cancellation, progress: { n, current in
                stamper.emit(DeletionProgress(phase: .verifying, itemIndex: index, itemCount: count,
                                              currentPath: current, deletedCount: deletedSoFar, entriesChecked: n))
            }, willStartRemoval: {
                stamper.emit(DeletionProgress(phase: .deleting, itemIndex: index, itemCount: count,
                                              currentPath: path, deletedCount: deletedSoFar))
            })
            do {
                try deleter.deleteItem(atPath: target, expected: expected, context: context)
            } catch DeletionError.posix(_, _, let code) where (code == EACCES || code == EPERM) {
                guard let priv = privileged, priv.isAvailable else { throw DeletionError.posix(path: target, operation: "delete", code: code) }
                try await priv.deleteItemPrivileged(atPath: target)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

extension DeletionGuard.Reason {
    /// Maps a subtree finding to a refusal reason.
    public init(_ issue: DeletionGuard.SubtreeIssue) {
        switch issue {
        case .otherDevice(let p): self = .containsOtherDevice(p)
        case .restricted(let p): self = .containsRestricted(p)
        case .unreadable(let p): self = .contentsNotVerifiable(p)
        case .notDeletable(let p, let why): self = .cannotDelete(p, why)
        case .cancelled: self = .cancelled
        }
    }
}
