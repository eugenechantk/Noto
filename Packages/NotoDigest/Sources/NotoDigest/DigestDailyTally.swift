import Foundation

/// A compact local activity ledger. Undo removes its event, including when the
/// midnight boundary was crossed while a toast remained visible.
public struct DigestDailyTally: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case filed, discarded, snoozed }
    public struct Counts: Equatable, Sendable {
        public let filed: Int
        public let discarded: Int
        public let snoozed: Int
        public var total: Int { filed + discarded + snoozed }
        public init(filed: Int, discarded: Int, snoozed: Int) {
            self.filed = filed; self.discarded = discarded; self.snoozed = snoozed
        }
    }
    private struct Event: Codable, Sendable { let id: UUID; let action: Action; let date: Date }
    private var events: [Event] = []
    public init() {}

    @discardableResult public mutating func record(_ action: Action, at date: Date) -> UUID {
        events.removeAll { $0.date < date.addingTimeInterval(-7 * 86_400) }
        let id = UUID()
        events.append(Event(id: id, action: action, date: date))
        return id
    }
    public mutating func undo(_ id: UUID) { events.removeAll { $0.id == id } }
    public func counts(at date: Date, calendar: Calendar = .current) -> Counts {
        let today = events.filter { calendar.isDate($0.date, inSameDayAs: date) }
        return Counts(filed: today.filter { $0.action == .filed }.count,
                      discarded: today.filter { $0.action == .discarded }.count,
                      snoozed: today.filter { $0.action == .snoozed }.count)
    }
}
