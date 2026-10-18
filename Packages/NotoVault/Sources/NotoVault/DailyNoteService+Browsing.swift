import Foundation

public enum DailyNoteBrowsingError: LocalizedError {
    case cannotCreateFolder
    case cannotCreateNote

    public var errorDescription: String? {
        switch self {
        case .cannotCreateFolder: "The Daily Notes folder could not be created."
        case .cannotCreateNote: "This day's note could not be saved. Please try again."
        }
    }
}

/// Calendar semantics shared by the day navigator and the filesystem service.
public enum DailyNoteDay {
    public static func fileStem(for date: Date, calendar: Calendar = .current) -> String {
        formatted(date, format: "yyyy-MM-dd", calendar: calendar)
    }

    public static func title(for date: Date, calendar: Calendar = .current) -> String {
        formatted(date, format: "dd MMM, yy (EEE)", calendar: calendar)
    }

    public static func caption(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let weekday = formatted(date, format: "EEEE", calendar: calendar)
        if calendar.isDate(date, inSameDayAs: offset(now, by: -1, calendar: calendar)) {
            return "Yesterday · \(weekday)"
        }
        return weekday
    }

    public static func offset(_ date: Date, by days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
            ?? calendar.startOfDay(for: date)
    }

    private static func formatted(_ date: Date, format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

public extension DailyNoteService {
    /// Noto 2's read-only browsing path. Existing notes are never normalized or
    /// given a template retroactively. Noto v1 continues to use `ensure`.
    func open(date: Date, createIfMissing: Bool, calendar: Calendar = .current) throws -> DailyNoteResolution? {
        let folder = vaultRootURL.appendingPathComponent("Daily Notes", isDirectory: true)
        let url = folder.appendingPathComponent(DailyNoteDay.fileStem(for: date, calendar: calendar) + ".md")
        let title = DailyNoteDay.title(for: date, calendar: calendar)
        var created = false
        if !fileSystem.fileExists(at: url) {
            guard createIfMissing else { return nil }
            if !fileSystem.fileExists(at: folder), !fileSystem.createDirectory(at: folder) {
                throw DailyNoteBrowsingError.cannotCreateFolder
            }
            let markdown = VaultMarkdown.makeFrontmatter(id: UUID(), createdAt: date) + "# \(title)\n\(template.body)"
            guard fileSystem.writeString(markdown, to: url) else { throw DailyNoteBrowsingError.cannotCreateNote }
            created = true
        }
        let content = fileSystem.readString(from: url)
        return DailyNoteResolution(
            dailyFolderURL: folder,
            fileURL: url,
            displayTitle: title,
            id: content.flatMap(VaultMarkdown.idFromFrontmatter) ?? VaultDirectoryLoader.stableID(for: url),
            modifiedDate: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? date,
            didCreate: created,
            didApplyTemplate: false
        )
    }

    func hasWriting(in content: String, date: Date, calendar: Calendar = .current) -> Bool {
        let templateLines = Set(template.body.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let title = "# " + DailyNoteDay.title(for: date, calendar: calendar)
        return VaultMarkdown.stripFrontmatter(content).components(separatedBy: .newlines).contains { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && value != title && !templateLines.contains(value)
        }
    }

    /// A bounded month scan: it neither creates missing dates nor downloads the
    /// entire vault. Unreadable notes do not get an inferred writing dot.
    func writtenDays(inMonthContaining date: Date, calendar: Calendar = .current) -> Set<Date> {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let folder = vaultRootURL.appendingPathComponent("Daily Notes", isDirectory: true)
        guard fileSystem.fileExists(at: folder) else { return [] }
        var written = Set<Date>()
        for index in days {
            let day = DailyNoteDay.offset(month.start, by: index - 1, calendar: calendar)
            let url = folder.appendingPathComponent(DailyNoteDay.fileStem(for: day, calendar: calendar) + ".md")
            guard fileSystem.fileExists(at: url), let content = fileSystem.readString(from: url),
                  hasWriting(in: content, date: day, calendar: calendar) else { continue }
            written.insert(day)
        }
        return written
    }
}
