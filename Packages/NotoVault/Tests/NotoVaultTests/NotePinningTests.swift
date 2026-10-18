import Foundation
import Testing
@testable import NotoVault

struct NotePinningTests {
    @Test func preservesUnrelatedBytesAndLineEndings() {
        let original = "---\r\nid: a\r\nmodified: yesterday\r\ntags: [a, b] # keep\r\n---\r\n\r\n# Héllo 🌿\r\nbody\r\n"
        let pinned = NotePinning.settingPinned(true, in: original)
        #expect(pinned == original.replacingOccurrences(of: "tags: [a, b] # keep\r\n", with: "tags: [a, b] # keep\r\npinned: true\r\n"))
        #expect(NotePinning.isPinned(in: pinned))
        #expect(NotePinning.settingPinned(false, in: pinned) == original)
        #expect(NotePinning.settingPinned(true, in: pinned) == pinned)
    }

    @Test func changesOnlyTopLevelPinAndKeepsComment() {
        let original = "---\npinned: false  # a comment\nmetadata:\n  pinned: true\n---\n\npinned: false\n"
        let pinned = NotePinning.settingPinned(true, in: original)
        #expect(pinned == original.replacingOccurrences(of: "pinned: false  #", with: "pinned: true  #"))
        #expect(NotePinning.settingPinned(false, in: pinned) == "---\nmetadata:\n  pinned: true\n---\n\npinned: false\n")
        #expect(!NotePinning.isPinned(in: "---\nmetadata:\n  pinned: true\n---\n"))
        #expect(!NotePinning.isPinned(in: "---\npinned: \"true\"\n---\n"))
    }

    @Test func handlesAbsentAndMalformedFrontmatter() {
        #expect(NotePinning.settingPinned(false, in: "hello") == "hello")
        #expect(NotePinning.settingPinned(true, in: "hello") == "---\npinned: true\n---\nhello")
        let malformed = "---\ntags: [a]\nhello"
        #expect(NotePinning.settingPinned(true, in: malformed) == malformed)
        #expect(!NotePinning.isPinned(in: malformed))
    }

    @Test func persistsAndListsByTitleIncludingPinnedCaptures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("inbox"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let zebra = root.appendingPathComponent("z.md")
        let alpha = root.appendingPathComponent("a.md")
        let capture = root.appendingPathComponent("inbox/capture.md")
        try "---\nmodified: keep\n---\n# Zebra\n".write(to: zebra, atomically: true, encoding: .utf8)
        try "# Alpha\n".write(to: alpha, atomically: true, encoding: .utf8)
        try "---\npinned: true\n---\n# Capture\n".write(to: capture, atomically: true, encoding: .utf8)
        let service = NotePinning(vaultRootURL: root)
        try service.setPinned(true, at: zebra)
        try service.setPinned(true, at: alpha)
        #expect(service.pinnedNotes().map(\.title) == ["Alpha", "Capture", "Zebra"])
        #expect(try String(contentsOf: zebra, encoding: .utf8) == "---\nmodified: keep\npinned: true\n---\n# Zebra\n")
        try service.setPinned(false, at: zebra)
        #expect(service.pinnedNotes().map(\.title) == ["Alpha", "Capture"])
        #expect(throws: NotePinning.PinError.self) { try service.setPinned(true, at: root.appendingPathComponent("missing.md")) }
    }
}
