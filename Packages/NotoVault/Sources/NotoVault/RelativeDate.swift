import Foundation

public enum NotoRelativeDate {
    /// Abbreviated "Edited …" label for list rows, matching the v2 design
    /// ("Edited just now", "Edited 5m ago", "Edited 2h ago", "Edited 3d ago",
    /// "Edited 2w ago", "Edited 4mo ago", "Edited 1y ago").
    public static func editedString(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds) / 60
        if minutes < 1 { return "Edited just now" }
        if minutes < 60 { return "Edited \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "Edited \(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "Edited \(days)d ago" }
        let weeks = days / 7
        if weeks < 5 { return "Edited \(weeks)w ago" }
        let months = days / 30
        if months < 12 { return "Edited \(months)mo ago" }
        return "Edited \(days / 365)y ago"
    }

    /// Compact relative label without the "Edited " prefix, for the search
    /// surface metadata line ("just now", "5m ago", "2h ago", "3d ago", …).
    public static func compactString(from date: Date, now: Date = Date()) -> String {
        let edited = editedString(from: date, now: now)
        return edited.hasPrefix("Edited ") ? String(edited.dropFirst("Edited ".count)) : edited
    }
}
