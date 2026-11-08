import Foundation

public struct ScanOptions: Sendable {
    /// Enter directories on a different device than the scan root (default: no).
    public var crossFilesystems: Bool = false
    /// Number of worker threads enumerating directories in parallel.
    public var maxConcurrency: Int = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
    /// Minimum seconds between progress callbacks.
    public var progressInterval: TimeInterval = 0.1

    public init(crossFilesystems: Bool = false, maxConcurrency: Int? = nil, progressInterval: TimeInterval = 0.1) {
        self.crossFilesystems = crossFilesystems
        if let m = maxConcurrency { self.maxConcurrency = max(1, m) }
        self.progressInterval = progressInterval
    }
}

public struct ScanProgress: Sendable, Equatable {
    public var directoriesScanned: Int = 0
    public var filesSeen: Int = 0
    public var allocatedBytesSeen: UInt64 = 0
    public var restrictedDirectories: Int = 0
    public var pendingDirectories: Int = 0
    public var lastPath: String = ""
    public var isFinished: Bool = false
}

public struct ScanResult: @unchecked Sendable {
    public let root: FileNode
    public let progress: ScanProgress
    public let hardLinkDuplicates: Int
    /// Files charged only their private bytes because they share blocks with
    /// an earlier member of their APFS clone family.
    public let cloneDuplicates: Int
    /// Allocated bytes not charged thanks to clone dedup.
    public let cloneSharedBytes: UInt64
    public let restrictedPaths: [String]
    public let duration: TimeInterval
}

public enum ScanError: Error, Equatable, Sendable {
    case cancelled
    case rootNotADirectory(String)
    case rootUnreadable(String, EnumeratorError)
}

/// Thread-safe cancellation flag shared between UI and workers.
public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

/// Concurrent directory-tree scanner.
///
/// Design: a shared LIFO work list of directories, drained by
/// `maxConcurrency` worker threads (blocking syscalls stay off the Swift
/// cooperative pool). Each job enumerates one directory, creates the child
/// nodes, attaches them to the parent, and pushes sub-directories back onto
/// the list. When the list is empty and no job is in flight the scan is done;
/// sizes are then aggregated bottom-up in a single post-order pass.
public final class ScanEngine: @unchecked Sendable {
    public let enumerator: DirectoryEnumerator
    public let options: ScanOptions

    public init(enumerator: DirectoryEnumerator = DefaultEnumerator.make(), options: ScanOptions = ScanOptions()) {
        self.enumerator = enumerator
        self.options = options
    }

    // MARK: async API

