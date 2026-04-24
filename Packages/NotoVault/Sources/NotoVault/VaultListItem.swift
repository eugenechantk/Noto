import Foundation

public struct NoteSummary: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let title: String
    public let modifiedDate: Date

    public init(id: UUID, fileURL: URL, title: String, modifiedDate: Date) {
        self.id = id
        self.fileURL = fileURL.standardizedFileURL
        self.title = title
        self.modifiedDate = modifiedDate
    }
}

public struct FolderSummary: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let folderURL: URL
    public let name: String
    public let modifiedDate: Date
    public let folderCount: Int
    public let itemCount: Int

    public init(
        id: UUID,
        folderURL: URL,
        name: String,
        modifiedDate: Date,
        folderCount: Int = 0,
        itemCount: Int = 0
    ) {
        self.id = id
        self.folderURL = folderURL.standardizedFileURL
        self.name = name
        self.modifiedDate = modifiedDate
        self.folderCount = folderCount
        self.itemCount = itemCount
    }
}

public enum VaultListItem: Identifiable, Equatable, Hashable, Sendable {
    case folder(FolderSummary)
    case note(NoteSummary)

    public var id: UUID {
        switch self {
        case .folder(let folder):
            folder.id
        case .note(let note):
            note.id
        }
    }

    public var modifiedDate: Date {
        switch self {
        case .folder(let folder):
            folder.modifiedDate
        case .note(let note):
            note.modifiedDate
        }
    }
}
