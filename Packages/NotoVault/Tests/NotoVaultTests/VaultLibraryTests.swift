import Foundation
import Testing
@testable import NotoVault

@Suite("Vault library projections")
struct VaultLibraryTests {
    @Test func libraryUsesLocalPreviewsWhenCoordinatedReadsAreUnavailable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let markdown = "---\nid: \(id)\n---\n# A readable title\n\nA local preview."
        try markdown.write(to: root.appendingPathComponent("Fallback.md"), atomically: true, encoding: .utf8)
        let snapshot = try VaultLibrarySnapshot.load(vaultURL: root, fileSystem: PreviewOnlyFileSystem())
        let note = try #require(snapshot.notes.first)
        #expect(note.id == id)
        #expect(note.title == "A readable title")
        #expect(note.isAvailable)
        #expect(note.content == markdown)
    }

    @Test func unavailablePreviewsKeepNotesVisibleByFilename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Hidden body".write(to: root.appendingPathComponent("Kept.md"), atomically: true, encoding: .utf8)
        let snapshot = try VaultLibrarySnapshot.load(vaultURL: root, fileSystem: PreviewOnlyFileSystem(previewAvailable: false))
        #expect(snapshot.notes.count == 1)
        #expect(snapshot.notes.first?.title == "Kept")
        #expect(snapshot.notes.first?.isAvailable == false)
    }

    @Test func localPreviewsKeepTheByteLimitAndOriginalBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data((0..<128).map(UInt8.init))
        try bytes.write(to: url)
        #expect(CoordinatedVaultFileSystem().readLocalPreview(from: url, maxBytes: 17) == Data(bytes.prefix(17)))
    }

    @Test func snippetsShowVisibleMarkdownInsteadOfSourceSyntax() {
        let markdown = "# Title\n\n## Tests\n\n- [x] Read [[Desktop redesign|desktop plan]] and [notes](https://example.com)\n\n**Finish** review"
        #expect(VaultLibraryNote.plainTextSnippet(from: markdown) == "Title Tests Read desktop plan and notes Finish review")
    }

    @Test func dailyStripStartsOnMondayAcrossTimezonesAndDaylightSaving() throws {
        for (zone, input, expected) in [
            ("Asia/Hong_Kong", "2026-10-18T04:00:00Z", "2026-10-11T16:00:00Z"),
            ("America/Los_Angeles", "2026-11-01T20:00:00Z", "2026-10-26T07:00:00Z")
        ] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone)); calendar.firstWeekday = 1
            let date = try #require(NotePropertyClassifier.date(from: input))
            #expect(VaultLibraryNote.mondayWeekStart(containing: date, calendar: calendar) == NotePropertyClassifier.date(from: expected))
        }
    }
    @Test func previewsExcludeFrontmatterAndHeading() {
        let content = "---\nid: hidden\n---\n# My title\n\nA useful preview.\nAnother line."
        #expect(VaultLibraryNote.preview(of: "# Title\n\n#fitness feels good") == "#fitness feels good")
        #expect(VaultLibraryNote.preview(of: content) == "A useful preview. Another line.")
        #expect(VaultLibraryNote.preview(of: "# Title\n\n## Why\n\nA **calm** editor.\n\n## Goals\n\n- Simple") == "A calm editor. Simple")
    }

    @Test func outlineIgnoresFencedCode() {
        let headings = VaultLibraryNote.outline(of: "# Title\n## First\n```md\n## Code\n```\n### Last")
        #expect(headings.map(\.title) == ["Title", "First", "Last"])
        #expect(headings.map(\.level) == [1, 2, 3])
    }

    @Test func libraryKeepsIdentityAndFolderBoundaries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Projects/Noto")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let id = UUID()
        try "---\nid: \(id)\npinned: true\n---\n# Desktop\nA calm editor".write(to: nested.appendingPathComponent("Desktop.md"), atomically: true, encoding: .utf8)
        let snapshot = try VaultLibrarySnapshot.load(vaultURL: root)
        #expect(snapshot.notes.count == 1)
        #expect(snapshot.notes.first?.id == id)
        #expect(snapshot.notes.first?.isPinned == true)
        #expect(snapshot.notes(in: root.appendingPathComponent("Projects")).isEmpty)
        #expect(snapshot.notes(in: nested).count == 1)
        #expect(snapshot.matching("calm").count == 1)
        #expect(snapshot.matching("missing").isEmpty)
        let note = try #require(snapshot.notes.first)
        #expect(note.snippet(matching: "calm").contains("calm"))
        #expect(!note.snippet(matching: "calm").contains("Desktop"))
        #expect(!note.snippet(matching: "calm").contains("pinned:"))
        try "# Plan\n\nSee [[Projects/Noto/Desktop|the app]]".write(to: root.appendingPathComponent("Plan.md"), atomically: true, encoding: .utf8)
        let linked = try VaultLibrarySnapshot.load(vaultURL: root)
        #expect(linked.backlinks(to: note).map(\.title) == ["Plan"])
    }

    @Test func dailyIdentityUsesTheLocalDayInsteadOfModificationTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let daily = root.appendingPathComponent("Daily Notes")
        try FileManager.default.createDirectory(at: daily, withIntermediateDirectories: true)
        try "# Daily".write(to: daily.appendingPathComponent("2026-10-18.md"), atomically: true, encoding: .utf8)
        let note = try #require(VaultLibrarySnapshot.load(vaultURL: root).notes.first)
        var hongKong = Calendar(identifier: .gregorian); hongKong.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = try #require(NotePropertyClassifier.date(from: "2026-10-17T19:00:00Z"))
        #expect(note.isDaily(on: instant, calendar: hongKong))
        #expect(!note.isDaily(on: instant, calendar: utc))
    }

    @Test func dateSectionsUseCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_792_281_600)
        #expect(VaultLibraryNote.dateSection(for: now, now: now, calendar: calendar) == "Today")
        #expect(VaultLibraryNote.dateSection(for: now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Yesterday")
        #expect(VaultLibraryNote.dateSection(for: now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar) == "Previous 7 Days")
    }
}

/// Models a file provider whose coordinated reads cannot answer promptly, while
/// the already-downloaded local bytes remain readable for a transient list preview.
private struct PreviewOnlyFileSystem: VaultFileSystem {
    private let base = CoordinatedVaultFileSystem()
    let previewAvailable: Bool
    init(previewAvailable: Bool = true) { self.previewAvailable = previewAvailable }
    func readLocalPreview(from url: URL, maxBytes: Int) -> Data? {
        guard previewAvailable else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }
    func readPrefix(from url: URL, maxBytes: Int) -> Data? { nil }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isReadableFile(at url: URL) -> Bool { base.isReadableFile(at: url) }
    func readString(from url: URL) -> String? { nil }
    func readData(from url: URL) -> Data? { nil }
    func writeString(_ content: String, to url: URL) -> Bool { false }
    func writeData(_ data: Data, to url: URL) -> Bool { false }
    func delete(at url: URL) -> Bool { false }
    func move(from sourceURL: URL, to destinationURL: URL) -> Bool { false }
    func createDirectory(at url: URL) -> Bool { false }
    func isDownloaded(at url: URL) -> Bool { true }
    func startDownloading(at url: URL) {}
}