    /// Scans `path`. Cancelling the calling Task stops the scan and throws `ScanError.cancelled`.
    public func scan(path: String, progress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> ScanResult {
        let token = ScanCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ScanResult, Error>) in
                let thread = Thread {
                    do { cont.resume(returning: try self.scanBlocking(path: path, cancellation: token, progress: progress)) }
                    catch { cont.resume(throwing: error) }
                }
                thread.name = "DiskRings.scan.coordinator"
                thread.start()
            }
        } onCancel: {
            token.cancel()
        }
    }

    // MARK: blocking API

    public func scanBlocking(path rawPath: String, cancellation: ScanCancellation = ScanCancellation(),
                             progress: (@Sendable (ScanProgress) -> Void)? = nil) throws -> ScanResult {
        let start = Date()
        let path = Self.normalize(rawPath)
        let rootEntry: DirectoryEntry
        do { rootEntry = try enumerator.rootEntry(at: path) }
        catch let e as EnumeratorError { throw ScanError.rootUnreadable(path, e) }
        guard rootEntry.kind == .directory else { throw ScanError.rootNotADirectory(path) }

        let root = FileNode(name: path, kind: .directory, device: rootEntry.device,
                            fileID: rootEntry.fileID, linkCount: rootEntry.linkCount)
        let state = SharedState(root: root, rootPath: path, interval: options.progressInterval, callback: progress)
        let hardLinks = HardLinkRegistry()
        let clones = CloneRegistry()

        let workers = max(1, options.maxConcurrency)
        let group = DispatchGroup()
        for i in 0..<workers {
            group.enter()
            let t = Thread { [self] in
                self.workerLoop(state: state, hardLinks: hardLinks, clones: clones, rootDevice: rootEntry.device, cancellation: cancellation)
                group.leave()
            }
            t.name = "DiskRings.scan.worker.\(i)"
            t.stackSize = 1 << 20
            t.start()
        }
        group.wait()

        if cancellation.isCancelled { throw ScanError.cancelled }
        if root.isRestricted, root.children.isEmpty, let first = state.restricted.first, first == path {
            throw ScanError.rootUnreadable(path, state.rootError ?? .posix(path: path, code: 13))
        }
        clones.resolve()
        root.aggregate()
        var final = state.snapshot()
        final.isFinished = true
        progress?(final)
        return ScanResult(root: root, progress: final, hardLinkDuplicates: hardLinks.duplicateCount,
                          cloneDuplicates: clones.duplicateCount, cloneSharedBytes: clones.sharedBytes,
                          restrictedPaths: state.restricted, duration: Date().timeIntervalSince(start))
    }

    private func workerLoop(state: SharedState, hardLinks: HardLinkRegistry, clones: CloneRegistry, rootDevice: UInt64, cancellation: ScanCancellation) {
        while let job = state.next(cancellation: cancellation) {
            var newJobs: [Job] = []
            var files = 0
            var bytes: UInt64 = 0
            var restricted = false
            do {
                let entries = try enumerator.entries(inDirectoryAt: job.path)
                var nodes: [FileNode] = []
                nodes.reserveCapacity(entries.count)
                for e in entries {
                    let node = FileNode(name: e.name, kind: e.kind, device: e.device, fileID: e.fileID,
                                        linkCount: e.linkCount, logicalSize: e.logicalSize, allocatedSize: e.allocatedSize,
                                        cloneID: e.cloneID)
                    switch e.kind {
                    case .directory:
                        let foreign = e.isMountPoint || e.device != rootDevice
                        if foreign && !options.crossFilesystems {
                            node.markOtherFilesystem()
                        } else {
                            newJobs.append(Job(node: node, path: PathUtil.join(job.path, e.name)))
                        }
                    case .file:
                        files += 1
                        if e.linkCount > 1,
                           !hardLinks.registerFirstSighting(device: e.device, inode: e.fileID) {
                            // Extra hard link: contributes 0 to everything; never
                            // consults the clone registry (no double subtraction).
                            node.markHardLinkDuplicate()
                        } else {
                            if let cid = e.cloneID {
                                // Decided after the scan, deterministically (see CloneRegistry).
                                clones.add(node: node, device: e.device, cloneID: cid, fileID: e.fileID,
                                           privateSize: e.privateSize, eligible: e.mayShareBlocks)
                            }
                            bytes &+= e.allocatedSize   // progress only; final sizes come from aggregate()
                        }
                    case .symlink, .other:
                        files += 1
                        bytes &+= e.allocatedSize
                    }
                    nodes.append(node)
                }
                // Attach children BEFORE publishing sub-jobs, so no other worker
                // can observe a half-built directory.
                job.node.setChildren(nodes)
            } catch {
                job.node.markRestricted()
                restricted = true
                if job.node === state.root, let e = error as? EnumeratorError { state.rootError = e }
            }
            state.finish(job: job, newJobs: newJobs, files: files, bytes: bytes, restricted: restricted)
        }
    }

    static func normalize(_ p: String) -> String {
        var s = p
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? "/" : s
    }

    // MARK: - Shared work list

    struct Job {
        let node: FileNode
        let path: String
    }

    final class SharedState: @unchecked Sendable {
        let root: FileNode
        private let cond = NSCondition()
        private var stack: [Job]
        private var inFlight = 0
        private var progress = ScanProgress()
        private(set) var restricted: [String] = []
        var rootError: EnumeratorError?
        private var lastReport = Date.distantPast
        private let interval: TimeInterval
        private let callback: (@Sendable (ScanProgress) -> Void)?

        init(root: FileNode, rootPath: String, interval: TimeInterval, callback: (@Sendable (ScanProgress) -> Void)?) {
            self.root = root
            self.stack = [Job(node: root, path: rootPath)]
            self.interval = interval
            self.callback = callback
        }

        /// Blocks until a job is available; returns nil when the scan is complete or cancelled.
        func next(cancellation: ScanCancellation) -> Job? {
            cond.lock(); defer { cond.unlock() }
            while true {
                if cancellation.isCancelled { cond.broadcast(); return nil }
                if let j = stack.popLast() { inFlight += 1; return j }
                if inFlight == 0 { cond.broadcast(); return nil }
                // Timed wait so cancellation is noticed even while idle.
                _ = cond.wait(until: Date().addingTimeInterval(0.05))
            }
        }

        func finish(job: Job, newJobs: [Job], files: Int, bytes: UInt64, restricted isRestricted: Bool) {
            var report: ScanProgress?
            cond.lock()
            inFlight -= 1
            stack.append(contentsOf: newJobs.reversed())
            progress.directoriesScanned += 1
            progress.filesSeen += files
            progress.allocatedBytesSeen &+= bytes
            if isRestricted { progress.restrictedDirectories += 1; restricted.append(job.path) }
            progress.pendingDirectories = stack.count + inFlight
            progress.lastPath = job.path
            if callback != nil {
                let now = Date()
                if now.timeIntervalSince(lastReport) >= interval { lastReport = now; report = progress }
            }
            if !newJobs.isEmpty || (stack.isEmpty && inFlight == 0) { cond.broadcast() }
            cond.unlock()
            if let r = report { callback?(r) }
        }

        func snapshot() -> ScanProgress {
            cond.lock(); defer { cond.unlock() }
            return progress
        }
    }
}
