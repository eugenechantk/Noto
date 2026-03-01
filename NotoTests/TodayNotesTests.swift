//
//  TodayNotesTests.swift
//  NotoTests
//
//  Unit tests for BlockBuilder, TodayNotesService, date logic, and integration.
//

import Testing
import Foundation
import SwiftData
@testable import Noto

// MARK: - BlockBuilder Tests

struct BlockBuilderTests {

    @Test @MainActor
    func testBuildPathCreatesFullPath() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let steps = [
            BuildStep(content: "Level 1", sortOrder: 1.0),
            BuildStep(content: "Level 2", sortOrder: 1.0),
            BuildStep(content: "Level 3", sortOrder: 1.0),
        ]

        let deepest = BlockBuilder.buildPath(root: root, path: steps, context: context)

        #expect(deepest.content == "Level 3")
        #expect(deepest.depth == 3)
        #expect(deepest.parent?.content == "Level 2")
        #expect(deepest.parent?.parent?.content == "Level 1")
        #expect(deepest.parent?.parent?.parent?.id == root.id)
    }

    @Test @MainActor
    func testBuildPathReusesExistingBlocks() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let existing = Block(content: "Level 1", parent: root, sortOrder: 1.0)
        context.insert(existing)
        try context.save()

        let steps = [
            BuildStep(content: "Level 1", sortOrder: 1.0),
            BuildStep(content: "Level 2", sortOrder: 1.0),
        ]

        let deepest = BlockBuilder.buildPath(root: root, path: steps, context: context)

        #expect(deepest.content == "Level 2")
        #expect(deepest.parent?.id == existing.id) // Reused, not duplicated
        #expect(root.children.count == 1) // Still just one child
    }

    @Test @MainActor
    func testBuildPathIdempotent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let steps = [
            BuildStep(content: "A", sortOrder: 1.0),
            BuildStep(content: "B", sortOrder: 1.0),
        ]

        let first = BlockBuilder.buildPath(root: root, path: steps, context: context)
        let second = BlockBuilder.buildPath(root: root, path: steps, context: context)

        #expect(first.id == second.id)
        #expect(root.children.count == 1)
    }

    @Test @MainActor
    func testBuildPathSetsCorrectDepth() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let steps = [
            BuildStep(content: "D1", sortOrder: 1.0),
            BuildStep(content: "D2", sortOrder: 1.0),
        ]

        let deepest = BlockBuilder.buildPath(root: root, path: steps, context: context)

        #expect(deepest.depth == 2)
        #expect(deepest.parent?.depth == 1)
    }

    @Test @MainActor
    func testBuildPathUsesProvidedSortOrder() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let steps = [
            BuildStep(content: "Child", sortOrder: 42.0),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.sortOrder == 42.0)
    }

    @Test @MainActor
    func testBuildPathSetsProtectionProperties() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let steps = [
            BuildStep(
                content: "Protected",
                sortOrder: 1.0,
                isDeletable: false,
                isContentEditableByUser: false,
                isReorderable: false,
                isMovable: false
            ),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.isDeletable == false)
        #expect(result.isContentEditableByUser == false)
        #expect(result.isReorderable == false)
        #expect(result.isMovable == false)
    }

    @Test @MainActor
    func testBuildPathSetsExtensionData() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let testData = "test".data(using: .utf8)!
        let steps = [
            BuildStep(content: "WithData", sortOrder: 1.0, extensionData: testData),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.extensionData == testData)
    }

    @Test @MainActor
    func testBuildPathIgnoresArchivedBlocks() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let archived = Block(content: "Alpha", parent: root, sortOrder: 1.0, isArchived: true)
        context.insert(archived)
        try context.save()

        let steps = [
            BuildStep(content: "Alpha", sortOrder: 2.0),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.id != archived.id) // Created new, not reused archived
        #expect(result.isArchived == false)
    }

    @Test @MainActor
    func testBuildPathExactContentMatch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let partial = Block(content: "Alpha Beta", parent: root, sortOrder: 1.0)
        context.insert(partial)
        try context.save()

        let steps = [
            BuildStep(content: "Alpha", sortOrder: 2.0, matchStrategy: .exactContent),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.content == "Alpha") // New block created
        #expect(result.id != partial.id)   // Not matched against "Alpha Beta"
    }

    @Test @MainActor
    func testDateAwareMatchingDay() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let userCreated = Block(content: "March 1", parent: root, sortOrder: 1.0)
        context.insert(userCreated)
        try context.save()

        let steps = [
            BuildStep(content: "Mar 1, 2026", sortOrder: 1.0, matchStrategy: .dateAware(.day)),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.id == userCreated.id)         // Matched
        #expect(result.content == "Mar 1, 2026")     // Renamed to canonical
    }

    @Test @MainActor
    func testDateAwareMatchingMonth() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let userCreated = Block(content: "Mar", parent: root, sortOrder: 1.0)
        context.insert(userCreated)
        try context.save()

        let steps = [
            BuildStep(content: "March", sortOrder: 3.0, matchStrategy: .dateAware(.month)),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.id == userCreated.id)    // Matched
        #expect(result.content == "March")       // Renamed to canonical
    }

    @Test @MainActor
    func testDateAwareMatchingWeek() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let userCreated = Block(content: "Week 1", parent: root, sortOrder: 1.0)
        context.insert(userCreated)
        try context.save()

        let steps = [
            BuildStep(content: "Week 1 (2/3 - 8/3)", sortOrder: 1.0, matchStrategy: .dateAware(.week)),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.id == userCreated.id)                // Matched
        #expect(result.content == "Week 1 (2/3 - 8/3)")    // Renamed
    }

    @Test @MainActor
    func testDateAwareNoMatchOnUnparseable() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let userCreated = Block(content: "My March Notes", parent: root, sortOrder: 1.0)
        context.insert(userCreated)
        try context.save()

        let steps = [
            BuildStep(content: "March", sortOrder: 3.0, matchStrategy: .dateAware(.month)),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.id != userCreated.id)    // Not matched
        #expect(result.content == "March")       // New block created
    }

    @Test @MainActor
    func testDateAwareRenamePreservesIdentity() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let day = Block(content: "March 1", parent: root, sortOrder: 1.0)
        context.insert(day)

        let child = Block(content: "Idea A", parent: day, sortOrder: 1.0)
        context.insert(child)
        try context.save()

        let originalId = day.id

        let steps = [
            BuildStep(content: "Mar 1, 2026", sortOrder: 1.0, matchStrategy: .dateAware(.day)),
        ]

        let result = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(result.id == originalId)           // Same block
        #expect(result.content == "Mar 1, 2026")   // Renamed
        #expect(result.children.count == 1)         // Children preserved
        #expect(result.children.first?.content == "Idea A")
    }
}

