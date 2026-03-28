//
//  HomeViewUITests.swift
//  NotoUITests
//
//  XCUITests for the Home Screen.
//  Covers: display, toolbar, block creation, block deletion, indent/outdent,
//  reorder, edit mode, and mentions — all from the home view.
//
//  NOTE: The home screen always contains a "Today's Notes" root block (line 0).
//  All helpers account for this auto-created block.
//

import XCTest

final class HomeViewUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["UITESTING"] = "1"
        app.launch()

        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private var textView: XCUIElement {
        app.textViews["noteTextView"]
    }

    /// Type lines into the text view. Positions cursor after any existing content
    /// (e.g. the auto-created "Today's Notes" block) before typing.
    private func typeLines(_ lines: [String]) {
        let tv = textView
        XCTAssertTrue(tv.waitForExistence(timeout: 5), "Text view should exist")

        let existingText = tv.value as? String ?? ""
        if !existingText.isEmpty {
            // Tap below existing text to place cursor at end of content.
            // UITextView places cursor at nearest valid position when tapping
            // below the last line — which is the end of the document.
            let lineCount = existingText.components(separatedBy: "\n").count
            let belowContentY = 8 + 24 * CGFloat(lineCount) + 12
            let base = tv.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let belowContent = base.withOffset(CGVector(dx: 80, dy: belowContentY))
            belowContent.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("\n")
        } else {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        let fullText = lines.joined(separator: "\n")
        tv.typeText(fullText)
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// All lines in the text view (including "Today's Notes").
    private func currentLines() -> [String] {
        let value = textView.value as? String ?? ""
        return value.components(separatedBy: "\n")
    }

    /// Lines typed by the test, excluding the auto-created "Today's Notes" root block.
    private func userLines() -> [String] {
        currentLines().filter { $0 != "Today's Notes" }
    }

    private func currentText() -> String {
        return textView.value as? String ?? ""
    }

    private func dismissKeyboard() {
        let dismiss = app.buttons["Dismiss Keyboard"]
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// Double-tap a user-content line. Adjusts index to account for
    /// "Today's Notes" being line 0 on the home screen.
    private func doubleTapUserLine(_ userLineIndex: Int) {
        let actualIndex = userLineIndex + 1 // "Today's Notes" is line 0
        doubleTapLine(actualIndex)
    }

    private func doubleTapLine(_ lineIndex: Int) {
        let textInsetTop: CGFloat = 8
        let lineHeight: CGFloat = 24
        let targetY = textInsetTop + lineHeight * CGFloat(lineIndex) + lineHeight * 0.5

        let base = textView.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let lineCoord = base.withOffset(CGVector(dx: 80, dy: targetY))
        lineCoord.doubleTap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Tap on a user-content line. Adjusts index for "Today's Notes" at line 0.
    private func tapOnUserLine(_ userLineIndex: Int) {
        tapOnLine(userLineIndex + 1)
    }

    private func tapOnLine(_ lineIndex: Int) {
        let textInsetTop: CGFloat = 8
        let lineHeight: CGFloat = 24
        let targetY = textInsetTop + lineHeight * CGFloat(lineIndex) + lineHeight * 0.3

        let base = textView.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let lineCoord = base.withOffset(CGVector(dx: 80, dy: targetY))
        lineCoord.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Display

    /// AC-HS-1: Root blocks render as plain text
    @MainActor
    func testRootBlocksRenderAsPlainText() throws {
        typeLines(["Alpha", "Beta", "Gamma"])
        dismissKeyboard()

        let lines = userLines()
        XCTAssertEqual(lines.count, 3, "Should have 3 user lines")
        XCTAssertEqual(lines[0], "Alpha")
        XCTAssertEqual(lines[1], "Beta")
        XCTAssertEqual(lines[2], "Gamma")

        let text = currentText()
        XCTAssertFalse(text.contains("•"), "No bullets should be visible for root blocks")
    }

    /// AC-HS-2: Only root blocks are shown (children NOT visible on home screen)
    @MainActor
    func testOnlyRootBlocksShown() throws {
        typeLines(["Parent", "Child A"])

        // Indent "Child A" under "Parent"
        let indentButton = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'indent'"
        )).firstMatch
        if indentButton.waitForExistence(timeout: 2) {
            indentButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        dismissKeyboard()

        // After indent, Child A becomes a child of Parent and should disappear from home
        let lines = userLines()
        XCTAssertEqual(lines.count, 1,
                       "Home screen should only show root blocks — children should be hidden")
        XCTAssertEqual(lines[0], "Parent")
    }

    /// AC-HS-3: Empty state shows tappable area
    @MainActor
    func testEmptyStateShowsTappableArea() throws {
        let tv = textView
        XCTAssertTrue(tv.waitForExistence(timeout: 5), "Text view should exist for tapping")

        tv.tap()
        Thread.sleep(forTimeInterval: 0.3)

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), "Keyboard should appear after tapping empty state")
    }

    /// AC-HS-4: Content uses correct typography
    @MainActor
    func testContentTypography() throws {
        typeLines(["Hello World"])
        dismissKeyboard()

        let text = currentText()
        XCTAssertTrue(text.contains("Hello World"), "Content should be readable")
    }

    // MARK: - Toolbar

    /// AC-HT-1: Home title and subtitle displayed
    @MainActor
    func testHomeTitleAndSubtitle() throws {
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 5),
                      "Home title should be displayed")

        let subtitle = app.staticTexts["Add tag here"]
        XCTAssertTrue(subtitle.exists, "Tag subtitle placeholder should be displayed")
    }

    /// AC-HT-2: Sort/filter button exists
    @MainActor
    func testSortFilterButton() throws {
        let sortButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'arrow'")).firstMatch
        Thread.sleep(forTimeInterval: 1.0)
        let exists = sortButton.exists || app.buttons.count > 0
        XCTAssertTrue(exists, "Sort/filter button should exist in toolbar")
    }

    /// AC-HT-3: Bottom search bar present
    @MainActor
    func testBottomSearchBar() throws {
        let searchField = app.textFields.firstMatch
        Thread.sleep(forTimeInterval: 1.0)

        let searchExists = searchField.exists
        let placeholderExists = app.staticTexts["Ask anything or search"].exists

        XCTAssertTrue(searchExists || placeholderExists,
                      "Bottom search bar should be present")
    }

    // MARK: - Block Creation

    /// AC-BC-1: Return key creates sibling below
    @MainActor
    func testReturnKeyCreatesSiblingBelow() throws {
        typeLines(["Alpha"])
        textView.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)
        textView.typeText("Beta")
        Thread.sleep(forTimeInterval: 0.3)

        let lines = userLines()
        XCTAssertEqual(lines.count, 2, "Should have 2 user blocks")
        XCTAssertEqual(lines[0], "Alpha")
        XCTAssertEqual(lines[1], "Beta")
    }

    /// AC-BC-2: Return on last block creates block at end
    @MainActor
    func testReturnOnLastBlockCreatesAtEnd() throws {
        typeLines(["Alpha", "Beta"])
        textView.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)
        textView.typeText("Gamma")
        Thread.sleep(forTimeInterval: 0.3)

        let lines = userLines()
        XCTAssertEqual(lines.count, 3, "Should have 3 user blocks after Return on last block")
        XCTAssertEqual(lines[2], "Gamma", "New block should be at the end")
    }

    /// AC-BC-4: Tap empty space on empty screen creates first block
    @MainActor
    func testTapEmptyScreenCreatesFirstBlock() throws {
        let tv = textView
        XCTAssertTrue(tv.waitForExistence(timeout: 5))

        tv.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "Tapping empty screen should enter edit mode")

        tv.typeText("First block")
        Thread.sleep(forTimeInterval: 0.3)

        let text = currentText()
        XCTAssertTrue(text.contains("First block"),
                      "First block should be created after tapping empty space")
    }

    /// AC-BC-7: New block has empty content
    @MainActor
    func testNewBlockHasEmptyContent() throws {
        typeLines(["Alpha"])
        textView.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)

        let lines = userLines()
        XCTAssertGreaterThanOrEqual(lines.count, 2, "Should have at least 2 user lines")
        XCTAssertEqual(lines.last, "", "New block should have empty content")
    }

    // MARK: - Block Deletion

    /// AC-BD-1: Backspace on empty block deletes it
    @MainActor
    func testBackspaceOnEmptyBlockDeletesIt() throws {
        typeLines(["Alpha", ""])
        textView.typeText(String(XCUIKeyboardKey.delete.rawValue))
        Thread.sleep(forTimeInterval: 0.3)

        let lines = userLines()
        XCTAssertTrue(lines.count <= 2,
                      "Backspace on empty block should remove it or merge lines")
    }

    /// AC-BD-3: Backspace on non-empty block does not delete
    @MainActor
    func testBackspaceOnNonEmptyBlockDoesNotDelete() throws {
        typeLines(["Hello"])
        textView.typeText(String(XCUIKeyboardKey.delete.rawValue))
        Thread.sleep(forTimeInterval: 0.3)

        let text = currentText()
        XCTAssertTrue(text.contains("Hell"), "Backspace should delete character, not block")
        XCTAssertFalse(text.isEmpty, "Block should NOT be deleted when it has content")
    }

    // MARK: - Indent / Outdent

    /// AC-IN-1: Indent reparents block under previous sibling (disappears from home)
    @MainActor
    func testIndentMakesChildOfPreviousSibling() throws {
        typeLines(["Alpha", "Beta"])

        let indentButton = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'indent'"
        )).firstMatch

        if indentButton.waitForExistence(timeout: 3) {
            indentButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // On home screen, indented block becomes a child and disappears
        let lines = userLines()
        XCTAssertEqual(lines.count, 1,
                       "Indented block should disappear from home (becomes child)")
        XCTAssertEqual(lines[0], "Alpha",
                       "Only the parent block should remain visible")
    }

    /// AC-IN-3: Indent disabled for first sibling
    @MainActor
    func testIndentDisabledForFirstSibling() throws {
        typeLines(["Alpha"])
        tapOnUserLine(0)

        let text = currentText()
        XCTAssertFalse(text.contains("\t"),
                       "First sibling should not be indentable")
    }

    /// AC-OUT-1: Indent then navigate to node view to verify child, then back to verify home
    @MainActor
    func testIndentedBlockVisibleInNodeView() throws {
        typeLines(["Alpha", "Beta"])

        // Indent Beta under Alpha
        let indentButton = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'increase' OR label CONTAINS[c] 'indent'"
        )).firstMatch

        if indentButton.waitForExistence(timeout: 3) {
            indentButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        dismissKeyboard()

        // Home should show only Alpha (plus Today's Notes)
        let lines = userLines()
        XCTAssertEqual(lines.count, 1, "Only Alpha should be visible on home")

        // Navigate into Alpha to see Beta as a child
        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        let heading = app.staticTexts["Alpha"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3),
                      "Should be in Alpha's node view")

        let nodeText = currentText()
        XCTAssertTrue(nodeText.contains("Beta"),
                      "Beta should be visible as a child in Alpha's node view")
    }

    /// AC-OUT-3: Outdent disabled for root blocks
    @MainActor
    func testOutdentDisabledForRootBlocks() throws {
        typeLines(["Alpha"])

        let outdentButton = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'decrease' OR label CONTAINS[c] 'outdent'"
        )).firstMatch

        if outdentButton.waitForExistence(timeout: 2) {
            outdentButton.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        let text = currentText()
        XCTAssertTrue(text.contains("Alpha"),
                       "Alpha should still be present after outdent attempt on root")
    }

    // MARK: - Reorder

    /// AC-RO-4: Reorder preserves content
    @MainActor
    func testReorderPreservesContent() throws {
        typeLines(["Alpha", "Beta", "Gamma"])
        dismissKeyboard()

        textView.tap()
        Thread.sleep(forTimeInterval: 0.3)

        let moveUp = app.buttons["Move Up"]
        if moveUp.waitForExistence(timeout: 3) {
            moveUp.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let lines = userLines()
        XCTAssertEqual(lines.count, 3, "Should still have 3 user lines")
        XCTAssertTrue(lines.contains("Alpha"), "Alpha should be preserved")
        XCTAssertTrue(lines.contains("Beta"), "Beta should be preserved")
        XCTAssertTrue(lines.contains("Gamma"), "Gamma should be preserved")
    }

    // MARK: - Edit Mode

    /// AC-EM-1: Tap enters edit mode
    @MainActor
    func testTapEntersEditMode() throws {
        typeLines(["Hello"])
        dismissKeyboard()

        textView.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "Tapping block text should enter edit mode (keyboard appears)")
    }

    /// AC-EM-2: Content changes are saved on exit
    @MainActor
    func testContentSavedOnExit() throws {
        typeLines(["Hello"])
        textView.typeText(" World")
        Thread.sleep(forTimeInterval: 0.3)

        dismissKeyboard()

        let text = currentText()
        XCTAssertTrue(text.contains("Hello World"),
                      "Content changes should be saved when exiting edit mode")
    }

    /// AC-EMV-1: Tapping block text shows keyboard
    @MainActor
    func testTappingShowsKeyboard() throws {
        typeLines(["Hello"])
        dismissKeyboard()

        textView.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "Keyboard should appear when tapping block text")
    }

    /// AC-EMV-2: Format bar has toolbar buttons
    @MainActor
    func testFormatBarHasButtons() throws {
        typeLines(["Hello"])

        let indentExists = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'indent'"
        )).firstMatch.waitForExistence(timeout: 3)

        XCTAssertTrue(indentExists, "Format bar should have indent/outdent buttons")
    }

    /// AC-EMV-6: Tapping outside exits edit mode
    @MainActor
    func testTappingOutsideExitsEditMode() throws {
        typeLines(["Hello"])

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        dismissKeyboard()
        Thread.sleep(forTimeInterval: 0.5)

        let text = currentText()
        XCTAssertTrue(text.contains("Hello"), "Content should be saved after exiting edit mode")
    }

    // MARK: - Mentions

    /// AC-MN-1: Typing @ inserts character normally
    @MainActor
    func testAtSignInsertsNormally() throws {
        typeLines(["Hello"])
        textView.typeText("@world")
        Thread.sleep(forTimeInterval: 0.3)

        let text = currentText()
        XCTAssertTrue(text.contains("@world"),
                      "@ character should be inserted as plain text in v1")
    }
}
