import Foundation

public struct ReadwiseSyncState: Codable, Sendable {
    public var version: Int
    public var lastSuccessfulSyncAt: String?
    public var lastSuccessfulReaderSyncAt: String?
    public var sources: [String: SourceMapping]

    public init(
        version: Int = 1,
        lastSuccessfulSyncAt: String? = nil,
        lastSuccessfulReaderSyncAt: String? = nil,
        sources: [String: SourceMapping] = [:]
    ) {
        self.version = version
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastSuccessfulReaderSyncAt = lastSuccessfulReaderSyncAt
        self.sources = sources
    }
}

public struct SourceMapping: Codable, Sendable {
    public var noteID: String
    public var relativePath: String
    public var generatedBlockHash: String
    public var readwiseUserBookID: Int?
    public var readerDocumentID: String?
    public var updatedAt: String

    public init(
        noteID: String,
        relativePath: String,
        generatedBlockHash: String,
        readwiseUserBookID: Int? = nil,
        readerDocumentID: String? = nil,
        updatedAt: String
    ) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.generatedBlockHash = generatedBlockHash
        self.readwiseUserBookID = readwiseUserBookID
        self.readerDocumentID = readerDocumentID
        self.updatedAt = updatedAt
    }
}

public enum SyncStateStore {
    public static func stateURL(in vaultURL: URL) -> URL {
        vaultURL
            .appendingPathComponent(".noto", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
            .appendingPathComponent("readwise.json")
    }

    public static func load(from vaultURL: URL) throws -> ReadwiseSyncState {
        let url = stateURL(in: vaultURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ReadwiseSyncState()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReadwiseSyncState.self, from: data)
    }

    public static func save(_ state: ReadwiseSyncState, to vaultURL: URL) throws {
        let url = stateURL(in: vaultURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }
}
