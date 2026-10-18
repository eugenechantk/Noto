import Foundation
import Testing
@testable import Noto2

/// Test case index — where an "Open" from Capture's toast lands in Library.
/// 1. filedNoteURLResolvesToItsDestination — a real filed note resolves to its editor target
/// 2. noteInSubfolderResolvesToItsOwnDirectory — inbox/ notes get the inbox store, not the root
/// 3. urlOutsideTheVaultResolvesToNil — a foreign URL navigates nowhere
/// 4. urlWithNoNoteBehindItResolvesToNil — a vault-shaped path with no file navigates nowhere
struct BrowseDestinationTests {
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
