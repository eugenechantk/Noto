import Foundation

/// When Capture's actions are available (feature doc C2, C4).
enum CaptureActions {
    /// ✓ and every filing action need text, a vault, and no filing in flight.
    static func canFile(draft: String, hasVault: Bool, isBusy: Bool) -> Bool {
        hasVault && !isBusy && !CaptureFilingService.normalizedBody(draft).isEmpty
    }
}

/// The card's long-press menu, in display order.
enum CaptureMenuAction: CaseIterable, Hashable {
    case fileToInbox, addToNote, newNote, copyText, discard

    var title: String {
        switch self {
        case .fileToInbox: "File to Inbox"
        case .addToNote: "Add to note…"
        case .newNote: "New note…"
        case .copyText: "Copy text"
        case .discard: "Discard"
        }
    }

    var systemImage: String {
        switch self {
        case .fileToInbox: "tray.and.arrow.down"
        case .addToNote: "text.append"
        case .newNote: "doc.badge.plus"
        case .copyText: "doc.on.doc"
        case .discard: "trash"
        }
    }

    var isDestructive: Bool { self == .discard }

    var accessibilityIdentifier: String {
        switch self {
        case .fileToInbox: "captureMenuFile"
        case .addToNote: "captureMenuAddTo"
        case .newNote: "captureMenuNewNote"
        case .copyText: "captureMenuCopy"
        case .discard: "captureMenuDiscard"
        }
    }

    /// Everything needs text. Copy and Discard touch no file, so they work
    /// before a vault is chosen; the three filing actions do not.
    func isEnabled(draft: String, hasVault: Bool) -> Bool {
        guard !CaptureFilingService.normalizedBody(draft).isEmpty else { return false }
        switch self {
        case .copyText, .discard: return true
        case .fileToInbox, .addToNote, .newNote: return hasVault
        }
    }
}
