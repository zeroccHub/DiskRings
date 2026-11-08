import XCTest
@testable import DiskScanCore
#if canImport(Glibc)
import Glibc
#endif

final class AppActivityTests: XCTestCase {
    func testCommandGatingAndQuitDuringDeletion() {
        let a = AppActivity()
        XCTAssertTrue(a.isAllowed(.scan)); XCTAssertTrue(a.isAllowed(.delete)); XCTAssertFalse(a.isAllowed(.stopScan))
        XCTAssertEqual(a.requestTermination(), .now)

        XCTAssertTrue(a.beginScan())
        XCTAssertTrue(a.isAllowed(.scan), "a new scan restarts the running one"); XCTAssertTrue(a.isAllowed(.stopScan))
        XCTAssertFalse(a.isAllowed(.delete)); XCTAssertFalse(a.beginDeletion(), "no delete while scanning")
        a.endScan()

        XCTAssertTrue(a.beginDeletion())
        for c in [AppActivity.Command.scan, .rescan, .editDeletionList, .delete] { XCTAssertFalse(a.isAllowed(c), "\(c)") }
        XCTAssertFalse(a.beginScan(), "no scan/rescan/open while deleting")
        XCTAssertFalse(a.beginDeletion(), "no second deletion")
        XCTAssertEqual(a.requestTermination(), .later, "Cmd-Q while deleting -> terminateLater")
        XCTAssertTrue(a.quitPending); XCTAssertTrue(a.isAllowed(.quit), "R6 7D: Quit stays enabled (disabled Quit beeps)")
        XCTAssertEqual(a.endDeletion(), .replyTerminate, "reply(toApplicationShouldTerminate: true) after the deletion stops")
        XCTAssertFalse(a.quitPending)
        XCTAssertTrue(a.isAllowed(.scan))

        XCTAssertTrue(a.beginDeletion())
        XCTAssertEqual(a.endDeletion(), .none, "no quit requested")
    }
}

final class ACLAndTCCTests: XCTestCase {
    var base = ""
    let fm = FileManager.default
    override func setUpWithError() throws {
        base = NSTemporaryDirectory() + "dr5fix-\(UUID().uuidString)"
        try fm.createDirectory(atPath: base + "/v/sub", withIntermediateDirectories: true)
        for i in 0..<5 { _ = fm.createFile(atPath: base + "/v/f\(i)", contents: Data([1])) }
        _ = fm.createFile(atPath: base + "/v/sub/x", contents: Data([1]))
    }
    override func tearDown() { try? fm.removeItem(atPath: base) }
    func count() -> Int { (fm.subpaths(atPath: base + "/v") ?? []).count }

    func testACLDenyDeleteOnEntryRefusesWholeItem() throws {
        let target = base + "/v/sub/x"
        let c = DeletabilityChecker(flags: { _ in 0 }, aclDenies: { p, k in p == target && k == .deleteSelf })
        guard case .notDeletable(let p, let why)? = c.check(base + "/v", recursive: true) else { return XCTFail() }
        XCTAssertEqual(p, target); XCTAssertTrue(why.contains("ACL"))
        let before = count()
        XCTAssertThrowsError(try PosixRecursiveDeleter(checker: c).deleteItem(atPath: base + "/v"))
        XCTAssertEqual(count(), before)
    }

    func testACLDenyDeleteChildOnFolderAndOnTopParent() {
        let c = DeletabilityChecker(flags: { _ in 0 }, aclDenies: { [base] p, k in p == base + "/v/sub" && k == .deleteChild })
        guard case .notDeletable(let p, let why)? = c.check(base + "/v", recursive: true) else { return XCTFail() }
        XCTAssertEqual(p, base + "/v/sub"); XCTAssertTrue(why.contains("delete_child"))
        // delete_child deny on the TOP item's parent blocks even a Trash move.
        let top = DeletabilityChecker(flags: { _ in 0 }, aclDenies: { [base] p, k in p == base && k == .deleteChild })
        XCTAssertNotNil(top.check(base + "/v", recursive: false))
        // A delete deny on an unrelated kind/path does nothing.
        let none = DeletabilityChecker(flags: { _ in 0 }, aclDenies: { [base] p, k in p == base + "/v/sub" && k == .deleteSelf && false })
        XCTAssertNil(none.check(base + "/v", recursive: true))
    }

