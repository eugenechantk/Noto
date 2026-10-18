import Foundation

public enum DigestSectionKind: String, CaseIterable, Sendable {
    case snoozed = "Snoozed", today = "Today", yesterday = "Yesterday", earlier = "Earlier"
}

public struct DigestSection: Identifiable, Equatable, Sendable {
    public let kind: DigestSectionKind
    public let entries: [DigestEntry]
    public var id: String { kind.rawValue }
}

/// The stack and list share one ordering: returning snoozes, future snoozes,
/// then ordinary captures newest first. Stack callers filter future snoozes.
public enum DigestPresentation {
    public static func ordered(_ entries: [DigestEntry], now: Date) -> [DigestEntry] {
        entries.sorted { lhs, rhs in
            if (lhs.snoozedUntil != nil) != (rhs.snoozedUntil != nil) { return lhs.snoozedUntil != nil }
            if lhs.snoozedUntil != nil, lhs.isDue(at: now) != rhs.isDue(at: now) { return lhs.isDue(at: now) }
            if lhs.snoozedUntil != nil, let a = lhs.snoozedUntil, let b = rhs.snoozedUntil, a != b { return a < b }
            if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt > rhs.capturedAt }
            return lhs.relativePath < rhs.relativePath
        }
    }

    public static func sections(_ entries: [DigestEntry], now: Date, calendar: Calendar = .current) -> [DigestSection] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let ordered = ordered(entries, now: now)
        return DigestSectionKind.allCases.compactMap { kind in
            let members = ordered.filter { entry in
                let group: DigestSectionKind
                if entry.snoozedUntil != nil { group = .snoozed }
                else if calendar.isDate(entry.capturedAt, inSameDayAs: now) { group = .today }
                else if calendar.isDate(entry.capturedAt, inSameDayAs: yesterday) { group = .yesterday }
                else { group = .earlier }
                return group == kind
            }
            return members.isEmpty ? nil : DigestSection(kind: kind, entries: members)
        }
    }
}
