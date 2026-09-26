import Foundation

/// Runs the share-capture drain one pass at a time.
///
/// A cold launch through the share sheet's "Keep editing" link calls the drain
/// from three places at once (launch, activation, the link itself). Concurrent
/// passes raced: the one that had not recorded the requested capture could
/// finish first and give up on opening it (bug 036). Here a call while a pass
/// is running asks for exactly one more pass after it — so a capture staged
/// mid-pass is still filed — and every caller returns only once no pass is left.
/// Calls that arrive before a queued pass has started simply share it.
@MainActor
final class SharedCaptureDrainQueue {
    private var running: Task<Void, Never>?
    private var needsAnotherPass = false

    var isRunning: Bool { running != nil }
    /// A call arrived while a pass was running; one more pass will follow it.
    var hasPendingPass: Bool { needsAnotherPass }

    func run(_ pass: @escaping @MainActor () async -> Void) async {
        if running != nil {
            needsAnotherPass = true
        } else {
            running = Task { @MainActor in
                repeat {
                    needsAnotherPass = false
                    await pass()
                } while needsAnotherPass
                running = nil
            }
        }
        while let current = running {
            await current.value
        }
    }
}