// MARK: - TodayNotesService Date Formatting Tests

struct TodayNotesDateTests {

    @Test
    func testYearContentFormat() {
        #expect(TodayNotesService.formatYear(2026) == "2026")
        #expect(TodayNotesService.formatYear(2027) == "2027")
    }

    @Test
    func testMonthContentFormat() {
        #expect(TodayNotesService.formatMonth(1) == "January")
        #expect(TodayNotesService.formatMonth(3) == "March")
        #expect(TodayNotesService.formatMonth(12) == "December")
    }

    @Test
    func testDayContentFormat() {
        let cal = TodayNotesService.calendar
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let date = cal.date(from: components)!

        let result = TodayNotesService.formatDay(date, calendar: cal)
        #expect(result == "Mar 1, 2026")
    }

    @Test
    func testWeekBoundariesMondayToSunday() {
        let cal = TodayNotesService.calendar

        // March 1, 2026 is a Sunday
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let sunday = cal.date(from: components)!

        let monday = TodayNotesService.mondayOfWeek(containing: sunday, calendar: cal)
        let mondayWeekday = cal.component(.weekday, from: monday)
        #expect(mondayWeekday == 2) // Monday

        // The Monday should be Feb 23, 2026
        #expect(cal.component(.day, from: monday) == 23)
        #expect(cal.component(.month, from: monday) == 2)
    }

    @Test
    func testWeekAssignedToMondayMonth() {
        let cal = TodayNotesService.calendar

        // Mar 1, 2026 is Sunday; its Monday is Feb 23
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let date = cal.date(from: components)!

        let steps = TodayNotesService.buildSteps(for: date, calendar: cal)

        // Month step should be "February" (the month of Monday Feb 23)
        #expect(steps[1].content == "February")
    }

    @Test
    func testWeekNumberResetsPerMonth() {
        let cal = TodayNotesService.calendar

        // First Monday of March 2026 is March 2
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let firstMonday = cal.date(from: components)!
        let weekNum = TodayNotesService.weekNumberInMonth(for: firstMonday, calendar: cal)
        #expect(weekNum == 1)

        // Second Monday of March 2026 is March 9
        components.day = 9
        let secondMonday = cal.date(from: components)!
        let weekNum2 = TodayNotesService.weekNumberInMonth(for: secondMonday, calendar: cal)
        #expect(weekNum2 == 2)
    }

