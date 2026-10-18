import Foundation
import NotoDigest
import Testing
@testable import Noto2

/// Test case index — Add to note… and New note… from Capture (C7, C8, C9).
/// Integration tests: real temp vault, real `CaptureFilingService`, real `DigestFiling`.
/// 1. addToAppendsTheDraftAndLeavesTheInboxEmpty — the text lands at the end of the note, no inbox copy
/// 2. newNoteIsNamedFromTheFirstLineAndKeepsTheMarkdown — `<first line>.md`, Markdown unchanged
/// 3. failedAddToKeepsTheCaptureInTheInbox — a missing target never loses the thought
/// 4. blankDraftIsRejectedBeforeAnythingIsWritten — nothing lands anywhere
/// 5. undoRemovesOnlyTheCaptureThisFilingCreated — ✓ then Undo leaves the vault as it was
/// 6. undoKeepsAnEarlierIdenticalCapture — Undo of a duplicate never deletes the original
/// 7. undoDirectAddRestoresExactDestinationAndDraft — direct append Undo restores bytes and draft
/// 8. undoDirectCreateRemovesNewNoteAndRestoresEditedDraft — direct create Undo keeps optional edits
/// 9. undoDirectFilingKeepsAnEarlierIdenticalInboxCapture — only the new staging file is removed
/// 10. undoDirectAddRefusesLaterDestinationEdits — Undo keeps edits after append
/// 11. undoDirectCreateRefusesLaterDestinationEdits — Undo keeps edits after create
/// 12. matchingDocumentUndoKeepsAnEditedCaptureWithTheSameIdentity — cleanup checks exact bytes
struct CaptureDirectFilingTests {
    private func makeVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Noto2DirectFiling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func inboxFiles(_ vault: URL) -> [String] {
        let inbox = vault.appendingPathComponent("inbox", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? [])
            .filter { $0.hasSuffix(".md") }
    }

    @Test func addToAppendsTheDraftAndLeavesTheInboxEmpty() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let target = vault.appendingPathComponent("Health.md")
        try "---\nid: t\n---\nHealth\n\n- sleep earlier\n".write(to: target, atomically: true, encoding: .utf8)

        let written = try CaptureDirectFiling(vaultURL: vault).add("Ran 5k before work.", toNoteAt: target).noteURL

