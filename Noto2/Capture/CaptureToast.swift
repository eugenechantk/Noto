import Foundation

/// The glass toast that confirms what Capture just did (feature doc C5).
///
/// A value type so the rules are testable: what the toast says, which actions it
/// offers, how long it stays, and what Undo puts back. A toast you are meant to
/// tap (Undo, Open) has to outlive a passive confirmation.
struct CaptureToast: Identifiable, Equatable {
    enum Kind: Equatable {
        case filed(CaptureFilingService.Filed, draft: String)
        case discarded(draft: String)
        case added(noteTitle: String, receipt: CaptureDirectFiling.Receipt)
        case created(folderName: String, receipt: CaptureDirectFiling.Receipt)
        case copied
    }

    let id = UUID()
    let kind: Kind

    var message: String {
        switch kind {
        case .filed(let filed, _): filed.didCreate ? "Filed to Inbox" : "Already in Inbox"
        case .discarded: "Discarded"
        case .added(let title, _): "Added to \(title)"
        case .created(let folder, _): "Created in \(folder)"
        case .copied: "Copied"
        }
    }

    var systemImage: String {
        switch kind {
        case .filed, .added, .created: "checkmark"
        case .discarded: "trash"
        case .copied: "doc.on.doc"
        }
    }

    var isSuccessfulFiling: Bool {
        switch kind {
        case .filed, .added, .created: true
        case .discarded, .copied: false
        }
    }

    /// The text Undo puts back in the card, including optional New note edits.
    var restoredDraft: String? {
        switch kind {
        case .filed(_, let draft), .discarded(let draft): draft
        case .added(_, let receipt), .created(_, let receipt): receipt.draft
        case .copied: nil
        }
    }

    var canUndo: Bool { restoredDraft != nil }

    var directFilingReceipt: CaptureDirectFiling.Receipt? {
        switch kind {
        case .added(_, let receipt), .created(_, let receipt): receipt
        case .filed, .discarded, .copied: nil
        }
    }

    /// The person can start their next thought while the toast is visible.
    /// Undo must keep that writing as well as the restored capture.
    func restoringDraft(alongside current: String) -> String? {
        guard let restoredDraft else { return nil }
        guard !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return restoredDraft }
        return restoredDraft + "\n\n" + current
    }

    /// The note Open shows in Library.
    var openURL: URL? {
        switch kind {
        case .filed(let filed, _): filed.fileURL
        case .added(_, let receipt), .created(_, let receipt): receipt.noteURL
        case .discarded, .copied: nil
        }
    }

    var dwell: Duration {
        switch kind {
        case .filed, .added, .created: .seconds(6)
        case .discarded: .seconds(4)
        case .copied: .seconds(1.5)
        }
    }

    static func filed(_ filed: CaptureFilingService.Filed, draft: String) -> CaptureToast {
        CaptureToast(kind: .filed(filed, draft: draft))
    }

    static func discarded(draft: String) -> CaptureToast {
        CaptureToast(kind: .discarded(draft: draft))
    }

    static func added(noteTitle: String, receipt: CaptureDirectFiling.Receipt) -> CaptureToast {
        CaptureToast(kind: .added(noteTitle: noteTitle, receipt: receipt))
    }

    static func created(folderName: String, receipt: CaptureDirectFiling.Receipt) -> CaptureToast {
        CaptureToast(kind: .created(folderName: folderName, receipt: receipt))
    }

    static func copied() -> CaptureToast {
        CaptureToast(kind: .copied)
    }
}