    func testEPERMIsClassifiedAsFullDiskAccess() {
        let c = DeletabilityChecker(flags: { _ in 0 }, listDirectory: { [base] p in
            p == base + "/v/sub" ? .failure(DirectoryReadError(code: EPERM, atOpen: true)) : DirectoryListing.names(atPath: p)
        })
        guard case .notDeletable(let p, let why)? = c.check(base + "/v", recursive: true) else { return XCTFail() }
        XCTAssertEqual(p, base + "/v/sub")
        XCTAssertTrue(why.contains("Full Disk Access")); XCTAssertTrue(why.contains("Privacy & Security"))
        XCTAssertEqual(DeletionGuard.Reason(.notDeletable(p, why)).description.contains("Full Disk Access"), true)
        XCTAssertTrue(DeletionError.posix(path: "/x", operation: "unlink", code: EPERM).description.contains("Full Disk Access"))
    }

    func testReaddirErrorMidListingIsNotEndOfFolder() {
        // drain: NULL with errno == 0 -> end; NULL with errno != 0 -> error.
        var steps: [(String?, Int32)] = [(".", 0), ("a", 0), ("b", 0), (nil, 0)]
        XCTAssertEqual(try DirectoryListing.drain { steps.removeFirst() }.get(), ["a", "b"])
        steps = [("a", 0), (nil, EIO)]
        XCTAssertEqual(DirectoryListing.drain { steps.removeFirst() }, .failure(DirectoryReadError(code: EIO)))
        // The checker treats a read error as "can't be deleted" (not as an empty/complete folder).
        let c = DeletabilityChecker(flags: { _ in 0 }, listDirectory: { [base] p in
            p == base + "/v/sub" ? .failure(DirectoryReadError(code: EIO)) : DirectoryListing.names(atPath: p)
        })
        guard case .notDeletable(let p, let why)? = c.check(base + "/v", recursive: true) else { return XCTFail() }
        XCTAssertEqual(p, base + "/v/sub"); XCTAssertTrue(why.contains("could not be read completely"))
        // The scan enumerator surfaces a listing failure as an error, too.
        XCTAssertThrowsError(try PosixDirectoryEnumerator().entries(inDirectoryAt: base + "/does-not-exist"))
    }

    func testParentChecksAreCachedPerFolder() {
        final class Counter: @unchecked Sendable { let l = NSLock(); var n: [String: Int] = [:]
            func hit(_ p: String) { l.lock(); n[p, default: 0] += 1; l.unlock() } }
        let cw = Counter(), acl = Counter()
        let c = DeletabilityChecker(flags: { _ in 0 }, canWriteAndSearch: { cw.hit($0); return true },
                                    aclDenies: { p, k in if k == .deleteChild { acl.hit(p) }; return false })
        XCTAssertNil(c.check(base + "/v", recursive: true))
        XCTAssertEqual(cw.n[base + "/v"], 1, "5 files + 1 folder in /v, but one write check")
        XCTAssertEqual(acl.n[base + "/v"], 1)
        XCTAssertEqual(cw.n[base], 1, "parent of the top item checked once")
    }

    func testDeleterRecheckIsCancellableAndReportsProgress() throws {
        let big = base + "/big"
        try fm.createDirectory(atPath: big, withIntermediateDirectories: true)
        for i in 0..<600 { _ = fm.createFile(atPath: big + "/f\(i)", contents: Data([1])) }
        // Cancelled before/while re-checking: nothing removed, `.cancelled` thrown.
        let tok = DeletionCancellation(); tok.cancel()
        XCTAssertThrowsError(try PosixRecursiveDeleter().deleteItem(atPath: big, expected: nil,
                                                                   context: DeletionContext(cancellation: tok))) {
            XCTAssertEqual($0 as? DeletionError, .cancelled)
        }
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: big))?.count, 600)
        // Progress during the re-check, then exactly one willStartRemoval.
        final class Log: @unchecked Sendable { let l = NSLock(); var counts: [Int] = []; var starts = 0 }
        let log = Log()
        try PosixRecursiveDeleter().deleteItem(atPath: big, expected: nil, context: DeletionContext(
            progress: { n, _ in log.l.lock(); log.counts.append(n); log.l.unlock() },
            willStartRemoval: { log.l.lock(); log.starts += 1; log.l.unlock() }))
        XCTAssertEqual(log.counts, [256, 512, 600])
        XCTAssertEqual(log.starts, 1)
        XCTAssertFalse(fm.fileExists(atPath: big))
    }
}

