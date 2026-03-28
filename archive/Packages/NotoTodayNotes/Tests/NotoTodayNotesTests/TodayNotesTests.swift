import Foundation
import SwiftData
import Testing
import NotoModels
import NotoCore
import NotoTodayNotes

struct TodayNotesPackageTests {
    @Test @MainActor
    func ensureRootIsIdempotent() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let first = TodayNotesService.ensureRoot(context: context)
        let second = TodayNotesService.ensureRoot(context: context)

        #expect(first.id == second.id)
        #expect(first.content == "Today's Notes")
    }

    @Test @MainActor
    func buildHierarchyCreatesYearMonthWeekDay() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = TodayNotesService.ensureRoot(context: context)

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 2
        let date = TodayNotesService.calendar.date(from: comps)!

        let dayBlock = TodayNotesService.buildHierarchy(root: root, for: date, context: context)

        #expect(dayBlock.parent != nil) // week
        #expect(dayBlock.parent?.parent != nil) // month
        #expect(dayBlock.parent?.parent?.parent != nil) // year
        #expect(dayBlock.parent?.parent?.parent?.parent?.id == root.id)
    }

    @Test
    func formattersProduceStableStrings() {
        #expect(TodayNotesService.formatYear(2026) == "2026")
        #expect(TodayNotesService.formatMonth(3) == "March")
    }
}
