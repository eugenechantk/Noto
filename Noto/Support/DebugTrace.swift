import Foundation

enum DebugTrace {
    private static let eventsKey = "DebugTraceEvents"
    private static let enabledKey = "EnableDebugTrace"
    private static let maxEvents = 200
    private static let formatter = ISO8601DateFormatter()

    private static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTO_DEBUG_TRACE"] == "1"
            || UserDefaults.standard.bool(forKey: enabledKey)
        #else
        false
        #endif
    }

    static func reset() {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: eventsKey)
        #endif
    }

    static func record(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        var events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        let timestamp = formatter.string(from: Date())
        events.append("[\(timestamp)] \(message())")
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        UserDefaults.standard.set(events, forKey: eventsKey)
        #endif
    }

    static func textSummary(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
        let suffix = String(normalized.suffix(80))
        return "len=\(text.count) tail=\(suffix)"
    }
}
