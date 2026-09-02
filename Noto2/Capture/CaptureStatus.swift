import Foundation

/// The outcome line above the capture card.
///
/// This is a value type rather than view-local state because it decides two
/// things worth testing: whether the line opens a note (a filed capture does, a
/// discard does not) and how long it stays on screen — a line you are meant to
/// tap cannot vanish in the 1.5s that was fine for a passive confirmation.
struct CaptureStatus: Identifiable, Equatable {
    let id = UUID()
    let glyph: String
    let text: String
    /// The note this line opens, when there is one.
    let fileURL: URL?
    let isDiscard: Bool

    var isOpenable: Bool { fileURL != nil }

    /// How long the line stays before it clears itself.
    var dwell: Duration { isOpenable ? .seconds(6) : .seconds(1.5) }

    /// A capture that reached disk. `didCreate == false` means an identical
    /// capture was already filed — that note still exists, so the line still
    /// opens it.
    static func filed(relativePath: String, fileURL: URL, didCreate: Bool) -> CaptureStatus {
        CaptureStatus(
            glyph: didCreate ? "checkmark" : "doc.on.doc",
            text: (didCreate ? "Filed · " : "Already filed · ") + relativePath,
            fileURL: fileURL,
            isDiscard: false
        )
    }

    static func discarded() -> CaptureStatus {
        CaptureStatus(glyph: "trash", text: "Discarded", fileURL: nil, isDiscard: true)
    }
}
