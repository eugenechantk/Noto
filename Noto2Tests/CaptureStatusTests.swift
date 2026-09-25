import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. filedStatusCarriesTheFileURL — a filed capture's line knows which note to open (SC1)
/// 2. filedTextNamesTheRelativePath — the line reads "Filed · inbox/<slug>.md" (SC1)
/// 3. discardedStatusHasNoFileURL — a discard opens nothing (SC2)
/// 4. duplicateStatusIsStillOpenable — "Already filed" still points at the existing note (SC3)
/// 5. openableStatusDwellsLongerThanADiscard — a tappable line outlives the old 1.5s (SC4)
/// 6. filedNoteURLResolvesToItsDestination — a real filed note resolves to its editor target (SC5)
/// 7. noteInSubfolderResolvesToItsOwnDirectory — inbox/ notes get the inbox store, not the root (SC5)
/// 8. urlOutsideTheVaultResolvesToNil — a foreign URL navigates nowhere (SC6)
/// 9. urlWithNoNoteBehindItResolvesToNil — a vault-shaped path with no file navigates nowhere (SC6)
struct CaptureStatusTests {
    private let fileURL = URL(fileURLWithPath: "/tmp/Vault/inbox/2026-09-01-1a2b3c4d.md")

    // MARK: - Unit

    @Test func filedStatusCarriesTheFileURL() {
        let status = CaptureStatus.filed(
            relativePath: "inbox/2026-09-01-1a2b3c4d.md", fileURL: fileURL, didCreate: true
        )
        #expect(status.fileURL == fileURL)
        #expect(status.isOpenable)
        #expect(status.isDiscard == false)
    }

    @Test func filedTextNamesTheRelativePath() {
        let status = CaptureStatus.filed(
            relativePath: "inbox/2026-09-01-1a2b3c4d.md", fileURL: fileURL, didCreate: true
        )
        #expect(status.text == "Filed · inbox/2026-09-01-1a2b3c4d.md")
        #expect(status.glyph == "checkmark")
    }

    @Test func discardedStatusHasNoFileURL() {
        let status = CaptureStatus.discarded()
        #expect(status.fileURL == nil)
        #expect(status.isOpenable == false)
        #expect(status.isDiscard)
    }

    @Test func duplicateStatusIsStillOpenable() {
        // The capture was not written again, but the note it duplicates exists
        // and is exactly what the user wants to open.
        let status = CaptureStatus.filed(
            relativePath: "inbox/2026-09-01-1a2b3c4d.md", fileURL: fileURL, didCreate: false
        )
        #expect(status.isOpenable)
        #expect(status.text.hasPrefix("Already filed · "))
        #expect(status.glyph == "doc.on.doc")
    }

    @Test func openableStatusDwellsLongerThanADiscard() {
        let openable = CaptureStatus.filed(relativePath: "inbox/a.md", fileURL: fileURL, didCreate: true)
        let discarded = CaptureStatus.discarded()
        #expect(openable.dwell == .seconds(6))
        #expect(discarded.dwell == .seconds(1.5))
        #expect(openable.dwell > discarded.dwell)
    }

    // MARK: - Integration (real temp vault)

    private func makeVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Noto2CaptureStatusVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    @Test func filedNoteURLResolvesToItsDestination() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let noteURL = vault.appendingPathComponent("Root Note.md")
        try "# Root Note\n\nbody".write(to: noteURL, atomically: true, encoding: .utf8)

        let controller = VaultController(vaultURL: vault, autoloadRoot: false)
        let destination = BrowseDestination.note(at: noteURL, in: controller)

        guard case .note(let note, let directoryURL, let isNew)? = destination else {
            Issue.record("expected a note destination, got \(String(describing: destination))")
            return
        }
        #expect(note.fileURL.standardizedFileURL == noteURL.standardizedFileURL)
        #expect(directoryURL.standardizedFileURL == vault.standardizedFileURL)
        #expect(!isNew)
    }

    @MainActor
    @Test func noteInSubfolderResolvesToItsOwnDirectory() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let inbox = vault.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let noteURL = inbox.appendingPathComponent("2026-09-01-1a2b3c4d.md")
        try "captured thought".write(to: noteURL, atomically: true, encoding: .utf8)

        let controller = VaultController(vaultURL: vault, autoloadRoot: false)
        let destination = BrowseDestination.note(at: noteURL, in: controller)

        guard case .note(let note, let directoryURL, let isNew)? = destination else {
            Issue.record("expected a note destination, got \(String(describing: destination))")
            return
        }
        #expect(note.fileURL.standardizedFileURL == noteURL.standardizedFileURL)
        // The editor must write through the inbox store, not the vault root.
        #expect(directoryURL.standardizedFileURL == inbox.standardizedFileURL)
        #expect(!isNew)
    }

    @MainActor
    @Test func urlOutsideTheVaultResolvesToNil() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let controller = VaultController(vaultURL: vault, autoloadRoot: false)
        let foreign = FileManager.default.temporaryDirectory.appendingPathComponent("Elsewhere.md")
        #expect(BrowseDestination.note(at: foreign, in: controller) == nil)
    }

    @MainActor
    @Test func urlWithNoNoteBehindItResolvesToNil() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let controller = VaultController(vaultURL: vault, autoloadRoot: false)
        let missing = vault.appendingPathComponent("inbox/never-written.md")
        #expect(BrowseDestination.note(at: missing, in: controller) == nil)
    }
}
