import Foundation

public struct SourceLibrarySyncResult: Sendable {
    public let reader: SourceNoteSyncResult
    public let readwise: SourceNoteSyncResult
    public let fetchedReaderDocuments: Int
    public let fetchedReadwiseBooks: Int
    public let fetchedJoinedReadwiseBooks: Int
    public let readerUpdatedAfter: String?
    public let readwiseUpdatedAfter: String?

    public init(
        reader: SourceNoteSyncResult,
        readwise: SourceNoteSyncResult,
        fetchedReaderDocuments: Int,
        fetchedReadwiseBooks: Int,
        fetchedJoinedReadwiseBooks: Int,
        readerUpdatedAfter: String?,
        readwiseUpdatedAfter: String?
    ) {
        self.reader = reader
        self.readwise = readwise
        self.fetchedReaderDocuments = fetchedReaderDocuments
        self.fetchedReadwiseBooks = fetchedReadwiseBooks
        self.fetchedJoinedReadwiseBooks = fetchedJoinedReadwiseBooks
        self.readerUpdatedAfter = readerUpdatedAfter
        self.readwiseUpdatedAfter = readwiseUpdatedAfter
    }

    /// Union of every URL written across the reader and readwise legs of the
    /// sync. Empty in dry-run mode. The app fans these out to per-file index
    /// refreshes so freshly written iCloud files don't depend on the vault
    /// enumerator (which can miss them inside the macOS sandbox).
    public var writtenURLs: Set<URL> {
        reader.writtenURLs.union(readwise.writtenURLs)
    }
}

public struct SourceLibrarySyncEngine: Sendable {
    private let client: any ReadwiseSyncClient
    private let noteSyncEngine: SourceNoteSyncEngine

    public init(
        client: any ReadwiseSyncClient,
        noteSyncEngine: SourceNoteSyncEngine = SourceNoteSyncEngine()
    ) {
        self.client = client
        self.noteSyncEngine = noteSyncEngine
    }

    public func syncIncrementally(
        vaultURL: URL,
        sourceDirectory: String = SourceNoteSyncEngine.defaultSourceDirectory,
        includeDeleted: Bool = true,
        dryRun: Bool = false,
        limit: Int? = nil,
        syncedAt: Date = Date()
    ) async throws -> SourceLibrarySyncResult {
        let state = try SyncStateStore.load(from: vaultURL)
        let readerUpdatedAfter = state.lastSuccessfulReaderSyncAt
        let readwiseUpdatedAfter = state.lastSuccessfulSyncAt

        let readerDocuments = try await client.fetchReaderDocuments(
            id: nil,
            updatedAfter: readerUpdatedAfter,
            location: nil,
            category: nil,
            tags: [],
            limit: limit
        )
        let incrementalReadwiseBooks = try await client.fetchExport(
            updatedAfter: readwiseUpdatedAfter,
            includeDeleted: includeDeleted,
            ids: nil,
            limit: limit
        )

        let readerDocumentIDs = Set(readerDocuments.map(\.id))
        var matchedBooks = incrementalReadwiseBooks.reduce(into: [String: ReadwiseBook]()) { partialResult, book in
            guard book.source == "reader",
                  let externalID = book.externalID,
                  readerDocumentIDs.contains(externalID),
                  partialResult[externalID] == nil else {
                return
            }
            partialResult[externalID] = book
        }

        let missingKnownBookIDs = readerDocuments.compactMap { document -> Int? in
            guard matchedBooks[document.id] == nil else { return nil }
            return state.sources[document.canonicalKey]?.readwiseUserBookID
        }

        let knownBookIDs = Array(Set(missingKnownBookIDs)).sorted()
        if !knownBookIDs.isEmpty {
            let joinedBooks = try await client.fetchExport(
                updatedAfter: nil,
                includeDeleted: includeDeleted,
                ids: knownBookIDs,
                limit: nil
            )
            for book in joinedBooks {
                guard book.source == "reader",
                      let externalID = book.externalID,
                      readerDocumentIDs.contains(externalID),
                      matchedBooks[externalID] == nil else {
                    continue
                }
                matchedBooks[externalID] = book
            }
        }

        let readerResult = try noteSyncEngine.syncReaderDocuments(
            readerDocuments,
            matchedReadwiseBooks: matchedBooks,
            vaultURL: vaultURL,
            sourceDirectory: sourceDirectory,
            dryRun: dryRun,
            syncedAt: syncedAt
        )
        let readwiseResult = try noteSyncEngine.sync(
            books: incrementalReadwiseBooks,
            vaultURL: vaultURL,
            sourceDirectory: sourceDirectory,
            dryRun: dryRun,
            syncedAt: syncedAt
        )

        return SourceLibrarySyncResult(
            reader: readerResult,
            readwise: readwiseResult,
            fetchedReaderDocuments: readerDocuments.count,
            fetchedReadwiseBooks: incrementalReadwiseBooks.count,
            fetchedJoinedReadwiseBooks: matchedBooks.count,
            readerUpdatedAfter: readerUpdatedAfter,
            readwiseUpdatedAfter: readwiseUpdatedAfter
        )
    }
}
