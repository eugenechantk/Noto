import Foundation

/// Result of a time-bounded blocking filesystem read.
public enum BoundedReadOutcome<Value: Sendable>: Sendable {
    /// The read completed and produced a value.
    case value(Value)
    /// The read completed but produced nothing (missing file, bad encoding, …).
    case failed
    /// The read did not finish within the budget and was abandoned.
    case timedOut
}

/// Runs a *blocking* filesystem read off the Swift concurrency cooperative pool and
/// abandons it after a deadline.
///
/// Two problems this exists to solve, both seen on an iCloud Drive vault whose files
/// have been evicted (`dataless`):
///
/// 1. Reading a dataless file blocks in the kernel until the file provider
///    materializes it. If the provider is wedged or backlogged that never happens, so
///    an unbounded read leaves the caller hung forever with no way out.
/// 2. `Task.detached` runs on the cooperative pool, which is sized to the core count
///    and does **not** grow to cover blocked threads — a handful of stuck reads starve
///    every other async operation in the app.
///
/// The work closure is dispatched to the (overcommitting) global queue, so a stuck
/// read parks a disposable pool thread instead of a cooperative one. The thread stays
/// parked until the kernel finally returns; it cannot be cancelled, but the caller is
/// released at the deadline and its result is discarded.
public enum BoundedFileRead {
    /// - Parameters:
    ///   - timeout: how long to wait before giving up on `work`.
    ///   - qos: quality of service for the thread running `work`.
    ///   - work: the blocking read. Must be safe to abandon — its result is dropped on timeout.
    public static func run<Value: Sendable>(
        timeout: TimeInterval,
        qos: DispatchQoS.QoSClass = .userInitiated,
        work: @escaping @Sendable () -> Value?
    ) async -> BoundedReadOutcome<Value> {
        let box = ResumeOnce<Value>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<BoundedReadOutcome<Value>, Never>) in
            box.attach(continuation)
            DispatchQueue.global(qos: qos).async {
                let value = work()
                box.finish(value.map { BoundedReadOutcome.value($0) } ?? .failed)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                box.finish(.timedOut)
            }
        }
    }
}

/// Guarantees the continuation is resumed exactly once, whichever of the read and the
/// deadline lands first. `attach` always runs before either racer is dispatched, so a
/// `finish` can never arrive with no continuation to resume.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<BoundedReadOutcome<Value>, Never>?

    func attach(_ continuation: CheckedContinuation<BoundedReadOutcome<Value>, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ outcome: BoundedReadOutcome<Value>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: outcome)
    }
}
