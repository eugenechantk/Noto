import Foundation

public struct DailyNoteTemplate: Sendable, Equatable {
    public let body: String
    public let marker: String

    public init(body: String, marker: String) {
        self.body = body
        self.marker = marker
    }

    public static let notoDefault = DailyNoteTemplate(
        body: """
        ## What did I do today?

        ## What's on my mind today?

        ## How do I feel today? Why am I feeling this way?

        ## What will I do with this information?

        """,
        marker: "## What did I do today?"
    )

    public func isApplied(in content: String) -> Bool {
        content.contains(marker)
    }

    public func applyRetroactively(to content: String) -> String? {
        guard !isApplied(in: content) else { return nil }

        let bodyWithoutFrontmatter = VaultMarkdown.stripFrontmatter(content)
        guard let firstNewline = bodyWithoutFrontmatter.firstIndex(of: "\n") else {
            return content + "\n" + body
        }

        let titleEnd = content.distance(from: content.startIndex, to: content.endIndex)
            - content.distance(from: bodyWithoutFrontmatter.startIndex, to: bodyWithoutFrontmatter.endIndex)
            + content.distance(from: bodyWithoutFrontmatter.startIndex, to: firstNewline)

        let insertIndex = content.index(content.startIndex, offsetBy: titleEnd)
        var result = content
        result.insert(contentsOf: body, at: content.index(after: insertIndex))
        return result
    }
}

public struct DailyNoteResolution: Sendable, Equatable {
    public let dailyFolderURL: URL
    public let fileURL: URL
    public let displayTitle: String
    public let id: UUID
    public let modifiedDate: Date
    public let didCreate: Bool
    public let didApplyTemplate: Bool

    public init(
        dailyFolderURL: URL,
        fileURL: URL,
        displayTitle: String,
        id: UUID,
        modifiedDate: Date,
        didCreate: Bool,
        didApplyTemplate: Bool
    ) {
        self.dailyFolderURL = dailyFolderURL
        self.fileURL = fileURL
        self.displayTitle = displayTitle
        self.id = id
        self.modifiedDate = modifiedDate
        self.didCreate = didCreate
        self.didApplyTemplate = didApplyTemplate
    }
}

public struct DailyNoteService: Sendable {
    public let vaultRootURL: URL
    public let fileSystem: any VaultFileSystem
    public let template: DailyNoteTemplate

    public init(
        vaultRootURL: URL,
        fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem(),
        template: DailyNoteTemplate = .notoDefault
    ) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
        self.fileSystem = fileSystem
        self.template = template
    }

    public func ensure(date: Date = Date(), calendar: Calendar = .current) -> DailyNoteResolution {
        let dailyFolderURL = vaultRootURL.appendingPathComponent("Daily Notes")
        if !fileSystem.fileExists(at: dailyFolderURL) {
            _ = fileSystem.createDirectory(at: dailyFolderURL)
        }

        let isoDate = Self.dateFormatter(format: "yyyy-MM-dd", calendar: calendar).string(from: date)
        let displayTitle = Self.dateFormatter(format: "dd MMM, yy (EEE)", calendar: calendar).string(from: date)
        let fileURL = dailyFolderURL.appendingPathComponent("\(isoDate).md")

        var didCreate = false
        if !fileSystem.fileExists(at: fileURL) {
            let id = UUID()
            let content = VaultMarkdown.makeFrontmatter(id: id, createdAt: date) + "# \(displayTitle)\n\(template.body)"
            didCreate = fileSystem.writeString(content, to: fileURL)
        }

        let existingContent = fileSystem.readString(from: fileURL) ?? ""
        var didApplyTemplate = false
        if let updated = template.applyRetroactively(to: existingContent) {
            didApplyTemplate = fileSystem.writeString(updated, to: fileURL)
        }

        let id = VaultMarkdown.idFromFrontmatter(existingContent) ?? VaultDirectoryLoader.stableID(for: fileURL)
        let modifiedDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? date

        return DailyNoteResolution(
            dailyFolderURL: dailyFolderURL,
            fileURL: fileURL,
            displayTitle: displayTitle,
            id: id,
            modifiedDate: modifiedDate,
            didCreate: didCreate,
            didApplyTemplate: didApplyTemplate
        )
    }

    public static func nextStartOfDay(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
    }

    private static func dateFormatter(format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
