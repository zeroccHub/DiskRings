import Foundation

/// Serialises background tree READERS against main-actor tree MUTATIONS (deletion's
/// `FileNode.removeFromTree`, which edits `children` arrays and ancestor sizes in place).
///
/// Protocol (cancel + await, then re-run):
///   • a background reader (whole-tree search, TreeAnalysis) must obtain a ticket with
///     `beginRead(cancel:)` BEFORE it starts and call `endRead` when it has stopped touching
///     the tree; `beginRead` returns nil while a mutation is pending or running → the reader
///     must not start (callers re-run it after the mutation)
///   • a mutator calls `await beginMutation()` — it blocks new readers, cancels every active
///     one and suspends until all have called `endRead` — then mutates, then `endMutation()`
///   • one mutation at a time (the app's ActivityState already allows only one deletion)
/// Readers poll their cancellation every few thousand nodes, so the wait is short (ms).
public final class TreeAccessGate: @unchecked Sendable {
    public struct Ticket: Sendable, Hashable { let id: Int }
    private let lock = NSLock()
    private var readers: [Int: @Sendable () -> Void] = [:]
    private var nextID = 0
    private var mutating = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Diagnostics/tests: readers granted / refused, mutations completed.
    public private(set) var granted = 0, refused = 0, mutations = 0

    public init() {}

    public var activeReaders: Int { lock.lock(); defer { lock.unlock() }; return readers.count }
    public var isMutating: Bool { lock.lock(); defer { lock.unlock() }; return mutating }

    /// nil while a mutation is pending/running: do not read the tree.
    public func beginRead(cancel: @escaping @Sendable () -> Void) -> Ticket? {
        lock.lock(); defer { lock.unlock() }
        guard !mutating else { refused += 1; return nil }
        nextID += 1
        readers[nextID] = cancel
        granted += 1
        return Ticket(id: nextID)
    }

    /// The reader has stopped touching the tree (finished or cancelled). Idempotent.
    public func endRead(_ t: Ticket) {
        lock.lock()
        readers[t.id] = nil
        var resume: [CheckedContinuation<Void, Never>] = []
        if mutating && readers.isEmpty { resume = waiters; waiters = [] }
        lock.unlock()
        resume.forEach { $0.resume() }
    }

    /// Blocks new readers, cancels the active ones and returns once none is left.
    public func beginMutation() async {
        let cancels: [@Sendable () -> Void] = {
            lock.lock(); defer { lock.unlock() }
            precondition(!mutating, "TreeAccessGate: one mutation at a time")
            mutating = true
            return Array(readers.values)
        }()
        cancels.forEach { $0() }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if readers.isEmpty { lock.unlock(); c.resume() } else { waiters.append(c); lock.unlock() }
        }
    }

    /// Mutation finished: readers may start again.
    public func endMutation() {
        lock.lock(); mutating = false; mutations += 1; lock.unlock()
    }
}
