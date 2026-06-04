import Testing
import Foundation
@testable import NotoVault

@Suite("NotePropertyClassifier")
struct NotePropertyTests {
    @Test("tags by key or list shape")
    func tags() {
        #expect(NotePropertyClassifier.kind(key: "tags", value: "a, b") == .tags)
        #expect(NotePropertyClassifier.kind(key: "keywords", value: "x") == .tags)
        #expect(NotePropertyClassifier.kind(key: "labels", value: "[one, two]") == .tags)
        #expect(NotePropertyClassifier.kind(key: "labels", value: "- one\n- two") == .tags)
    }

    @Test("url by value shape")
    func url() {
        #expect(NotePropertyClassifier.kind(key: "source", value: "https://example.com/p/1") == .url)
        #expect(NotePropertyClassifier.kind(key: "source_url", value: "\"http://x.com\"") == .url)
        #expect(NotePropertyClassifier.isURL("https://a.b/c"))
        #expect(!NotePropertyClassifier.isURL("not a url"))
        #expect(!NotePropertyClassifier.isURL("ftp://x"))
    }

    @Test("date by key or value")
    func date() {
        #expect(NotePropertyClassifier.kind(key: "published", value: "2026-03-02") == .date)
        #expect(NotePropertyClassifier.kind(key: "due_date", value: "x") == .date)
        #expect(NotePropertyClassifier.kind(key: "when", value: "2026-03-02T10:00:00Z") == .date)
        #expect(NotePropertyClassifier.isDate("2026-03-02"))
        #expect(!NotePropertyClassifier.isDate("March"))
    }

    @Test("text is the default")
    func text() {
        #expect(NotePropertyClassifier.kind(key: "author", value: "Sahil") == .text)
        #expect(NotePropertyClassifier.kind(key: "status", value: "Drafting") == .text)
    }

    @Test("parseTags handles inline, bracket, and block lists")
    func parseTags() {
        #expect(NotePropertyClassifier.parseTags("a, b, c") == ["a", "b", "c"])
        #expect(NotePropertyClassifier.parseTags("[one, two]") == ["one", "two"])
        #expect(NotePropertyClassifier.parseTags("- alpha\n- beta") == ["alpha", "beta"])
        #expect(NotePropertyClassifier.parseTags("\"q\", 'r'") == ["q", "r"])
    }

    @Test("serializeTags emits an inline flow list")
    func serializeTags() {
        #expect(NotePropertyClassifier.serializeTags(["a", "b"]) == "[a, b]")
        #expect(NotePropertyClassifier.serializeTags([" x ", "", "y"]) == "[x, y]")
    }

    @Test("date round-trips date-only and datetime")
    func dateRoundTrip() {
        let day = NotePropertyClassifier.date(from: "2026-03-02")
        #expect(day != nil)
        #expect(NotePropertyClassifier.dateString(from: day!, dateOnly: true) == "2026-03-02")
        let dt = NotePropertyClassifier.date(from: "2026-03-02T10:00:00Z")
        #expect(dt != nil)
        #expect(NotePropertyClassifier.dateString(from: dt!, dateOnly: false).hasPrefix("2026-03-02T10:00:00"))
    }
}
