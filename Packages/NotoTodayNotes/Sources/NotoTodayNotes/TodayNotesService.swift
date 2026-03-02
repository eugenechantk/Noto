//
//  TodayNotesService.swift
//  NotoTodayNotes
//
//  Today's Notes-specific date formatting and build path construction.
//  Uses BlockBuilder for the actual block creation.
//

import Foundation
import SwiftData
import os.log
import NotoModels
import NotoCore

private let logger = Logger(subsystem: "com.noto", category: "TodayNotesService")

public struct TodayNotesService {

    // MARK: - Root Block

    /// Ensure the "Today's Notes" root block exists. Creates it on first launch.
    @MainActor
    public static func ensureRoot(context: ModelContext) -> Block {
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                block.parent == nil && block.content == "Today's Notes" && !block.isArchived
            }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let root = Block(
            content: "Today's Notes",
            sortOrder: Double.leastNormalMagnitude,
            isDeletable: false,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(root)
        logger.info("Created Today's Notes root block")
        return root
    }

    // MARK: - Build Today's Hierarchy

    /// Build the Year -> Month -> Week -> Day hierarchy for the given date.
    /// Returns the day block. Creates any missing blocks along the way.
    @MainActor
    public static func buildHierarchy(root: Block, for date: Date, context: ModelContext) -> Block {
        let cal = calendar
        let steps = buildSteps(for: date, calendar: cal)

        let dayBlock = BlockBuilder.buildPath(root: root, path: steps, context: context)
        logger.debug("Built hierarchy for \(formatDay(date, calendar: cal))")
        return dayBlock
    }

    /// Ensure root exists and build today's hierarchy in one call.
    @MainActor
    public static func ensureToday(context: ModelContext, date: Date = Date()) -> Block {
        let root = ensureRoot(context: context)
        return buildHierarchy(root: root, for: date, context: context)
    }

    // MARK: - Build Steps

    /// Construct the 4-step build path for a given date.
    public static func buildSteps(for date: Date, calendar cal: Calendar = calendar) -> [BuildStep] {
        let year = cal.component(.year, from: date)

        // Find the Monday of the week containing this date
        let monday = mondayOfWeek(containing: date, calendar: cal)
        let mondayMonth = cal.component(.month, from: monday)

        // Week belongs to the month of its Monday
        let weekNumber = weekNumberInMonth(for: monday, calendar: cal)
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!

        return [
            // Year step
            BuildStep(
                content: formatYear(year),
                sortOrder: Double(year),
                matchStrategy: .dateAware(.year)
            ),
            // Month step (use Monday's month for cross-month weeks)
            BuildStep(
                content: formatMonth(mondayMonth),
                sortOrder: Double(mondayMonth),
                matchStrategy: .dateAware(.month)
            ),
            // Week step
            BuildStep(
                content: formatWeek(number: weekNumber, monday: monday, sunday: sunday, calendar: cal),
                sortOrder: Double(weekNumber),
                matchStrategy: .dateAware(.week)
            ),
            // Day step
            BuildStep(
                content: formatDay(date, calendar: cal),
                sortOrder: Double(cal.component(.day, from: date)),
                matchStrategy: .dateAware(.day)
            ),
        ]
    }

    // MARK: - Calendar

    /// Gregorian calendar with Monday as first weekday.
    public static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }

    // MARK: - Date Formatting

    /// Format year: "2026"
    public static func formatYear(_ year: Int) -> String {
        "\(year)"
    }

    /// Format month: full name, e.g. "March"
    public static func formatMonth(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.monthSymbols[month - 1]
    }

    /// Format week: "Week N (D/M - D/M)"
    public static func formatWeek(number: Int, monday: Date, sunday: Date, calendar cal: Calendar) -> String {
        let monDay = cal.component(.day, from: monday)
        let monMonth = cal.component(.month, from: monday)
        let sunDay = cal.component(.day, from: sunday)
        let sunMonth = cal.component(.month, from: sunday)
        return "Week \(number) (\(monDay)/\(monMonth) - \(sunDay)/\(sunMonth))"
    }

    /// Format day: "MMM D, YYYY" e.g. "Mar 1, 2026"
    public static func formatDay(_ date: Date, calendar cal: Calendar = calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Week Calculations

    /// Find the Monday of the week containing the given date.
    public static func mondayOfWeek(containing date: Date, calendar cal: Calendar) -> Date {
        let weekday = cal.component(.weekday, from: date)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        // Days to subtract to get to Monday
        let daysFromMonday: Int
        if weekday == 1 {
            daysFromMonday = 6 // Sunday -> previous Monday
        } else {
            daysFromMonday = weekday - 2 // Mon=0, Tue=1, ..., Sat=5
        }
        return cal.date(byAdding: .day, value: -daysFromMonday, to: cal.startOfDay(for: date))!
    }

    /// Calculate week number within a month (1-based).
    /// The first week whose Monday falls in the month is Week 1.
    public static func weekNumberInMonth(for monday: Date, calendar cal: Calendar) -> Int {
        let month = cal.component(.month, from: monday)
        let year = cal.component(.year, from: monday)

        // Find the first Monday in this month
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let firstOfMonth = cal.date(from: components)!

        let firstMonday: Date
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        if firstWeekday == 2 {
            // 1st is already Monday
            firstMonday = firstOfMonth
        } else {
            // Find the first Monday in or after the 1st
            let daysUntilMonday: Int
            if firstWeekday == 1 {
                daysUntilMonday = 1 // Sunday -> next Monday
            } else {
                daysUntilMonday = (9 - firstWeekday) % 7 // Tue(3)->6, Wed(4)->5, ...
            }
            firstMonday = cal.date(byAdding: .day, value: daysUntilMonday, to: firstOfMonth)!
        }

        // Count weeks from first Monday
        let daysBetween = cal.dateComponents([.day], from: firstMonday, to: monday).day!
        return (daysBetween / 7) + 1
    }
}
