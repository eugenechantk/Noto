import Foundation
import NotoReadwiseSyncCore

@main
struct NotoReadwiseSyncCLI {
    static func main() async {
        do {
            let options = try CLIOptions.parse(CommandLine.arguments)
            if options.help {
                print(CLIOptions.helpText)
                return
            }

            if options.readerMode {
                let fetchedDocuments: [ReaderDocument]
                if let fixtureURL = options.fixtureURL {
                    let data = try Data(contentsOf: fixtureURL)
                    fetchedDocuments = try JSONDecoder.readwise.decode(ReaderListPage.self, from: data).results
                } else {
                    guard let token = options.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                        throw CLIError.missingToken
                    }
                    let client = ReadwiseClient(token: token)
                    fetchedDocuments = try await client.fetchReaderDocuments(
                        id: options.readerID,
                        updatedAfter: options.updatedAfter,
                        location: options.readerLocation,
                        category: options.readerCategory,
                        tags: options.readerTags,
                        limit: options.limit
                    )
                }
                let documents: [ReaderDocument]
                if options.fixtureURL == nil {
                    documents = fetchedDocuments
                } else {
                    let fixtureFilteredDocuments = fetchedDocuments.filter { $0.matchesAllTags(options.readerTags) }
                    documents = options.limit.map { Array(fixtureFilteredDocuments.prefix($0)) } ?? fixtureFilteredDocuments
                }
                var matchedBooks: [String: ReadwiseBook] = [:]
                if options.readerJoinHighlights, options.fixtureURL == nil {
                    guard let token = options.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                        throw CLIError.missingToken
                    }
                    let client = ReadwiseClient(token: token)
                    let books = try await client.fetchExport(includeDeleted: options.includeDeleted)
                    let documentIDs = Set(documents.map(\.id))
                    for book in books {
                        guard book.source == "reader",
                              let externalID = book.externalID,
                              documentIDs.contains(externalID),
                              matchedBooks[externalID] == nil else {
                            continue
                        }
                        matchedBooks[externalID] = book
                    }
                }
                let result = try SourceNoteSyncEngine().syncReaderDocuments(
                    documents,
                    matchedReadwiseBooks: matchedBooks,
                    vaultURL: options.vaultURL,
                    sourceDirectory: options.sourceDirectory,
                    dryRun: options.dryRun
                )
                print("""
                Reader sync complete\(result.dryRun ? " (dry run)" : "").
                Documents fetched: \(fetchedDocuments.count)
                Documents selected: \(documents.count)
                Matched Readwise highlight sources: \(matchedBooks.count)
                Created: \(result.created)
                Updated: \(result.updated)
                Skipped child documents: \(result.skippedChildDocuments)
                Source directory: \(result.sourceDirectoryURL.path)
                """)
            } else {
                let fetchedBooks: [ReadwiseBook]
                if let fixtureURL = options.fixtureURL {
                    let data = try Data(contentsOf: fixtureURL)
                    fetchedBooks = try JSONDecoder.readwise.decode(ReadwiseExportPage.self, from: data).results
                } else {
                    guard let token = options.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                        throw CLIError.missingToken
                    }
                    fetchedBooks = try await ReadwiseClient(token: token).fetchExport(
                        updatedAfter: options.updatedAfter,
                        includeDeleted: options.includeDeleted,
                        limit: options.limit
                    )
                }
                let books = options.limit.map { Array(fetchedBooks.prefix($0)) } ?? fetchedBooks
                let result = try SourceNoteSyncEngine().sync(
                    books: books,
                    vaultURL: options.vaultURL,
                    sourceDirectory: options.sourceDirectory,
                    dryRun: options.dryRun
                )

                print("""
                Readwise sync complete\(result.dryRun ? " (dry run)" : "").
                Sources fetched: \(fetchedBooks.count)
                Sources selected: \(books.count)
                Created: \(result.created)
                Updated: \(result.updated)
                Skipped deleted sources: \(result.skippedDeleted)
                Source directory: \(result.sourceDirectoryURL.path)
                """)
            }
        } catch {
            fputs("Error: \(error)\n\n\(CLIOptions.helpText)\n", stderr)
            exit(1)
        }
    }
}

private struct CLIOptions {
    var vaultURL: URL
    var sourceDirectory: String = SourceNoteSyncEngine.defaultSourceDirectory
    var token: String?
    var fixtureURL: URL?
    var updatedAfter: String?
    var limit: Int?
    var readerMode: Bool = false
    var readerID: String?
    var readerCategory: String?
    var readerLocation: String?
    var readerTags: [String] = []
    var readerJoinHighlights: Bool = true
    var includeDeleted: Bool = true
    var dryRun: Bool = false
    var help: Bool = false

