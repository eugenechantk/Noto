import Foundation
import NotoShareCapture
import Testing
@testable import Noto2

/// Test case index
/// 1. drainFilesEachCaptureIntoInboxAndClearsStaging — every staged capture becomes inbox/<date>-<sha8>.md with standard frontmatter and the staging folder is emptied (SC4)
/// 2. drainStampsFileWithShareDateNotDrainDate — the inbox filename and `created:` use the moment the link was shared (SC4)
/// 3. failedWriteLeavesCaptureStaged — a failing vault write reports the capture as failed and keeps it staged for the next drain (SC4)
/// 4. drainWithEmptyStoreIsNoOp — nothing staged → nothing filed, nothing created under the vault (SC4)
/// 5. duplicateBodySameDayIsIdempotentAndStillCleared — re-sharing the same link on the same day reuses the existing file and clears the staged copy (SC4)
struct SharedCaptureDrainTests {
    private func makeDir(_ prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A drain whose filing service writes with plain FileManager (no file
    /// coordination) and a UTC calendar so filenames are deterministic.
    private func makeDrain(store: PendingCaptureStore, vault: URL, writeFails: Bool = false) -> SharedCaptureDrain {
        var drain = SharedCaptureDrain(store: store, vaultURL: vault)
        let calendar = utc
        drain.makeService = { vaultURL in
            var service = CaptureFilingService(vaultURL: vaultURL)
            service.calendar = calendar
            service.createDirectory = { url in
                (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
            }
            service.writeString = { content, url in
                if writeFails { return false }
                return (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil
            }
            return service
        }
        return drain
    }

    private let sharedAt = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17T20:53:20Z

    @Test func drainFilesEachCaptureIntoInboxAndClearsStaging() throws {
        let store = PendingCaptureStore(containerURL: try makeDir("group"))
        let vault = try makeDir("vault")
        let one = try store.enqueue(body: "[One](https://a.example/one)", at: sharedAt)
        let two = try store.enqueue(body: "[Two](https://a.example/two)", at: sharedAt.addingTimeInterval(5))

        let outcome = makeDrain(store: store, vault: vault).drain()

        #expect(outcome.failed.isEmpty)
        #expect(outcome.filed.count == 2)
        // Each result is paired with the staged capture it came from, so the
        // app can open the note the share sheet asked for.
        #expect(outcome.filed.map(\.capture) == [one, two])
        #expect(outcome.filed.allSatisfy { $0.filed.didCreate })
        #expect(outcome.filed.map(\.filed.relativePath).allSatisfy { $0.hasPrefix("inbox/2026-08-17-") && $0.hasSuffix(".md") })
        #expect(store.pending().isEmpty)

        let first = try #require(outcome.filed.first?.filed)
        let content = try String(contentsOf: first.fileURL, encoding: .utf8)
        #expect(content.hasPrefix("---\nid: \(first.id.uuidString)\ncreated: 2026-08-17T20:53:20Z\nupdated: 2026-08-17T20:53:20Z\ntype: note\nstatus: inbox\n---\n\n"))
        #expect(content.hasSuffix("[One](https://a.example/one)\n"))
    }

    @Test func drainStampsFileWithShareDateNotDrainDate() throws {
        let store = PendingCaptureStore(containerURL: try makeDir("group"))
        let vault = try makeDir("vault")
        // Shared "yesterday" relative to any plausible drain moment.
        try store.enqueue(body: "[Old](https://a.example/old)", at: sharedAt)

        let outcome = makeDrain(store: store, vault: vault).drain()
        let filed = try #require(outcome.filed.first?.filed)
        #expect(filed.relativePath.hasPrefix("inbox/2026-08-17-"))
        let expectedHash = CaptureFilingService.hash8(of: "[Old](https://a.example/old)")
        #expect(filed.relativePath == "inbox/2026-08-17-\(expectedHash).md")
    }

    @Test func failedWriteLeavesCaptureStaged() throws {
        let store = PendingCaptureStore(containerURL: try makeDir("group"))
        let vault = try makeDir("vault")
        let capture = try store.enqueue(body: "[Keep](https://a.example/keep)", at: sharedAt)

        let outcome = makeDrain(store: store, vault: vault, writeFails: true).drain()

        #expect(outcome.filed.isEmpty)
        #expect(outcome.failed == [capture])
        #expect(store.pending() == [capture])
        let inbox = vault.appendingPathComponent("inbox")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []
        #expect(files.isEmpty)

        // The next drain, with the vault writable again, files it.
        let retry = makeDrain(store: store, vault: vault).drain()
        #expect(retry.filed.count == 1)
        #expect(store.pending().isEmpty)
    }

    @Test func drainWithEmptyStoreIsNoOp() throws {
        let store = PendingCaptureStore(containerURL: try makeDir("group"))
        let vault = try makeDir("vault")
        let outcome = makeDrain(store: store, vault: vault).drain()
        #expect(outcome == SharedCaptureDrain.Outcome())
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("inbox").path))
    }

    @Test func duplicateBodySameDayIsIdempotentAndStillCleared() throws {
        let store = PendingCaptureStore(containerURL: try makeDir("group"))
        let vault = try makeDir("vault")
        try store.enqueue(body: "[Same](https://a.example/same)", at: sharedAt)
        try store.enqueue(body: "[Same](https://a.example/same)", at: sharedAt.addingTimeInterval(120))

        let outcome = makeDrain(store: store, vault: vault).drain()
        #expect(outcome.filed.count == 2)
        #expect(outcome.filed[0].filed.didCreate)
        #expect(!outcome.filed[1].filed.didCreate)
        #expect(outcome.filed[0].filed.fileURL == outcome.filed[1].filed.fileURL)
        #expect(store.pending().isEmpty)
    }
}
