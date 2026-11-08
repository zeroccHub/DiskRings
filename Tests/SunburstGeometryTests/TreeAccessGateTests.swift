import XCTest
@testable import SunburstGeometry
@testable import DiskScanCore

/// Background tree readers (TreeSearch, TreeAnalysis) vs. in-place deletion edits
/// (`FileNode.removeFromTree`), coordinated by TreeAccessGate. Meant to run under
/// `swift test --sanitize=thread`: any reader touching the tree during a mutation is a
/// reported data race.
final class TreeAccessGateTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        let lock = NSLock(); var active = 0, maxDuringMutation = 0, runs = 0, refused = 0
        func enter(_ mutating: Bool) { lock.lock(); active += 1; if mutating { maxDuringMutation = max(maxDuringMutation, active) }; lock.unlock() }
        func leave() { lock.lock(); active -= 1; runs += 1; lock.unlock() }
        func refuse() { lock.lock(); refused += 1; lock.unlock() }
    }

    func testMutationWaitsForReadersAndBlocksNewOnes() async {
        let gate = TreeAccessGate()
        let cancelled = TreeSearch.Token()
        let t = gate.beginRead(cancel: { cancelled.cancel() })!
        let mutationStarted = expectation(description: "mutation began")
        let task = Task { await gate.beginMutation(); mutationStarted.fulfill() }
        // The reader was cancelled, new readers are refused, the mutation still waits.
        for _ in 0..<200 where !cancelled.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertNil(gate.beginRead(cancel: {}))
        XCTAssertEqual(gate.activeReaders, 1)
        gate.endRead(t)
        await fulfillment(of: [mutationStarted], timeout: 5)
        _ = await task.value
        XCTAssertTrue(gate.isMutating)
        gate.endMutation()
        XCTAssertNotNil(gate.beginRead(cancel: {}), "readers allowed again")
        XCTAssertEqual(gate.mutations, 1)
    }

    /// Many interleavings of searches + analyses + deletions on one tree.
    func testStressSearchAndAnalysisAgainstDeletion() async {
        let root = SyntheticTree.build(targetNodes: 40_000)
        let gate = TreeAccessGate()
        let counter = Counter()
        let iterations = 60
        // Leaves to delete, picked up front (like a delete zone).
        var victims: [FileNode] = []
        var stack = [root]
        while let n = stack.popLast() { if n.children.isEmpty { victims.append(n) } else { stack.append(contentsOf: n.children) } }
        victims = stride(from: 0, to: victims.count, by: max(1, victims.count / (iterations * 20))).map { victims[$0] }

        let group = DispatchGroup()
        let stop = TreeSearch.Token()
        // 4 reader loops: search / analysis, each starting only with a ticket.
        for r in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                while !stop.isCancelled {
                    let token = TreeSearch.Token()
                    guard let ticket = gate.beginRead(cancel: { token.cancel() }) else { counter.refuse(); usleep(50); continue }
                    counter.enter(gate.isMutating)
                    if r % 2 == 0 {
                        _ = TreeSearch.run(root: root, query: ["cache", "f1", "Music"][r % 3], token: token)
                    } else {
                        _ = TreeAnalysis.build(root: root, homeDirectory: "/Users/tester", isCancelled: { token.isCancelled })
                    }
                    counter.leave()
                    gate.endRead(ticket)
                }
                group.leave()
            }
        }
        // Mutator (the app does this on the main actor around DeletionList.deleteAll).
        var removed = 0
        for i in 0..<iterations {
            await gate.beginMutation()
            XCTAssertEqual(gate.activeReaders, 0)
            for v in victims[(i * victims.count / iterations)..<((i + 1) * victims.count / iterations)] where v.removeFromTree() {
                removed += 1
            }
            gate.endMutation()
            try? await Task.sleep(nanoseconds: 200_000)        // let readers run between deletions
        }
        stop.cancel()
        group.wait()
        XCTAssertEqual(counter.maxDuringMutation, 0, "no reader active while the tree was mutated")
        XCTAssertGreaterThan(counter.runs, iterations / 2)
        XCTAssertGreaterThan(removed, iterations)
        XCTAssertEqual(gate.mutations, iterations)
        // Removed nodes are really gone and every remaining parent link is intact.
        XCTAssertEqual(victims.filter { $0.parent == nil }.count, removed)
        print("GATE stress: \(iterations) mutations, \(removed) removed, \(counter.runs) reader runs, \(counter.refused) refused")
    }
}
