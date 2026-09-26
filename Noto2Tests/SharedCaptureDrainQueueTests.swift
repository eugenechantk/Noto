import Testing
@testable import Noto2

/// Test case index
/// 1. concurrentCallsNeverOverlap — a call while a pass runs waits; the drain never runs twice at once (bug 036)
/// 2. callsDuringARunCoalesceIntoOneMorePass — three calls while a pass runs → exactly one more pass, not three
/// 3. everyCallerReturnsAfterTheLastPass — a caller that joined mid-pass returns only after the follow-up pass
/// 4. idleQueueRunsImmediately — with nothing running, one call is one pass
///
/// The first pass is held open by a `Gate`, so "while a pass runs" is exact
/// rather than a timing guess.
@MainActor
struct SharedCaptureDrainQueueTests {
    @Test func concurrentCallsNeverOverlap() async {
        let queue = SharedCaptureDrainQueue()
        let probe = Probe()
        let gate = Gate()
        let work = probe.pass(holdingFirstOn: gate)

        let first = Task { await queue.run(work) }
        await until { probe.passes == 1 }
        let second = Task { await queue.run(work) }
        await until { queue.hasPendingPass }
        gate.open()
        await first.value
        await second.value

        #expect(probe.maxActive == 1)
        #expect(probe.passes == 2)
    }

    @Test func callsDuringARunCoalesceIntoOneMorePass() async {
        let queue = SharedCaptureDrainQueue()
        let probe = Probe()
        let gate = Gate()
        let work = probe.pass(holdingFirstOn: gate)

        let first = Task { await queue.run(work) }
        await until { probe.passes == 1 }
        let joiners = (0..<3).map { _ in Task { await queue.run(work) } }
        for _ in 0..<5 { await Task.yield() }
        gate.open()
        await first.value
        for joiner in joiners { await joiner.value }

        #expect(probe.passes == 2)
    }

    @Test func everyCallerReturnsAfterTheLastPass() async {
        let queue = SharedCaptureDrainQueue()
        let probe = Probe()
        let gate = Gate()
        let work = probe.pass(holdingFirstOn: gate)

        let first = Task { await queue.run(work) }
        await until { probe.passes == 1 }
        let late = Task {
            await queue.run(work)
            return probe.passes
        }
        await until { queue.hasPendingPass }
        gate.open()

        // The late caller joined during pass 1, so it may only return after pass 2.
        #expect(await late.value == 2)
        await first.value
        #expect(!queue.isRunning)
    }

    @Test func idleQueueRunsImmediately() async {
        let queue = SharedCaptureDrainQueue()
        let probe = Probe()
        await queue.run { probe.passes += 1 }
        #expect(probe.passes == 1)
        #expect(!queue.isRunning)
    }

    /// Yields to the main actor until `condition` holds (bounded, so a bug fails instead of hanging).
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
    }
}

@MainActor
private final class Probe {
    var active = 0
    var maxActive = 0
    var passes = 0

    /// A pass that records overlap and, the first time, waits for `gate`.
    func pass(holdingFirstOn gate: Gate) -> @MainActor () async -> Void {
        { [self] in
            active += 1
            maxActive = max(maxActive, active)
            passes += 1
            if passes == 1 { await gate.wait() }
            active -= 1
        }
    }
}

@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