    static let helpText = """
    Usage:
      noto-readwise-sync --vault <vault-path> [options]

    Options:
      --token <token>             Readwise access token. Defaults to READWISE_TOKEN.
      --vault <path>              Noto vault path.
      --source-dir <path>         Source note directory, relative to vault unless absolute. Default: Captures.
      --updated-after <iso-date>  Fetch Readwise sources updated after this ISO 8601 date.
      --limit <count>             Sync only the first N fetched sources. Useful for test backfills.
      --reader                    Import saved Reader documents with full html_content instead of Readwise highlights.
      --reader-id <id>            Reader document id to import. Implies --reader.
      --reader-category <type>    Reader category filter: article, tweet, video, pdf, epub, rss, email.
      --reader-location <value>   Reader location filter: new, later, shortlist, archive, feed.
      --reader-tag <tag>          Reader tag filter. Repeat up to 5 times; Reader requires all tags.
      --no-reader-highlights      Do not join Reader documents with Readwise export highlights.
      --include-deleted           Include deleted highlights from Readwise export, then omit them from generated notes. Default.
      --no-include-deleted        Do not ask Readwise for deleted highlights.
      --fixture <path>            Use a local Readwise export JSON fixture instead of the network.
      --dry-run                   Fetch and plan without writing files.
      --help                      Show this help text.

    Environment:
      READWISE_TOKEN              Used when --token is omitted.
    """

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var options = CLIOptions(
            vaultURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            token: ProcessInfo.processInfo.environment["READWISE_TOKEN"]
        )

        var iterator = Array(arguments.dropFirst()).makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--help", "-h":
                options.help = true
            case "--vault":
                options.vaultURL = try requiredURL(iterator.next(), option: arg, isDirectory: true)
            case "--source-dir":
                options.sourceDirectory = try requiredValue(iterator.next(), option: arg)
            case "--token":
                options.token = try requiredValue(iterator.next(), option: arg)
            case "--fixture":
                options.fixtureURL = try requiredURL(iterator.next(), option: arg, isDirectory: false)
            case "--updated-after":
                options.updatedAfter = try requiredValue(iterator.next(), option: arg)
            case "--limit":
                options.limit = try requiredPositiveInt(iterator.next(), option: arg)
            case "--reader":
                options.readerMode = true
            case "--reader-id":
                options.readerMode = true
                options.readerID = try requiredValue(iterator.next(), option: arg)
            case "--reader-category":
                options.readerMode = true
                options.readerCategory = try requiredValue(iterator.next(), option: arg)
            case "--reader-location":
                options.readerMode = true
                options.readerLocation = try requiredValue(iterator.next(), option: arg)
            case "--reader-tag":
                options.readerMode = true
                options.readerTags.append(try requiredReaderTag(iterator.next(), option: arg, existingCount: options.readerTags.count))
            case "--no-reader-highlights":
                options.readerJoinHighlights = false
            case "--include-deleted":
                options.includeDeleted = true
            case "--no-include-deleted":
                options.includeDeleted = false
            case "--dry-run":
                options.dryRun = true
            default:
                throw CLIError.unknownOption(arg)
            }
        }

        return options
    }

    private static func requiredValue(_ value: String?, option: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw CLIError.missingValue(option)
        }
        return value
    }

    private static func requiredURL(_ value: String?, option: String, isDirectory: Bool) throws -> URL {
        URL(fileURLWithPath: try requiredValue(value, option: option), isDirectory: isDirectory)
            .standardizedFileURL
    }

    private static func requiredPositiveInt(_ value: String?, option: String) throws -> Int {
        let rawValue = try requiredValue(value, option: option)
        guard let number = Int(rawValue), number > 0 else {
            throw CLIError.invalidPositiveInt(option, rawValue)
        }
        return number
    }

    private static func requiredReaderTag(_ value: String?, option: String, existingCount: Int) throws -> String {
        let tag = try requiredValue(value, option: option)
        guard existingCount < 5 else {
            throw CLIError.tooManyReaderTags
        }
        return tag
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case missingToken
    case missingValue(String)
    case invalidPositiveInt(String, String)
    case tooManyReaderTags
    case unknownOption(String)

    var description: String {
        switch self {
        case .missingToken:
            "Missing Readwise token. Pass --token or set READWISE_TOKEN."
        case .missingValue(let option):
            "Missing value for \(option)."
        case .invalidPositiveInt(let option, let value):
            "\(option) requires a positive integer, got '\(value)'."
        case .tooManyReaderTags:
            "Reader API supports at most 5 --reader-tag filters."
        case .unknownOption(let option):
            "Unknown option: \(option)."
        }
    }
}
