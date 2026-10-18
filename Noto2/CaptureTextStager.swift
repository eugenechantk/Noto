import Foundation
import NotoShareCapture
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "CaptureTextStager")

/// Stages the text of a `noto2://capture?text=` link in the App Group, the same
/// hand-off the share extension uses, so `RootTabView`'s shared-capture drain
/// files it into `inbox/` and opens its note. Going through the drain rather
/// than writing the vault here covers a cold launch whose vault is not resolved
/// yet, and keeps filing, indexing and Digest refresh in one place.
enum CaptureTextStager {
    /// Stages `text` and returns the staged capture's id, or nil when it could not.
    static func stage(_ text: String, in store: PendingCaptureStore?) -> UUID? {
        guard let store else {
            logger.error("App Group container unavailable; capture-text link not staged")
            return nil
        }
        do {
            let capture = try store.enqueue(body: text)
            DebugTrace.record("capture-text link staged \(capture.id.uuidString)")
            return capture.id
        } catch {
            logger.error("capture-text link not staged: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The production stager, against the shared App Group container.
    static func stageInAppGroup(_ text: String) -> UUID? {
        stage(text, in: PendingCaptureStore.appGroup())
    }
}
