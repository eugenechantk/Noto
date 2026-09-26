import Foundation
import Testing
import UIKit
@testable import Noto2

struct NotePathCopyTests {
    @Test @MainActor func formatsPathsAndWritesNestedPathToPasteboard() {
        let previousValue = UIPasteboard.general.string
        defer { UIPasteboard.general.string = previousValue }

        let vaultURL = URL(fileURLWithPath: "/tmp/Noto Vault", isDirectory: true)
        let store = MarkdownNoteStore(vaultURL: vaultURL, autoload: false)
        let nestedNoteURL = vaultURL.appending(path: "Projects/Meeting Notes.md")
        let rootNoteURL = vaultURL.appending(path: "Meeting Notes.md")
        let outsideNoteURL = URL(fileURLWithPath: "/tmp/Another Vault/Meeting Notes.md")

        #expect(store.vaultRelativePath(for: nestedNoteURL) == "Projects/Meeting Notes.md")
        #expect(store.vaultRelativePath(for: rootNoteURL) == "Meeting Notes.md")
        #expect(store.vaultRelativePath(for: outsideNoteURL) == nil)
        #expect(outsideNoteURL.standardizedFileURL.path == "/tmp/Another Vault/Meeting Notes.md")

        let path = store.vaultRelativePath(for: nestedNoteURL) ?? nestedNoteURL.standardizedFileURL.path
        NotePathClipboard.copy(path)

        #expect(UIPasteboard.general.string == "Projects/Meeting Notes.md")
    }
}
