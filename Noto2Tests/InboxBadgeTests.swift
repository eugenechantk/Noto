import Foundation
import Testing
@testable import Noto2

@MainActor
struct InboxBadgeTests {
    @Test func badgeTracksDueCapturesAndClearsWhenVaultCloses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Badge-\(UUID())")
        let inbox = root.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_792_281_600)
        let formatter = ISO8601DateFormatter()
        for (name, snooze) in [("ready", ""), ("later", "snoozed_until: \(formatter.string(from: date.addingTimeInterval(3600)))\n")] {
            let text = "---\nid: \(UUID())\n\(snooze)---\nA capture"
            try text.write(to: inbox.appendingPathComponent(name + ".md"), atomically: true, encoding: .utf8)
        }
        let model = InboxBadgeModel()
        await model.refresh(vaultURL: root, now: date)
        #expect(model.count == 1)
        await model.refresh(vaultURL: root, now: date.addingTimeInterval(7200))
        #expect(model.count == 2)
        try FileManager.default.removeItem(at: inbox.appendingPathComponent("ready.md"))
        await model.refresh(vaultURL: root, now: date)
        #expect(model.count == 0)
        await model.refresh(vaultURL: nil)
        #expect(model.count == 0)
    }
}
