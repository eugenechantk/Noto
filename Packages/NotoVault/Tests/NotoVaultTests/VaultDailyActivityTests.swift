import Foundation
import Testing
@testable import NotoVault

@Suite("Daily activity totals")
struct VaultDailyActivityTests {
    @Test func totalsSurviveCodingAndUndoIsIndependent() throws {
        var activity = VaultDailyActivity()
        let date = Date()
        activity.record(.filed, at: date)
        activity.record(.processed, at: date)
        activity.record(.filed, delta: -1, at: date)
        let restored = try JSONDecoder().decode(VaultDailyActivity.self, from: JSONEncoder().encode(activity))
        #expect(restored.count(.filed, on: date) == 0)
        #expect(restored.count(.processed, on: date) == 1)
    }
    @Test func newLocalDayResetsTotalsAndOldUndoCannotChangeToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
        let yesterday = try #require(ISO8601DateFormatter().date(from: "2026-10-17T15:59:59Z"))
        let today = yesterday.addingTimeInterval(2)
        var activity = VaultDailyActivity()
        activity.record(.filed, at: yesterday, calendar: calendar)
        #expect(activity.count(.filed, on: today, calendar: calendar) == 0)
        activity.record(.processed, at: today, calendar: calendar)
        activity.record(.filed, delta: -1, at: yesterday, calendar: calendar)
        #expect(activity.count(.processed, on: today, calendar: calendar) == 1)
        #expect(activity.count(.filed, on: today, calendar: calendar) == 0)
    }
}
