import Foundation
import Testing
@testable import Noto2

/// Test case index — the glass toast that replaces Capture's status line (C5).
/// 1. filedToastOffersUndoAndOpen — "Filed to Inbox" can be undone and opened
/// 2. duplicateFileStillOpensButSaysSo — an identical capture already filed today
/// 3. discardedToastOffersUndoOnly — nothing was written, so nothing to open
/// 4. addedToastNamesTheNoteAndOffersUndoAndOpen — the destination and receipt travel together
/// 5. createdToastNamesTheFolderAndOffersUndoAndOpen — optional edits are restored alongside a new draft
/// 6. copiedToastIsShortAndInert — no actions, short dwell
/// 7. dwellMatchesWhatTheToastAsksOfYou — actionable toasts stay long enough to tap
/// 8. undoPayloadCarriesTheDraft — undo restores exactly the text that was filed or discarded
struct CaptureToastTests {
    private let inboxURL = URL(fileURLWithPath: "/tmp/Vault/inbox/2026-10-17-1a2b3c4d.md")

    private func directReceipt() throws -> CaptureDirectFiling.Receipt {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureToast-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        return try CaptureDirectFiling(vaultURL: vault).createNote("Calm UI\n\nEdited body", inFolderAt: vault)
    }

    private func filed(didCreate: Bool = true) -> CaptureFilingService.Filed {
        CaptureFilingService.Filed(
            fileURL: inboxURL,
            relativePath: "inbox/2026-10-17-1a2b3c4d.md",
            id: UUID(),
            didCreate: didCreate
        )
    }

    @Test func filedToastOffersUndoAndOpen() {
        let toast = CaptureToast.filed(filed(), draft: "Calm UI worth copying")
        #expect(toast.message == "Filed to Inbox")
        #expect(toast.canUndo)
        #expect(toast.openURL == inboxURL)
        #expect(toast.systemImage == "checkmark")
    }

    @Test func duplicateFileStillOpensButSaysSo() {
        let toast = CaptureToast.filed(filed(didCreate: false), draft: "Calm UI worth copying")
        #expect(toast.message == "Already in Inbox")
        #expect(toast.openURL == inboxURL)
    }

    @Test func discardedToastOffersUndoOnly() {
        let toast = CaptureToast.discarded(draft: "never mind")
        #expect(toast.message == "Discarded")
        #expect(toast.canUndo)
        #expect(toast.openURL == nil)
    }

    @Test func addedToastNamesTheNoteAndOffersUndoAndOpen() throws {
        let receipt = try directReceipt()
        let toast = CaptureToast.added(noteTitle: "Calm UI", receipt: receipt)
        #expect(toast.message == "Added to Calm UI")
        #expect(toast.canUndo)
        #expect(toast.openURL == receipt.noteURL)
        #expect(toast.directFilingReceipt == receipt)
        #expect(toast.restoredDraft == receipt.draft)
    }

    @Test func createdToastNamesTheFolderAndOffersUndoAndOpen() throws {
        let receipt = try directReceipt()
        let toast = CaptureToast.created(folderName: "Ideas", receipt: receipt)
        #expect(toast.message == "Created in Ideas")
        #expect(toast.canUndo)
        #expect(toast.openURL == receipt.noteURL)
        #expect(toast.restoringDraft(alongside: "Next thought") == receipt.draft + "\n\nNext thought")
    }

    @Test func copiedToastIsShortAndInert() {
        let toast = CaptureToast.copied()
        #expect(toast.message == "Copied")
        #expect(!toast.canUndo)
        #expect(toast.openURL == nil)
        #expect(toast.dwell == .seconds(1.5))
    }

    @Test func dwellMatchesWhatTheToastAsksOfYou() throws {
        let receipt = try directReceipt()
        #expect(CaptureToast.filed(filed(), draft: "x").dwell == .seconds(6))
        #expect(CaptureToast.added(noteTitle: "N", receipt: receipt).dwell == .seconds(6))
        #expect(CaptureToast.created(folderName: "F", receipt: receipt).dwell == .seconds(6))
        #expect(CaptureToast.discarded(draft: "x").dwell == .seconds(4))
    }

    @Test func undoPayloadCarriesTheDraft() {
        let filedToast = CaptureToast.filed(filed(), draft: "first thought")
        let discardToast = CaptureToast.discarded(draft: "second thought")
        #expect(filedToast.restoredDraft == "first thought")
        #expect(discardToast.restoredDraft == "second thought")
        #expect(CaptureToast.copied().restoredDraft == nil)
    }

    @Test func undoKeepsANewThoughtTypedWhileTheToastWasVisible() {
        let toast = CaptureToast.discarded(draft: "Original thought")
        #expect(toast.restoringDraft(alongside: "Next thought") == "Original thought\n\nNext thought")
        #expect(toast.restoringDraft(alongside: "  \n") == "Original thought")
        #expect(CaptureToast.copied().restoringDraft(alongside: "Next thought") == nil)
    }
}
