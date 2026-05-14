import Foundation

@MainActor
enum NoteContentCache {
    private static var entries: [UUID: String] = [:]

    static func get(_ noteID: UUID) -> String? {
        entries[noteID]
    }

    static func set(_ noteID: UUID, content: String) {
        entries[noteID] = content
    }

    static func invalidate(_ noteID: UUID) {
        entries.removeValue(forKey: noteID)
    }
}
