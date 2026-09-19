import Foundation
import NotoShareCapture
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "SharedCaptureDrain")

/// Files the captures the share extension staged in the App Group into the
/// vault's `inbox/`, through the same `CaptureFilingService` the Capture tab
/// uses. The extension cannot reach the vault itself (see `PendingCaptureStore`),
/// so the app runs this whenever it becomes active with a resolved vault.
///
/// Each staged capture is filed under the moment it was shared, and removed
/// from the staging folder only after the vault write succeeded — a failed
/// write costs a retry on the next drain, never the link.
struct SharedCaptureDrain {
    /// Posted on the main thread after a drain filed at least one capture, so
    /// screens already showing `inbox/` (Digest) can reload without waiting for
    /// the file watcher's debounce.
    static let didFileNotification = Notification.Name("SharedCaptureDrain.didFile")

    struct FiledCapture: Equatable {
        let capture: PendingCapture
        let filed: CaptureFilingService.Filed
    }

    struct Outcome: Equatable {
        var filed: [FiledCapture] = []
        var failed: [PendingCapture] = []
    }

    let store: PendingCaptureStore
    let vaultURL: URL
    /// Injected so tests can swap the filing writer; production uses the
    /// coordinated writer the Capture tab uses.
    var makeService: (URL) -> CaptureFilingService = { CaptureFilingService(vaultURL: $0) }

    init(store: PendingCaptureStore, vaultURL: URL) {
        self.store = store
        self.vaultURL = vaultURL
    }

    /// The drain against the shared App Group container, or nil when this
    /// build lacks the entitlement.
    static func appGroup(vaultURL: URL) -> SharedCaptureDrain? {
        guard let store = PendingCaptureStore.appGroup() else {
            logger.error("App Group container unavailable; share-sheet captures cannot be drained")
            return nil
        }
        return SharedCaptureDrain(store: store, vaultURL: vaultURL)
    }

    func drain() -> Outcome {
        var outcome = Outcome()
        for capture in store.pending() {
            var service = makeService(vaultURL)
            service.now = { capture.createdAt }
            do {
                let filed = try service.file(capture.body)
                store.remove(capture)
                outcome.filed.append(FiledCapture(capture: capture, filed: filed))
                logger.info("shared capture filed \(filed.relativePath, privacy: .public) created=\(filed.didCreate)")
                DebugTrace.record("shared capture filed \(filed.relativePath) created=\(filed.didCreate)")
            } catch {
                outcome.failed.append(capture)
                logger.error("shared capture \(capture.id.uuidString, privacy: .public) not filed: \(String(describing: error), privacy: .public)")
                DebugTrace.record("shared capture drain failed \(capture.id.uuidString) \(String(describing: error))")
            }
        }
        return outcome
    }
}
