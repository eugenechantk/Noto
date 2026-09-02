import Foundation

public struct NoteTagRecord: Sendable, Equatable {
    public let noteID: String
    public let tags: [TagName]

    public init(noteID: String, tags: [TagName]) {
        self.noteID = noteID
        self.tags = tags
    }
}

public struct TagMembershipIndex: Sendable {
    private let noteIDsByTag: [TagName: [String]]

    public init(records: [NoteTagRecord]) {
        var noteIDsByTag: [TagName: [String]] = [:]
        var seen: [TagName: Set<String>] = [:]

        for record in records {
            guard !record.noteID.isEmpty else {
                continue
            }

            let uniqueTags = Set(record.tags)
            for tag in uniqueTags {
                if seen[tag, default: []].insert(record.noteID).inserted {
                    noteIDsByTag[tag, default: []].append(record.noteID)
                }
            }
        }

        self.noteIDsByTag = noteIDsByTag
    }

    public func notes(withTag tag: TagName) -> [String] {
        noteIDsByTag[tag] ?? []
    }

    public func allTags() -> [TagName] {
        Array(noteIDsByTag.keys).sorted()
    }

    public func count(for tag: TagName) -> Int {
        noteIDsByTag[tag]?.count ?? 0
    }
}