    @Test
    func testWeekContentFormat() {
        let cal = TodayNotesService.calendar

        // March 2, 2026 (Monday)
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let date = cal.date(from: components)!

        let steps = TodayNotesService.buildSteps(for: date, calendar: cal)
        let weekStep = steps[2]
        #expect(weekStep.content == "Week 1 (2/3 - 8/3)")
    }

    @Test
    func testWeekSortOrder() {
        let cal = TodayNotesService.calendar

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let week1Date = cal.date(from: components)!

        components.day = 9
        let week2Date = cal.date(from: components)!

        let steps1 = TodayNotesService.buildSteps(for: week1Date, calendar: cal)
        let steps2 = TodayNotesService.buildSteps(for: week2Date, calendar: cal)

        #expect(steps1[2].sortOrder < steps2[2].sortOrder)
    }

    @Test
    func testDaySortOrder() {
        let cal = TodayNotesService.calendar

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let day1 = cal.date(from: components)!

        components.day = 3
        let day2 = cal.date(from: components)!

        let steps1 = TodayNotesService.buildSteps(for: day1, calendar: cal)
        let steps2 = TodayNotesService.buildSteps(for: day2, calendar: cal)

        #expect(steps1[3].sortOrder < steps2[3].sortOrder)
    }

    @Test
    func testMonthSortOrder() {
        let cal = TodayNotesService.calendar

        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        let janDate = cal.date(from: components)!

        components.month = 3
        components.day = 2
        let marDate = cal.date(from: components)!

        let stepsJan = TodayNotesService.buildSteps(for: janDate, calendar: cal)
        let stepsMar = TodayNotesService.buildSteps(for: marDate, calendar: cal)

        #expect(stepsJan[1].sortOrder < stepsMar[1].sortOrder)
    }

    @Test
    func testYearSortOrder() {
        let cal = TodayNotesService.calendar

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let date2026 = cal.date(from: components)!

        components.year = 2027
        components.month = 1
        components.day = 4
        let date2027 = cal.date(from: components)!

        let steps2026 = TodayNotesService.buildSteps(for: date2026, calendar: cal)
        let steps2027 = TodayNotesService.buildSteps(for: date2027, calendar: cal)

        #expect(steps2026[0].sortOrder < steps2027[0].sortOrder)
    }
}

// MARK: - Today's Notes Building Integration Tests

struct TodayNotesBuildingTests {

    @Test @MainActor
    func testBuildTodayCreatesFullHierarchy() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        // March 2, 2026 (Monday)
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let date = cal.date(from: components)!

        let dayBlock = TodayNotesService.buildHierarchy(root: root, for: date, context: context)

