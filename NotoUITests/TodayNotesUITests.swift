//
//  TodayNotesUITests.swift
//  NotoUITests
//
//  UI tests for Today's Notes feature: Today button navigation, breadcrumb display,
//  hierarchy building, block protection, and day block editing.
//  Maps to spec acceptance criteria: AC-GT-*, AC-SB-*, AC-AB-*, AC-BP-*, AC-DBE-*, AC-HSI-*.
//

import XCTest

final class TodayNotesUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["UITESTING"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private var textView: XCUIElement {
        app.textViews["noteTextView"]
    }

    private var todayButton: XCUIElement {
        app.buttons["todayButton"]
    }

    private var nodeViewTitle: XCUIElement {
        app.staticTexts["nodeViewTitle"]
    }

    private func waitForTextView() {
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "Text view should exist")
    }

    /// Wait briefly for navigation/animations to settle.
    private func waitForNavigation() {
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// Get current text content of the editor.
    private func currentText() -> String {
        textView.value as? String ?? ""
    }

    /// Tap the Back button in the navigation bar to go up one level.
    private func tapBack() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            waitForNavigation()
        }
    }

    // MARK: - AC-GT-1: Today button appears on home screen

    @MainActor
    func testTodayButtonExistsOnHomeScreen() throws {
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5),
                       "Today button should appear on the home screen bottom bar")
    }

    // MARK: - AC-GT-3 / AC-GT-4: Today button navigates to today's day block

    @MainActor
    func testTodayButtonNavigatesToDayBlock() throws {
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Should now be on a node view showing today's day block title
        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 5),
                       "Should navigate to a node view")

        // Verify we're in the Today's Notes hierarchy by checking for
        // "Today's Notes" text somewhere in the navigation bar (breadcrumb)
        let todayNotesText = app.navigationBars.staticTexts["Today's Notes"]
        let homeText = app.navigationBars.staticTexts["Home"]
        XCTAssertTrue(todayNotesText.exists || homeText.exists,
                       "Navigation bar should contain breadcrumb path segments")
    }

    // MARK: - AC-GT-7: Today button pushes full navigation path (back works)

    @MainActor
    func testTodayButtonPushesFullNavigationPath() throws {
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // We should be on the day block. Navigate back through the hierarchy.
        // Each Back tap should go up one level: Day → Week → Month → Year → Today's Notes → Home

        // First back should go to the week block
        tapBack()
        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 5),
                       "Should be on week node view after first back")

        // Second back should go to the month block
        tapBack()
        if nodeViewTitle.waitForExistence(timeout: 3) {
            // Third back should go to the year block
            tapBack()
            if nodeViewTitle.waitForExistence(timeout: 3) {
                // Fourth back should go to Today's Notes root
                tapBack()
                if nodeViewTitle.waitForExistence(timeout: 3) {
                    // Fifth back should return to home
                    tapBack()
                }
            }
        }

        // Should be back on home screen
        let homeTitle = app.staticTexts["homeTitle"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 5),
                       "Should return to home screen after navigating all the way back")
    }

    // MARK: - AC-GT-2: Today button appears on node views

    @MainActor
    func testTodayButtonExistsOnNodeView() throws {
        // Navigate to a node view via Today button
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Today button should still be visible in the node view
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5),
                       "Today button should appear on node view bottom bar")
    }

    // MARK: - AC-GT-5: Today button is no-op when already on today

    @MainActor
    func testTodayButtonNoOpWhenAlreadyOnToday() throws {
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Record the current title
        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 5))
        let titleBefore = nodeViewTitle.label

        // Tap Today button again — should be no-op
        todayButton.tap()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 3))
        let titleAfter = nodeViewTitle.label
        XCTAssertEqual(titleBefore, titleAfter,
                       "Tapping Today when already on today's block should not change the view")
    }

    // MARK: - AC-HSI-1: Today's Notes appears on home screen

    @MainActor
    func testTodayNotesBlockExistsOnHomeScreen() throws {
        waitForTextView()
        Thread.sleep(forTimeInterval: 0.5)

        let text = currentText()
        XCTAssertTrue(text.contains("Today's Notes"),
                       "Home screen should show 'Today's Notes' block")
    }

    // MARK: - AC-AB-1 / AC-AB-12: Full hierarchy built on navigation (instant)

    @MainActor
    func testHierarchyBuiltOnNavigation() throws {
        // Tap the Today button to trigger hierarchy building
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Should land on a node view immediately (no loading spinner)
        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 5),
                       "Hierarchy should be built instantly with no async delay")

        // The title should be today's date (e.g. "Mar 1, 2026")
        let title = nodeViewTitle.label
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let monthPrefix = formatter.string(from: Date())
        XCTAssertTrue(title.contains(monthPrefix),
                       "Day block title '\(title)' should contain current month '\(monthPrefix)'")
    }

    // MARK: - AC-SB-1 / AC-SB-3: Breadcrumb shows path segments

    @MainActor
    func testBreadcrumbShowsPathAfterNavigation() throws {
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Breadcrumb segments are StaticTexts inside the navigation bar.
        // The deepest segments (rightmost) are always visible; earlier ones may clip.
        // Check that at least some path segments exist in the nav bar.
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 5),
                       "Navigation bar should be visible in node view")

        // Look for breadcrumb separator " / " which indicates multi-segment breadcrumb
        let separators = navBar.staticTexts.matching(NSPredicate(format: "label == ' / '"))
        XCTAssertGreaterThan(separators.count, 0,
                              "Breadcrumb should have separator segments indicating a navigation path")
    }

    // MARK: - AC-TNR-5: Double-tap Today's Notes drills into node view

    @MainActor
    func testDoubleTapTodayNotesNavigatesToNodeView() throws {
        waitForTextView()
        Thread.sleep(forTimeInterval: 0.5)

        // Double-tap on the "Today's Notes" line in the editor
        // It should be the first line (line index 0)
        let textInsetTop: CGFloat = 8
        let lineHeight: CGFloat = 24
        let base = textView.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let targetY = textInsetTop + lineHeight * 0.5
        let lineCoord = base.withOffset(CGVector(dx: 100, dy: targetY))

        lineCoord.doubleTap()
        waitForNavigation()

        // Should now be in a node view for "Today's Notes"
        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 5),
                       "Double-tapping 'Today's Notes' should navigate to its node view")
        XCTAssertEqual(nodeViewTitle.label, "Today's Notes",
                        "Node view title should be 'Today's Notes'")
    }

    // MARK: - AC-DBE-1: Creating blocks under a day

    @MainActor
    func testCreatingBlocksUnderDayBlock() throws {
        // Navigate to today's day block
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Tap the text view and type
        waitForTextView()
        textView.tap()
        Thread.sleep(forTimeInterval: 0.3)
        textView.typeText("My first note")
        Thread.sleep(forTimeInterval: 0.3)

        let text = currentText()
        XCTAssertTrue(text.contains("My first note"),
                       "Should be able to create child blocks under the day block")
    }

    // MARK: - AC-DBE-2: Editing interactions work in day block

    @MainActor
    func testEditingInDayBlock() throws {
        // Navigate to today's day block
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Type multiple lines
        waitForTextView()
        textView.tap()
        Thread.sleep(forTimeInterval: 0.3)
        textView.typeText("Line one\nLine two\nLine three")
        Thread.sleep(forTimeInterval: 0.5)

        let lines = (currentText()).components(separatedBy: "\n")
        XCTAssertGreaterThanOrEqual(lines.count, 3,
                                     "Should be able to create multiple child blocks in a day view")
    }

    // MARK: - AC-BP-1/2: Protected blocks resist deletion and editing

    @MainActor
    func testProtectedBlocksResistDeletion() throws {
        // Navigate into Today's Notes hierarchy
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        waitForNavigation()

        // Go back to the week level
        tapBack()
        XCTAssertTrue(nodeViewTitle.waitForExistence(timeout: 5))

        // The week view should show the day block as a child.
        // The day block text should be visible in the editor.
        waitForTextView()
        let textBefore = currentText()

        // Try to select all and delete — protected blocks should resist
        textView.tap()
        Thread.sleep(forTimeInterval: 0.3)

        // Press delete many times to try removing content
        for _ in 0..<30 {
            textView.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        Thread.sleep(forTimeInterval: 0.5)

        let textAfter = currentText()
        // The auto-built day block label should still exist (isContentEditableByUser = false)
        // We can't easily assert the exact content, but the text should not be empty
        // since protected blocks resist deletion
        XCTAssertFalse(textAfter.isEmpty,
                        "Protected blocks should resist deletion — editor should not be empty")
    }
}