final class ProgressOrderingTests: XCTestCase {
    func testStamperIsMonotonicAcrossThreadsAndSequencerDropsStale() {
        final class Sink: @unchecked Sendable { let l = NSLock(); var seqs: [Int] = [] }
        let sink = Sink()
        let stamper = ProgressStamper { p in sink.l.lock(); sink.seqs.append(p.sequence); sink.l.unlock() }
        DispatchQueue.concurrentPerform(iterations: 500) { i in
            stamper.emit(DeletionProgress(phase: .checking, itemIndex: i, itemCount: 500, currentPath: "", deletedCount: 0))
        }
        XCTAssertEqual(sink.seqs, Array(1...500), "delivery order == sequence order")
        var seq = ProgressSequencer()
        func p(_ n: Int) -> DeletionProgress { DeletionProgress(phase: .checking, itemIndex: 1, itemCount: 1, currentPath: "", deletedCount: 0, sequence: n) }
        XCTAssertTrue(seq.accept(p(1))); XCTAssertTrue(seq.accept(p(3)))
        XCTAssertFalse(seq.accept(p(2)), "stale event dropped"); XCTAssertFalse(seq.accept(p(3)))
        XCTAssertTrue(seq.accept(p(4))); XCTAssertEqual(seq.lastSequence, 4)
    }

    @MainActor
    func testDeleteAllEventsAreStrictlyOrderedAndPhasesSensible() async throws {
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/Users/tester/d",
            ["a", "b", "c"].map { .file(name: $0, size: 1) }), options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/Users/tester/d")
        let l = DeletionList(deletionGuard: DeletionGuard(homeDirectory: "/Users/tester"))
        for n in r.root.children.sorted(by: { $0.name < $1.name }) { _ = l.add(n) }
        final class Ev: @unchecked Sendable { let lk = NSLock(); var list: [DeletionProgress] = [] }
        final class D: ItemDeleting, @unchecked Sendable { func deleteItem(atPath path: String) throws {} }
        let ev = Ev()
        _ = await l.deleteAll(using: D(), progress: { p in ev.lk.lock(); ev.list.append(p); ev.lk.unlock() })
        XCTAssertEqual(ev.list.map(\.sequence), Array(1...ev.list.count))
        XCTAssertEqual(ev.list.map(\.phase), [.checking, .verifying, .deleting, .checking, .verifying, .deleting,
                                              .checking, .verifying, .deleting, .finished])
        _ = r
    }

    func testStreamConsumerSeesOrderedEvents() async {
        // The app pattern: callback -> AsyncStream continuation -> one consumer + sequencer.
        let (stream, cont) = AsyncStream<DeletionProgress>.makeStream()
        let stamper = ProgressStamper { cont.yield($0) }
        let producer = Task.detached {
            for i in 0..<200 { stamper.emit(DeletionProgress(phase: .checking, itemIndex: i, itemCount: 200, currentPath: "", deletedCount: 0)) }
            cont.finish()
        }
        var seq = ProgressSequencer(); var accepted: [Int] = []
        for await p in stream where seq.accept(p) { accepted.append(p.sequence) }
        await producer.value
        XCTAssertEqual(accepted, Array(1...200))
    }
}

final class OffMainTests: XCTestCase {
    @MainActor
    func testDeleteOneRunsOffMainEvenWhenCalledFromMainActor() async {
        XCTAssertTrue(Thread.isMainThread)
        final class D: ItemDeleting, @unchecked Sendable { var main: Bool?; func deleteItem(atPath path: String) throws { main = Thread.isMainThread } }
        let d = D()
        let r = await DeletionList.deleteOne(path: "/Users/tester/x", guard: nil, deleter: d, privileged: nil,
                                             confirmedCautions: false, cancellation: nil, stamper: ProgressStamper(nil),
                                             index: 1, count: 1, deletedSoFar: 0)
        XCTAssertNoThrow(try r.get())
        XCTAssertEqual(d.main, false)
        XCTAssertTrue(Thread.isMainThread, "back on the main actor afterwards")
    }
}

