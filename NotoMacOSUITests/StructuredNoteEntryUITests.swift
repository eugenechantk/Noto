import XCTest

final class StructuredNoteEntryUITests: XCTestCase {
    private var app: XCUIApplication!

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

        editor.click()
        editor.typeText(composedMarkdown)

        XCTAssertTrue(waitForEditorToContain("UI Test Title"), "The first heading should be written")
        XCTAssertTrue(waitForEditorToContain("Section Heading"), "The second heading should be written")
        XCTAssertTrue(waitForEditorToContain("This is a paragraph in the UI test."), "The paragraph should be written")
        XCTAssertTrue(waitForEditorToContain("Bullet one"), "The first bullet should be written")
        XCTAssertTrue(waitForEditorToContain("Bullet two"), "The second bullet should be written")
    }

    private func createNewNote() {
        let newNoteButton = app.buttons["new_note_button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 10), "The new note button should exist")
        newNoteButton.click()
    }

    private func waitForEditorToContain(_ text: String, timeout: TimeInterval = 10) -> Bool {
        let editor = app.textViews["note_editor"]
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
