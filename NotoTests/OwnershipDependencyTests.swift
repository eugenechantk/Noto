import Foundation
import Testing

@Suite("Ownership dependency checks")
struct OwnershipDependencyTests {
    @Test("Obsolete search refresh coordinator name is not used")
    func obsoleteSearchRefreshCoordinatorNameIsRemoved() throws {
        let root = try repositoryRoot()
        let sourceFiles = try swiftFiles(in: root.appendingPathComponent("Noto"))

        for fileURL in sourceFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!source.contains("SearchIndexRefreshCoordinator"), "\(fileURL.path) still references SearchIndexRefreshCoordinator")
        }
    }

    @Test("NotoVault package stays presentation-framework free")
    func notoVaultDoesNotImportPresentationFrameworks() throws {
        let root = try repositoryRoot()
        let sourceFiles = try swiftFiles(in: root.appendingPathComponent("Packages/NotoVault/Sources/NotoVault"))

        for fileURL in sourceFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!source.contains("import SwiftUI"), "\(fileURL.path) imports SwiftUI")
            #expect(!source.contains("import UIKit"), "\(fileURL.path) imports UIKit")
            #expect(!source.contains("import AppKit"), "\(fileURL.path) imports AppKit")
        }
    }

    @Test("NotoSearch package does not post app notifications")
    func notoSearchDoesNotOwnAppNotifications() throws {
        let root = try repositoryRoot()
        let sourceFiles = try swiftFiles(in: root.appendingPathComponent("Packages/NotoSearch/Sources/NotoSearch"))

        for fileURL in sourceFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!source.contains("NotificationCenter"), "\(fileURL.path) uses NotificationCenter")
            #expect(!source.contains("notoSearchIndexDidChange"), "\(fileURL.path) posts app search notifications")
        }
    }

    @Test("Split view is a navigation shell")
    func splitViewDoesNotOwnEditorOrVaultMutation() throws {
        let root = try repositoryRoot()
        let fileURL = root.appendingPathComponent("Noto/Views/Shared/NotoSplitView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(!source.contains("NoteEditorScreen("), "NotoSplitView should not instantiate the note editor")
        #expect(!source.contains("selectedNoteStore"), "NotoSplitView should not own selected-note store state")
        #expect(!source.contains("store.createNote("), "NotoSplitView should not create notes directly")
        #expect(!source.contains("openDocumentLink("), "NotoSplitView should not resolve document links")
    }

    @Test("Shared sidebar emits workspace intents")
    func sharedSidebarDoesNotOwnSelectionOrVaultMutation() throws {
        let root = try repositoryRoot()
        let fileURL = root.appendingPathComponent("Noto/Views/Shared/NotoSidebarView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        let forbiddenSnippets = [
            "@Binding var selectedNote",
            "@Binding var selectedNoteStore",
            "@Binding var selectedIsNew",
            "selectedNote =",
            "selectedNoteStore =",
            "selectedIsNew =",
            "externallyDeletingNoteID",
            "isSearchPresented",
            ".deleteNote(",
            ".deleteFolder(",
            ".moveNote(",
            ".createNote(",
            ".createFolder("
        ]

        for snippet in forbiddenSnippets {
            #expect(!source.contains(snippet), "NotoSidebarView should not contain \(snippet)")
        }
    }

    @Test("Compact folder list emits workspace intents")
    func folderContentViewDoesNotOwnNavigationOrVaultMutation() throws {
        let root = try repositoryRoot()
        let fileURL = root.appendingPathComponent("Noto/Views/NoteListView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let folderContentSource = try sourceSection(
            in: source,
            startingAt: "struct FolderContentView",
            endingBefore: "// MARK: - Shared iOS Bottom Toolbar"
        )

        let forbiddenSnippets = [
            "@Binding var path",
            "NavigationPath",
            "path.append(",
            "store.createNote(",
            "store.createFolder(",
            "store.deleteItem("
        ]

        for snippet in forbiddenSnippets {
            #expect(!folderContentSource.contains(snippet), "FolderContentView should not contain \(snippet)")
        }
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let marker = url.appendingPathComponent("Noto.xcodeproj")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw RepositoryLookupError.notFound
    }

    private func swiftFiles(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func sourceSection(in source: String, startingAt startMarker: String, endingBefore endMarker: String) throws -> String {
        guard let startRange = source.range(of: startMarker) else {
            throw SourceSectionError.markerNotFound(startMarker)
        }
        guard let endRange = source[startRange.lowerBound...].range(of: endMarker) else {
            throw SourceSectionError.markerNotFound(endMarker)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    enum RepositoryLookupError: Error {
        case notFound
    }

    enum SourceSectionError: Error {
        case markerNotFound(String)
    }
}
