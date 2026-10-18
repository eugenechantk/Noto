import Foundation

/// Small presentation totals, persisted separately from note content by the app.
public struct VaultDailyActivity: Codable, Equatable, Sendable {
    public enum Kind { case filed, processed }
    private var day: Date?
    private var filed = 0
    private var processed = 0
    public init() {}

    public func count(_ kind: Kind, on date: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let day, calendar.isDate(day, inSameDayAs: date) else { return 0 }
        return kind == .filed ? filed : processed
    }

    public mutating func record(_ kind: Kind, delta: Int = 1, at date: Date = Date(), calendar: Calendar = .current) {
        if let day, !calendar.isDate(day, inSameDayAs: date) {
            guard delta > 0 else { return }
            filed = 0; processed = 0
        }
        day = calendar.startOfDay(for: date)
        switch kind {
        case .filed: filed = max(0, filed + delta)
        case .processed: processed = max(0, processed + delta)
        }
    }
}
