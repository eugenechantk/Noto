//
//  NavigationUITests.swift
//  NotoUITests
//
//  Cross-page XCUITests that verify flows spanning the home screen and node view.
//  Covers: double-tap navigation, nested drill-down, back button, content
//  preservation across navigation, and editing round-trips.
//
//  NOTE: The home screen always contains a "Today's Notes" root block (line 0).
//  All helpers account for this auto-created block.
//

import XCTest

final class NavigationUITests: XCTestCase {

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
        doubleTapLine(userLineIndex + 1)
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

    private func tapBackButton() {
        // Custom Liquid Glass back button with accessibility label "Back"
        let backButton = app.buttons["Back"]
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - Home → Node View

    /// AC-NAV-1: Double-tap pushes node view
    @MainActor
    func testDoubleTapPushesNodeView() throws {
        typeLines(["Topic A"])
        dismissKeyboard()

        doubleTapUserLine(0)

        let heading = app.staticTexts["Topic A"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3),
                      "Double-tap should push node view with heading")
    }

    /// AC-NAV-2: Nested double-tap continues drill-down
    @MainActor
    func testNestedDoubleTapDrillDown() throws {
        typeLines(["Topic A"])
        dismissKeyboard()

        // Navigate to Topic A
        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        // Create child in node view
        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Subtopic B")
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        // Double-tap child to drill down further
        doubleTapLine(0)

        let heading = app.staticTexts["Subtopic B"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3),
                      "Nested double-tap should drill into subtopic")
    }

    // MARK: - Node View → Home (Back Navigation)

    /// AC-NAV-3: Back button pops to previous screen
    @MainActor
    func testBackButtonPops() throws {
        typeLines(["Topic A"])
        dismissKeyboard()

        doubleTapUserLine(0)

        let heading = app.staticTexts["Topic A"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))

        tapBackButton()

        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 3),
                      "Back button should return to home screen")
    }

    /// AC-NAV-4: Back from first node returns to home
    @MainActor
    func testBackFromFirstNodeReturnsHome() throws {
        typeLines(["Topic A"])
        dismissKeyboard()

        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        tapBackButton()

        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 3),
                      "Should return to home screen with 'Home' title")

        let text = currentText()
        XCTAssertTrue(text.contains("Topic A"), "Content should be preserved after navigation")
    }

    // MARK: - Content Preservation Across Navigation

    /// Verify that creating content on home, navigating to node, and coming back preserves home content
    @MainActor
    func testHomeContentPreservedAfterNodeVisit() throws {
        typeLines(["Alpha", "Beta", "Gamma"])
        dismissKeyboard()

        // Navigate into Alpha
        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        // Come back
        tapBackButton()

        let text = currentText()
        XCTAssertTrue(text.contains("Alpha"), "Alpha should be preserved")
        XCTAssertTrue(text.contains("Beta"), "Beta should be preserved")
        XCTAssertTrue(text.contains("Gamma"), "Gamma should be preserved")
    }

    /// Verify that edits made in node view persist when navigating back and re-entering
    @MainActor
    func testNodeEditsPersistedAcrossNavigation() throws {
        typeLines(["Parent"])
        dismissKeyboard()

        // Navigate to Parent node view
        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        // Create a child
        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Child created")
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        // Go back to home
        tapBackButton()
        Thread.sleep(forTimeInterval: 0.5)

        // Re-navigate to Parent
        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        // The child should still be there
        let text = currentText()
        XCTAssertTrue(text.contains("Child created"),
                      "Child created in node view should persist after round-trip navigation")
    }

    /// Verify deep navigation: Home → Node A → Child B → back → back → Home
    @MainActor
    func testDeepNavigationRoundTrip() throws {
        typeLines(["Node A"])
        dismissKeyboard()

        // Navigate to Node A
        doubleTapUserLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        // Create child in Node A
        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Child B")
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        // Navigate to Child B
        doubleTapLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        let childHeading = app.staticTexts["Child B"]
        XCTAssertTrue(childHeading.waitForExistence(timeout: 3),
                      "Should be in Child B's node view")

        // Back to Node A
        tapBackButton()
        let nodeAHeading = app.staticTexts["Node A"]
        XCTAssertTrue(nodeAHeading.waitForExistence(timeout: 3),
                      "Should be back in Node A's node view")

        // Back to Home
        tapBackButton()
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 3),
                      "Should be back on home screen")
    }
}