        #expect(dayBlock.content == "Mar 2, 2026")
        #expect(dayBlock.depth == 4)
        #expect(dayBlock.parent?.content.hasPrefix("Week 1") == true)
        #expect(dayBlock.parent?.parent?.content == "March")
        #expect(dayBlock.parent?.parent?.parent?.content == "2026")
        #expect(dayBlock.parent?.parent?.parent?.parent?.id == root.id)
    }

    @Test @MainActor
    func testBuildTodayIdempotent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let date = cal.date(from: components)!

        let first = TodayNotesService.buildHierarchy(root: root, for: date, context: context)
        let second = TodayNotesService.buildHierarchy(root: root, for: date, context: context)

        #expect(first.id == second.id)
        #expect(root.children.count == 1) // Only one year
    }

    @Test @MainActor
    func testBuildNewDaySameWeek() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let mon = cal.date(from: components)!
        let _ = TodayNotesService.buildHierarchy(root: root, for: mon, context: context)

        components.day = 3
        let tue = cal.date(from: components)!
        let tueDayBlock = TodayNotesService.buildHierarchy(root: root, for: tue, context: context)

        #expect(tueDayBlock.content == "Mar 3, 2026")
        // Same week block should have 2 day children now
        let weekBlock = tueDayBlock.parent!
        #expect(weekBlock.children.count == 2)
        // Still only 1 year, 1 month, 1 week
        #expect(root.children.count == 1)
    }

    @Test @MainActor
    func testBuildNewWeekSameMonth() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let week1Date = cal.date(from: components)!
        let _ = TodayNotesService.buildHierarchy(root: root, for: week1Date, context: context)

        components.day = 9
        let week2Date = cal.date(from: components)!
        let week2Day = TodayNotesService.buildHierarchy(root: root, for: week2Date, context: context)

        #expect(week2Day.content == "Mar 9, 2026")
        // March should now have 2 week blocks
        let monthBlock = week2Day.parent!.parent!
        #expect(monthBlock.content == "March")
        #expect(monthBlock.children.count == 2)
    }

    @Test @MainActor
    func testBuildNewMonth() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let marDate = cal.date(from: components)!
        let _ = TodayNotesService.buildHierarchy(root: root, for: marDate, context: context)

        components.month = 4
        components.day = 6
        let aprDate = cal.date(from: components)!
        let aprDay = TodayNotesService.buildHierarchy(root: root, for: aprDate, context: context)

        #expect(aprDay.content == "Apr 6, 2026")
        // Year should now have 2 months
        let yearBlock = aprDay.parent!.parent!.parent!
        #expect(yearBlock.content == "2026")
        #expect(yearBlock.children.count == 2)
    }

    @Test @MainActor
    func testBuildNewYear() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let date2026 = cal.date(from: components)!
        let _ = TodayNotesService.buildHierarchy(root: root, for: date2026, context: context)

        components.year = 2027
        components.month = 1
        components.day = 4
        let date2027 = cal.date(from: components)!
        let day2027 = TodayNotesService.buildHierarchy(root: root, for: date2027, context: context)

        #expect(day2027.content == "Jan 4, 2027")
        // Root should now have 2 year blocks
        #expect(root.children.count == 2)
    }

    @Test @MainActor
    func testBuildCrossMonthWeek() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        // Mar 1, 2026 is Sunday — its Monday is Feb 23
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let date = cal.date(from: components)!

        let dayBlock = TodayNotesService.buildHierarchy(root: root, for: date, context: context)

        #expect(dayBlock.content == "Mar 1, 2026")
        // Week belongs to February (Monday's month)
        let monthBlock = dayBlock.parent!.parent!
        #expect(monthBlock.content == "February")
    }

    @Test @MainActor
    func testAutoBuiltBlocksAreProtected() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let cal = TodayNotesService.calendar

        let root = TodayNotesService.ensureRoot(context: context)

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2
        let date = cal.date(from: components)!

        let dayBlock = TodayNotesService.buildHierarchy(root: root, for: date, context: context)
        let weekBlock = dayBlock.parent!
        let monthBlock = weekBlock.parent!
        let yearBlock = monthBlock.parent!

        // All structural blocks should be protected
        for block in [root, yearBlock, monthBlock, weekBlock, dayBlock] {
            #expect(block.isDeletable == false, "Block '\(block.content)' should not be deletable")
            #expect(block.isContentEditableByUser == false, "Block '\(block.content)' should not be content-editable")
            #expect(block.isReorderable == false, "Block '\(block.content)' should not be reorderable")
            #expect(block.isMovable == false, "Block '\(block.content)' should not be movable")
        }
    }
}

// MARK: - Today's Notes Root Tests

struct TodayNotesRootTests {

    @Test @MainActor
    func testRootCreatedOnLaunch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = TodayNotesService.ensureRoot(context: context)

        #expect(root.content == "Today's Notes")
        #expect(root.parent == nil)
        #expect(root.depth == 0)
        #expect(root.sortOrder == Double.leastNormalMagnitude)
    }

    @Test @MainActor
    func testRootIdempotent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let first = TodayNotesService.ensureRoot(context: context)
        let second = TodayNotesService.ensureRoot(context: context)

        #expect(first.id == second.id)
    }

    @Test @MainActor
    func testRootPinnedFirst() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Create some regular blocks first
        let alpha = Block(content: "Alpha", sortOrder: 1.0)
        let beta = Block(content: "Beta", sortOrder: 2.0)
        context.insert(alpha)
        context.insert(beta)
        try context.save()

        let root = TodayNotesService.ensureRoot(context: context)

        // Today's Notes should sort before Alpha and Beta
        #expect(root.sortOrder < alpha.sortOrder)
        #expect(root.sortOrder < beta.sortOrder)
    }

    @Test @MainActor
    func testRootIsProtected() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = TodayNotesService.ensureRoot(context: context)

        #expect(root.isDeletable == false)
        #expect(root.isContentEditableByUser == false)
        #expect(root.isReorderable == false)
        #expect(root.isMovable == false)
    }
}