/// R6 7D (P2): Cmd-Q during a delete beeped and showed no "Quitting…".
final class QuitDuringDeleteTests: XCTestCase {
    func testMenuPolicyQuitAlwaysAllowedEverythingElseBlockedWhileDeleting() {
        let a = AppActivity()
        XCTAssertTrue(a.beginDeletion())
        XCTAssertTrue(a.validate(.quit), "terminate: must stay enabled during a delete")
        XCTAssertTrue(a.validate(nil), "standard items unaffected")
        for c in [AppActivity.Command.scan, .rescan, .editDeletionList, .delete, .stopScan] {
            XCTAssertFalse(a.validate(c), "\(c) blocked while deleting")
        }
        XCTAssertEqual(a.requestTermination(), .later)
        XCTAssertTrue(a.validate(.quit), "still enabled while a quit is pending (a disabled Quit beeps)")
        XCTAssertEqual(a.quitKeyAction(), .alreadyQuitting, "repeat Cmd-Q is swallowed, not re-sent")
        XCTAssertEqual(a.requestTermination(), .later, "idempotent")
        XCTAssertEqual(a.endDeletion(), .replyTerminate)
        XCTAssertEqual(a.endDeletion(), .none, "reply sent exactly once")
        XCTAssertEqual(a.quitKeyAction(), .terminate)
        XCTAssertTrue(AppActivity.Command.allCases.allSatisfy { a.validate($0) || $0 == .stopScan })
    }

    @MainActor
    func testQuitMidRunFinishesCurrentItemSkipsRestRepliesOnce() async throws {
        try await runQuit(userCancelledFirst: false)
    }

    @MainActor
    func testQuitAfterUserCancelAlsoReplies() async throws {
        try await runQuit(userCancelledFirst: true)
    }

    @MainActor
    private func runQuit(userCancelledFirst: Bool) async throws {
        let r = try ScanEngine(enumerator: InMemoryDirectoryEnumerator(rootPath: "/Users/tester/d",
            ["a", "b", "c", "d"].map { .file(name: $0, size: 1) }), options: ScanOptions(maxConcurrency: 1)).scanBlocking(path: "/Users/tester/d")
        let l = DeletionList(deletionGuard: DeletionGuard(homeDirectory: "/Users/tester"))
        for n in r.root.children.sorted(by: { $0.name < $1.name }) { _ = l.add(n) }
        let activity = AppActivity(); let tok = DeletionCancellation()
        XCTAssertTrue(activity.beginDeletion())
        final class D: ItemDeleting, @unchecked Sendable {
            let lk = NSLock(); var calls: [String] = []; var onB: (() -> Void)?
            func deleteItem(atPath path: String) throws {
                lk.lock(); calls.append(path); lk.unlock()
                if path.hasSuffix("/b") { onB?() }
            }
        }
        let d = D()
        // Cmd-Q arrives while item "b" is being removed (what shouldTerminate does).
        d.onB = {
            if userCancelledFirst { tok.cancel() }
            DispatchQueue.main.sync {
                XCTAssertEqual(activity.requestTermination(), .later)
                tok.cancel()
            }
        }
        let out = await l.deleteAll(using: d, cancellation: tok)
        var replies = 0
        if activity.endDeletion() == .replyTerminate { replies += 1 }
        if activity.endDeletion() == .replyTerminate { replies += 1 }
        XCTAssertEqual(out.deleted.map(\.name), ["a", "b"], "current item completes")
        XCTAssertEqual(out.notAttempted.map(\.name), ["c", "d"], "remaining items not run")
        XCTAssertEqual(d.calls.count, 2)
        XCTAssertTrue(out.cancelled)
        XCTAssertEqual(replies, 1, "reply(toApplicationShouldTerminate:) exactly once")
        _ = r
    }
}
