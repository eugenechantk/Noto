import Foundation

struct NoteSyncSnapshot: Sendable, Equatable {
    let noteID: UUID
    let fileURL: URL
    let text: String
    let sourceEditorID: UUID
    let savedAt: Date
}

@MainActor
enum NoteSyncCenter {
    static let notificationName = Notification.Name("NoteSyncCenter.noteDidPersist")

    static func publish(_ snapshot: NoteSyncSnapshot) {
        NotificationCenter.default.post(name: notificationName, object: snapshot)
    }
}
