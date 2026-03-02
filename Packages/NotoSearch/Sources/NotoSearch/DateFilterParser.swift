//
//  DateFilterParser.swift
//  NotoSearch
//
//  Extracts temporal phrases from query strings and returns
//  a cleaned query with an optional date range.
//

import Foundation

public struct DateFilterParser {

    private static let calendar = Calendar.current

    // MARK: - Pattern definitions

    /// Each pattern has a regex and a closure that produces a DateRange from the current date.
    private struct TemporalPattern {
        let regex: NSRegularExpression
        let dateRange: (Date) -> DateRange
    }

    private static let patterns: [TemporalPattern] = {
        var list: [TemporalPattern] = []

        // "today"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\btoday\b"#, options: .caseInsensitive),
            dateRange: { now in
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                return DateRange(start: start, end: end)
            }
        ))

        // "yesterday"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\byesterday\b"#, options: .caseInsensitive),
            dateRange: { now in
                let todayStart = calendar.startOfDay(for: now)
                let start = calendar.date(byAdding: .day, value: -1, to: todayStart)!
                return DateRange(start: start, end: todayStart)
            }
        ))

        // "last week"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\blast\s+week\b"#, options: .caseInsensitive),
            dateRange: { now in
                let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
                return DateRange(start: start, end: now)
            }
        ))

        // "this week"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\bthis\s+week\b"#, options: .caseInsensitive),
            dateRange: { now in
                let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                let start = calendar.date(from: comps)!
                return DateRange(start: start, end: now)
            }
        ))

        // "last month"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\blast\s+month\b"#, options: .caseInsensitive),
            dateRange: { now in
                let comps = calendar.dateComponents([.year, .month], from: now)
                let thisMonthStart = calendar.date(from: comps)!
                let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
                return DateRange(start: lastMonthStart, end: thisMonthStart)
            }
        ))

        // "this month"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\bthis\s+month\b"#, options: .caseInsensitive),
            dateRange: { now in
                let comps = calendar.dateComponents([.year, .month], from: now)
                let start = calendar.date(from: comps)!
                return DateRange(start: start, end: now)
            }
        ))

        // "last N days"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\blast\s+(\d+)\s+days?\b"#, options: .caseInsensitive),
            dateRange: { now in
                // Placeholder -- actual N is extracted at match time
                return DateRange(start: now, end: now)
            }
        ))

        // "recent" / "recently"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\brecent(?:ly)?\b"#, options: .caseInsensitive),
            dateRange: { now in
                let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
                return DateRange(start: start, end: now)
            }
        ))

        // "in <Month> <Year>" -- e.g. "in March 2024"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(
                pattern: #"\bin\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{4})\b"#,
                options: .caseInsensitive
            ),
            dateRange: { now in
                // Placeholder -- actual month/year extracted at match time
                return DateRange(start: now, end: now)
            }
        ))

        // "in <Month>" -- e.g. "in March" (current year)
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(
                pattern: #"\bin\s+(january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
                options: .caseInsensitive
            ),
            dateRange: { now in
                // Placeholder -- actual month extracted at match time
                return DateRange(start: now, end: now)
            }
        ))

        // "in <Year>" -- e.g. "in 2024"
        list.append(TemporalPattern(
            regex: try! NSRegularExpression(pattern: #"\bin\s+(\d{4})\b"#, options: .caseInsensitive),
            dateRange: { now in
                // Placeholder -- actual year extracted at match time
                return DateRange(start: now, end: now)
            }
        ))

        return list
    }()

    private static let monthNames: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4,
        "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12
    ]

    // MARK: - Public API

    public init() {}

    public func parse(_ rawQuery: String) -> SearchQuery {
        return Self.parse(rawQuery, now: Date())
    }

    /// Internal parse with injectable `now` for testing.
    public static func parse(_ rawQuery: String, now: Date = Date()) -> SearchQuery {
        let fullRange = NSRange(rawQuery.startIndex..., in: rawQuery)

        // Find the first (leftmost) matching pattern
        var bestMatch: (range: NSRange, dateRange: DateRange, patternIndex: Int)?

        for (index, pattern) in patterns.enumerated() {
            guard let match = pattern.regex.firstMatch(in: rawQuery, range: fullRange) else {
                continue
            }

            let dateRange: DateRange

            // Handle patterns that need captured group data
            switch index {
            case 6: // "last N days"
                let nRange = match.range(at: 1)
                guard let nSwiftRange = Range(nRange, in: rawQuery),
                      let n = Int(rawQuery[nSwiftRange]) else {
                    continue
                }
                let start = calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now))!
                dateRange = DateRange(start: start, end: now)

            case 7: // "recent(ly)"
                dateRange = pattern.dateRange(now)

            case 8: // "in <Month> <Year>"
                let monthRange = match.range(at: 1)
                let yearRange = match.range(at: 2)
                guard let monthSwiftRange = Range(monthRange, in: rawQuery),
                      let yearSwiftRange = Range(yearRange, in: rawQuery),
                      let month = monthNames[rawQuery[monthSwiftRange].lowercased()],
                      let year = Int(rawQuery[yearSwiftRange]) else {
                    continue
                }
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = 1
                guard let start = calendar.date(from: comps),
                      let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                    continue
                }
                dateRange = DateRange(start: start, end: end)

            case 9: // "in <Month>" (current year)
                let monthRange = match.range(at: 1)
                guard let monthSwiftRange = Range(monthRange, in: rawQuery),
                      let month = monthNames[rawQuery[monthSwiftRange].lowercased()] else {
                    continue
                }
                let currentYear = calendar.component(.year, from: now)
                var comps = DateComponents()
                comps.year = currentYear
                comps.month = month
                comps.day = 1
                guard let start = calendar.date(from: comps),
                      let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                    continue
                }
                dateRange = DateRange(start: start, end: end)

            case 10: // "in <Year>"
                let yearRange = match.range(at: 1)
                guard let yearSwiftRange = Range(yearRange, in: rawQuery),
                      let year = Int(rawQuery[yearSwiftRange]) else {
                    continue
                }
                var comps = DateComponents()
                comps.year = year
                comps.month = 1
                comps.day = 1
                guard let start = calendar.date(from: comps) else { continue }
                comps.year = year + 1
                guard let end = calendar.date(from: comps) else { continue }
                dateRange = DateRange(start: start, end: end)

            default:
                dateRange = pattern.dateRange(now)
            }

            // Use leftmost match
            if let existing = bestMatch {
                if match.range.location < existing.range.location {
                    bestMatch = (match.range, dateRange, index)
                }
            } else {
                bestMatch = (match.range, dateRange, index)
            }
        }

        guard let best = bestMatch else {
            return SearchQuery(text: rawQuery, dateRange: nil)
        }

        // Strip the matched temporal phrase from the query
        guard let swiftRange = Range(best.range, in: rawQuery) else {
            return SearchQuery(text: rawQuery, dateRange: nil)
        }

        var cleaned = rawQuery
        cleaned.removeSubrange(swiftRange)
        // Clean up extra whitespace
        cleaned = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return SearchQuery(text: cleaned, dateRange: best.dateRange)
    }
}