        #expect(written.standardizedFileURL == target.standardizedFileURL)
        let note = try String(contentsOf: target, encoding: .utf8)
        #expect(note.hasSuffix("- sleep earlier\n\nRan 5k before work.\n"))
        #expect(inboxFiles(vault).isEmpty)
    }

    @Test func newNoteIsNamedFromTheFirstLineAndKeepsTheMarkdown() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let folder = vault.appendingPathComponent("Ideas", isDirectory: true)
        let draft = "Calm UI worth copying\n\n- one quiet accent"

        let written = try CaptureDirectFiling(vaultURL: vault).createNote(draft, inFolderAt: folder).noteURL

        #expect(written.lastPathComponent == "Calm UI worth copying.md")
        let note = try String(contentsOf: written, encoding: .utf8)
        #expect(note.hasSuffix("---\n" + draft + "\n"))
        #expect(!note.contains("# Calm UI"))
        #expect(inboxFiles(vault).isEmpty)
    }

    @Test func failedAddToKeepsTheCaptureInTheInbox() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let ghost = vault.appendingPathComponent("Deleted meanwhile.md")

        #expect(throws: (any Error).self) {
            try CaptureDirectFiling(vaultURL: vault).add("Keep me", toNoteAt: ghost)
        }
        let files = inboxFiles(vault)
        #expect(files.count == 1)
        let body = try String(contentsOf: vault.appendingPathComponent("inbox/" + files[0]), encoding: .utf8)
        #expect(body.contains("Keep me"))
    }

    @Test func blankDraftIsRejectedBeforeAnythingIsWritten() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        #expect(throws: (any Error).self) {
            try CaptureDirectFiling(vaultURL: vault).createNote("   \n", inFolderAt: vault)
        }
        #expect(inboxFiles(vault).isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: vault.path)) ?? []).filter { $0.hasSuffix(".md") }.isEmpty)
    }

    @Test func undoRemovesOnlyTheCaptureThisFilingCreated() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = CaptureFilingService(vaultURL: vault)

        let filed = try service.file("A thought to take back")
        #expect(inboxFiles(vault).count == 1)
        #expect(service.undo(filed))
        #expect(inboxFiles(vault).isEmpty)
    }

    @Test func undoKeepsAnEarlierIdenticalCapture() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = CaptureFilingService(vaultURL: vault)

        _ = try service.file("Same thought")
        let duplicate = try service.file("Same thought")
        #expect(!duplicate.didCreate)
        #expect(!service.undo(duplicate))
        #expect(inboxFiles(vault).count == 1)
    }

    @Test func undoDirectAddRestoresExactDestinationAndDraft() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let target = vault.appendingPathComponent("Health.md")
        let original = "---\nid: health\nupdated: 2026-10-17T09:00:00Z\n---\nHealth\n\n- Sleep earlier\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        let service = CaptureDirectFiling(vaultURL: vault)
        let draft = "  Ran 5k\n\n- Felt good  "
        let receipt = try service.add(draft, toNoteAt: target)

        try service.undo(receipt)

        #expect(try String(contentsOf: target, encoding: .utf8) == original)
        #expect(receipt.draft == draft)
        #expect(inboxFiles(vault).isEmpty)
    }

    @Test func undoDirectCreateRemovesNewNoteAndRestoresEditedDraft() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = CaptureDirectFiling(vaultURL: vault)
        let editedDraft = "Edited title\n\nThe changed body."
        let receipt = try service.createNote(editedDraft, inFolderAt: vault)

        try service.undo(receipt)

        #expect(!FileManager.default.fileExists(atPath: receipt.noteURL.path))
        #expect(receipt.draft == editedDraft)
        #expect(inboxFiles(vault).isEmpty)
    }

    @Test func undoDirectFilingKeepsAnEarlierIdenticalInboxCapture() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let staged = try CaptureFilingService(vaultURL: vault).file("Same thought")
        let original = try String(contentsOf: staged.fileURL, encoding: .utf8)
        let service = CaptureDirectFiling(vaultURL: vault)
        let receipt = try service.createNote("Same thought", inFolderAt: vault)
        #expect(!receipt.stagedCapture.didCreate)

        try service.undo(receipt)

        #expect(try String(contentsOf: staged.fileURL, encoding: .utf8) == original)
        #expect(!FileManager.default.fileExists(atPath: receipt.noteURL.path))
    }

    @Test func undoDirectAddRefusesLaterDestinationEdits() throws {
        try verifyUndoRefusesLaterDestinationEdits(append: true)
    }

    @Test func undoDirectCreateRefusesLaterDestinationEdits() throws {
        try verifyUndoRefusesLaterDestinationEdits(append: false)
    }

    private func verifyUndoRefusesLaterDestinationEdits(append: Bool) throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = CaptureDirectFiling(vaultURL: vault)
        let target = vault.appendingPathComponent("Existing.md")
        try "Existing content\n".write(to: target, atomically: true, encoding: .utf8)
        let receipt: CaptureDirectFiling.Receipt
        if append {
            receipt = try service.add("Capture", toNoteAt: target)
        } else {
            receipt = try service.createNote("Capture", inFolderAt: vault)
        }
        let laterEdit = "Changed after filing\n"
        try laterEdit.write(to: receipt.noteURL, atomically: true, encoding: .utf8)

        #expect(throws: DigestFiling.FilingError.self) { try service.undo(receipt) }

        #expect(try String(contentsOf: receipt.noteURL, encoding: .utf8) == laterEdit)
        #expect(inboxFiles(vault).isEmpty)
        let toast = CaptureToast.created(folderName: "Vault", receipt: receipt)
        #expect(toast.restoringDraft(alongside: "Newer draft") == "Capture\n\nNewer draft")
    }

    @Test func matchingDocumentUndoKeepsAnEditedCaptureWithTheSameIdentity() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = CaptureFilingService(vaultURL: vault)
        let filed = try service.file("Original")
        let original = try String(contentsOf: filed.fileURL, encoding: .utf8)
        let changed = original + "Newer text\n"
        try changed.write(to: filed.fileURL, atomically: true, encoding: .utf8)

        #expect(!service.undo(filed, matchingDocument: original))
        #expect(try String(contentsOf: filed.fileURL, encoding: .utf8) == changed)
    }
}
