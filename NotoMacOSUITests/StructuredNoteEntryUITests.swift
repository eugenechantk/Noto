import XCTest

final class StructuredNoteEntryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var directVaultURL: URL?

    private let composedMarkdown = """
UI Test Title

## Section Heading
This is a paragraph in the UI test.
It continues on a second line.

- Bullet one
- Bullet two
"""

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-notoResetState", "YES",
            "-notoUseLocalVault", "YES",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let directVaultURL {
            try? FileManager.default.removeItem(at: directVaultURL)
        }
        app = nil
    }

    @MainActor
    func testCreateNoteOpensEditor() throws {
        createNewNote()

        let editor = app.textViews["note_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The editor should open after creating a note")
    }

    @MainActor
    func testCreateNoteAndEnterStructuredMarkdown() throws {
        createNewNote()

        let editor = app.textViews["note_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The editor should open after creating a note")

        appendTextToEndOfEditor(composedMarkdown, editor: editor)

        XCTAssertTrue(waitForEditorToContain("UI Test Title"), "The first heading should be written")
        XCTAssertTrue(waitForEditorToContain("Section Heading"), "The second heading should be written")
        XCTAssertTrue(waitForEditorToContain("This is a paragraph in the UI test."), "The paragraph should be written")
        XCTAssertTrue(waitForEditorToContain("Bullet one"), "The first bullet should be written")
        XCTAssertTrue(waitForEditorToContain("Bullet two"), "The second bullet should be written")
    }

    @MainActor
    func testDirectVaultWritesMarkdownToDiskWhenSwitchingNotes() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoMacDirectVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        directVaultURL = vaultURL

        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-notoResetState", "YES",
            "-notoDirectVaultPath", vaultURL.path,
        ]
        app.launch()

        createNewNote()

        let editor = app.textViews["note_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The editor should open after creating a note")

        let appendedText = "Direct vault disk write line"
        let title = "Disk Save Title"
        appendTextToEndOfEditor("Disk Save Title\n\(appendedText)", editor: editor)

        let firstNoteURL = try XCTUnwrap(waitForSingleMarkdownFile(in: vaultURL, timeout: 10), "A markdown file should be created in the direct vault")
        XCTAssertTrue(waitForFileToContain(appendedText, fileURL: firstNoteURL, timeout: 10), "Typing should write the new line to markdown on disk")

        createNewNote()

        let secondEditor = app.textViews["note_editor"]
        XCTAssertTrue(secondEditor.waitForExistence(timeout: 10), "The second note editor should appear")
        appendTextToEndOfEditor("Second note", editor: secondEditor)

        let renamedFirstNoteURL = waitForMarkdownFile(named: title, in: vaultURL, timeout: 10) ?? firstNoteURL
        XCTAssertTrue(waitForFileToContain(appendedText, fileURL: renamedFirstNoteURL, timeout: 10), "Switching notes should keep the first note's saved content on disk")
    }

    @MainActor
    func testDirectVaultExistingNoteKeepsAppendedLineOnDiskWhenSwitching() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoMacExistingVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        directVaultURL = vaultURL

        let existingNoteURL = vaultURL.appendingPathComponent("Existing.md")
        let existingContent = """
        ---
        id: \(UUID().uuidString)
        created: 2026-04-04T00:00:00Z
        updated: 2026-04-04T00:00:00Z
        ---

        # Existing
        Body
        """
        try existingContent.write(to: existingNoteURL, atomically: true, encoding: .utf8)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-notoResetState", "YES",
            "-notoDirectVaultPath", vaultURL.path,
        ]
        app.launch()

        let noteRow = app.buttons["note_Existing"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 10), "The existing note should appear in the sidebar")
        noteRow.click()

        let editor = app.textViews["note_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The editor should open for the existing note")

        let appendedText = "Existing appended line"
        appendTextToEndOfEditor("\n\(appendedText)", editor: editor)
        XCTAssertTrue(waitForFileToContain(appendedText, fileURL: existingNoteURL, timeout: 10), "Typing should write the appended line to the existing file")

        createNewNote()

        let secondEditor = app.textViews["note_editor"]
        XCTAssertTrue(secondEditor.waitForExistence(timeout: 10), "The second note editor should appear")
        appendTextToEndOfEditor("Second note", editor: secondEditor)

        XCTAssertTrue(waitForFileToContain(appendedText, fileURL: existingNoteURL, timeout: 10), "Switching notes should keep the appended line in the existing file on disk")
    }

    @MainActor
    func testDirectVaultSidebarDeleteRemovesFileFromDisk() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoMacDeleteVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        directVaultURL = vaultURL

        let existingNoteURL = vaultURL.appendingPathComponent("Delete Me.md")
        let existingContent = """
        ---
        id: \(UUID().uuidString)
        created: 2026-04-04T00:00:00Z
        updated: 2026-04-04T00:00:00Z
        ---

        # Delete Me
        Body
        """
        try existingContent.write(to: existingNoteURL, atomically: true, encoding: .utf8)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-notoResetState", "YES",
            "-notoDirectVaultPath", vaultURL.path,
        ]
        app.launch()

        let noteRow = app.buttons["note_Delete Me"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 10), "The existing note should appear in the sidebar")

        noteRow.rightClick()
        let deleteMenuItem = app.menuItems["Delete"].firstMatch
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 5), "The delete menu item should appear")
        deleteMenuItem.click()

        XCTAssertTrue(waitForFileToDisappear(existingNoteURL, timeout: 10), "Deleting from the sidebar should remove the file from disk")
    }

    private func createNewNote() {
        let newNoteButton = app.buttons["new_note_button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 10), "The new note button should exist")
        newNoteButton.click()
    }

    private func appendTextToEndOfEditor(_ text: String, editor: XCUIElement) {
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The editor should exist before typing")
        editor.click()
        editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
        editor.typeText(text)
    }

    private func waitForEditorToContain(_ text: String, timeout: TimeInterval = 10) -> Bool {
        let editor = app.textViews["note_editor"]
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForSingleMarkdownFile(in directory: URL, timeout: TimeInterval) -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let markdownFiles = files.filter { $0.pathExtension == "md" }
            if markdownFiles.count == 1 {
                return markdownFiles[0]
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    private func waitForMarkdownFile(named name: String, in directory: URL, timeout: TimeInterval) -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let candidate = directory.appendingPathComponent(name).appendingPathExtension("md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    private func waitForFileToContain(_ text: String, fileURL: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
               contents.contains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForFileToDisappear(_ fileURL: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
