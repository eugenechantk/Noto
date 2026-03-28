//
//  SearchUITests.swift
//  NotoUITests
//
//  XCUITests for the SearchSheet UI:
//  - Opening the search sheet via the bottom toolbar trigger
//  - Dismissing the search sheet
//  - Empty search state
//

import XCTest

final class SearchUITests: XCTestCase {

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

    /// Tap the search bar trigger in the bottom toolbar to open the search sheet.
    private func openSearchSheet() {
        let trigger = app.buttons["searchBarTrigger"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 5),
                      "Search bar trigger should exist in bottom toolbar")
        trigger.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Tests

    @MainActor
    func testSearchBarTriggerOpensSheet() throws {
        openSearchSheet()

        let searchField = app.textFields["searchTextField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "Search text field should appear after tapping search trigger")
    }

    @MainActor
    func testSearchDismiss() throws {
        openSearchSheet()

        let searchField = app.textFields["searchTextField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "Search text field should be visible")

        // Swipe down from the top of the sheet (near the drag indicator) to dismiss.
        // The search field is at the bottom, so swiping on it may not trigger dismissal.
        let topOfSheet = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        )
        let bottomOfScreen = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
        )
        topOfSheet.press(forDuration: 0.05, thenDragTo: bottomOfScreen)
        Thread.sleep(forTimeInterval: 1.0)

        XCTAssertFalse(searchField.exists,
                       "Search text field should no longer exist after dismissing sheet")
    }

    @MainActor
    func testEmptySearchShowsNoResults() throws {
        openSearchSheet()

        let searchField = app.textFields["searchTextField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        // Type a query and submit to trigger a search with no matching results
        searchField.typeText("zzzznonexistentquery")
        searchField.typeText("\n")
        Thread.sleep(forTimeInterval: 2.0)

        let noResults = app.staticTexts["noResultsText"]
        XCTAssertTrue(noResults.waitForExistence(timeout: 5),
                      "No results text should appear for a query with no matches")
    }
}
