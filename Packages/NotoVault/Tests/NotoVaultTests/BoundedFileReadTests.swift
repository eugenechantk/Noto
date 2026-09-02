import Foundation
import Testing
@testable import NotoVault

// Test case index
// ---------------
// 1. returnsValueWhenReadCompletesInTime — a fast read yields `.value`.
// 2. returnsFailedWhenReadYieldsNil      — a fast read returning nil yields `.failed`, not `.timedOut`.
// 3. timesOutWhenReadBlocks              — a read that blocks past the budget yields `.timedOut`.
// 4. releasesCallerWhileReadIsStillBlocked — the caller resumes at the deadline, not when the read finally returns.
// 5. abandonedReadResultIsDiscarded      — a read that completes after the timeout does not resume the caller twice.
// 6. concurrentBoundedReadsAllResolve    — many simultaneous blocked reads each resolve independently.

@Suite("BoundedFileRead")
struct BoundedFileReadTests {

    /// A read that finishes inside the budget returns its value.
    @Test
    func returnsValueWhenReadCompletesInTime() async {
        let outcome = await BoundedFileRead.run(timeout: 5) { "note body" }

        guard case .value(let text) = outcome else {
            Issue.record("expected .value, got \(outcome)")
            return
        }
        #expect(text == "note body")
    }

    /// A read that completes but produces nothing is `.failed` — callers use this to
    /// distinguish "file is genuinely unreadable" from "still materializing".
    @Test
    func returnsFailedWhenReadYieldsNil() async {
        let outcome = await BoundedFileRead.run(timeout: 5) { String?.none }

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
    }

    /// The core regression: a read blocked in the kernel (an evicted iCloud file)
    /// must surface as `.timedOut` instead of hanging the caller forever.
    @Test
    func timesOutWhenReadBlocks() async {
        let outcome = await BoundedFileRead.run(timeout: 0.2) {
            Thread.sleep(forTimeInterval: 5)
            return "never observed"
        }

        guard case .timedOut = outcome else {
            Issue.record("expected .timedOut, got \(outcome)")
            return
        }
    }

    /// The caller is released at the deadline — it does not wait out the blocked read.
    @Test
    func releasesCallerWhileReadIsStillBlocked() async {
        let started = Date()
        _ = await BoundedFileRead.run(timeout: 0.2) {
            Thread.sleep(forTimeInterval: 4)
            return "never observed"
        }
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 2, "caller waited \(elapsed)s — it should return at the 0.2s deadline")
    }

    /// A read that finishes *after* the timeout must not resume the continuation a
    /// second time (that would trap).
    @Test
    func abandonedReadResultIsDiscarded() async {
        let outcome = await BoundedFileRead.run(timeout: 0.1) {
            Thread.sleep(forTimeInterval: 0.5)
            return "late"
        }

        guard case .timedOut = outcome else {
            Issue.record("expected .timedOut, got \(outcome)")
            return
        }
        // Give the abandoned worker time to finish and attempt its (dropped) resume.
        try? await Task.sleep(for: .milliseconds(700))
    }

    /// Many blocked reads at once each resolve on their own deadline — a stuck read
    /// must not park the cooperative pool and stall its peers.
    @Test
    func concurrentBoundedReadsAllResolve() async {
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let outcome = await BoundedFileRead.run(timeout: 0.2) {
                        Thread.sleep(forTimeInterval: 3)
                        return "never observed"
                    }
                    if case .timedOut = outcome { return true }
                    return false
                }
            }
            var timedOut = 0
            for await didTimeOut in group where didTimeOut { timedOut += 1 }
            return timedOut
        }

        #expect(outcomes == 12)
    }
}
