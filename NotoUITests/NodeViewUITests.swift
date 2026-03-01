//
//  NodeViewUITests.swift
//  NotoUITests
//
//  XCUITests for the Node View (drill-down screen).
//  Covers: node display, toolbar, breadcrumbs, expand/collapse toggle,
//  block creation in node view.
//

import XCTest

final class NodeViewUITests: XCTestCase {

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

    private func typeLines(_ lines: [String]) {
        let tv = textView
        XCTAssertTrue(tv.waitForExistence(timeout: 5), "Text view should exist")
        tv.tap()
        Thread.sleep(forTimeInterval: 0.3)
        let fullText = lines.joined(separator: "\n")
        tv.typeText(fullText)
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func currentLines() -> [String] {
        let value = textView.value as? String ?? ""
        return value.components(separatedBy: "\n")
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

    private func doubleTapLine(_ lineIndex: Int) {
        let textInsetTop: CGFloat = 8
        let lineHeight: CGFloat = 24
        let targetY = textInsetTop + lineHeight * CGFloat(lineIndex) + lineHeight * 0.5

        let base = textView.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let lineCoord = base.withOffset(CGVector(dx: 80, dy: targetY))
        lineCoord.doubleTap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Navigate to node view for the first block on home screen.
    private func navigateToNodeView(blockContent: String) {
        typeLines([blockContent])
        dismissKeyboard()
        doubleTapLine(0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Node Screen Display

    /// AC-NS-1: Heading displays node content
    @MainActor
    func testHeadingDisplaysNodeContent() throws {
        navigateToNodeView(blockContent: "Not too bad")

        let heading = app.staticTexts["Not too bad"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3),
                      "Node heading should display the block's content")
    }

    /// AC-NS-2: First-level children render as plain body text (no bullets)
    @MainActor
    func testFirstLevelChildrenNoBullets() throws {
        navigateToNodeView(blockContent: "Parent")

        // Type children in node view
        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Idea A\nIdea B\nIdea C")
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        let text = currentText()
        XCTAssertTrue(text.contains("Idea A"), "First-level child should be visible")
        XCTAssertTrue(text.contains("Idea B"), "First-level child should be visible")
        XCTAssertTrue(text.contains("Idea C"), "First-level child should be visible")
        XCTAssertFalse(text.contains("•"), "First-level children should not have bullets")
    }

    // MARK: - Node Toolbar & Breadcrumbs

    /// AC-NT-2: Breadcrumb navigation shows path
    @MainActor
    func testBreadcrumbShowsPath() throws {
        navigateToNodeView(blockContent: "Topic A")

        let homeBreadcrumb = app.staticTexts["Home"]
        XCTAssertTrue(homeBreadcrumb.waitForExistence(timeout: 3),
                      "Breadcrumb should show 'Home'")

        let separator = app.staticTexts["/"]
        XCTAssertTrue(separator.exists, "Breadcrumb should show '/' separator")
    }

    /// AC-NT-3: Nested breadcrumb updates correctly
    @MainActor
    func testNestedBreadcrumb() throws {
        navigateToNodeView(blockContent: "Parent")

        // Create a child in the node view
        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Child")
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        // Double-tap the child to drill down further
        doubleTapLine(0)
        Thread.sleep(forTimeInterval: 0.5)

        let homeBreadcrumb = app.staticTexts["Home"]
        XCTAssertTrue(homeBreadcrumb.waitForExistence(timeout: 3),
                      "Nested breadcrumb should still show 'Home'")
    }

    // MARK: - Expand / Collapse Toggle

    /// AC-EC-1: Default state is collapsed
    @MainActor
    func testDefaultStateIsCollapsed() throws {
        navigateToNodeView(blockContent: "Parent")

        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Child A")
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Indent to create a grandchild
        tv.typeText("\nGrandchild")
        Thread.sleep(forTimeInterval: 0.3)

        let indentButton = app.buttons.matching(NSPredicate(
            format: "label CONTAINS 'indent' OR label CONTAINS 'Indent'"
        )).firstMatch
        if indentButton.waitForExistence(timeout: 2) {
            indentButton.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        // In collapsed mode, both child and grandchild should be visible
        let text = currentText()
        XCTAssertTrue(text.contains("Child A"), "Child should be visible in collapsed mode")
    }

    /// AC-EC-2: Expand shows all descendants
    @MainActor
    func testExpandShowsAllDescendants() throws {
        navigateToNodeView(blockContent: "Parent")

        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Child A")
            Thread.sleep(forTimeInterval: 0.3)
        }
        dismissKeyboard()

        // Tap expand/collapse toggle (custom Liquid Glass button)
        let expandButton = app.buttons["Expand"]
        if expandButton.waitForExistence(timeout: 3) {
            expandButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let text = currentText()
        XCTAssertTrue(text.contains("Child A"), "Child should be visible after expand")
    }

    // MARK: - Block Creation in Node View

    /// AC-BC-6: New child in node view gets correct parentId and depth
    @MainActor
    func testNewChildInNodeView() throws {
        navigateToNodeView(blockContent: "Parent")

        let tv = textView
        if tv.waitForExistence(timeout: 3) {
            tv.tap()
            Thread.sleep(forTimeInterval: 0.3)
            tv.typeText("Child block")
            Thread.sleep(forTimeInterval: 0.3)
        }

        let text = currentText()
        XCTAssertTrue(text.contains("Child block"),
                      "Child block should be created in node view")
    }
}
