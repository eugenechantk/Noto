import Foundation
import Testing
@testable import NotoShareCapture

/// Test case index
/// 1. acceptedJobLeavesNoOutboxCopy — deliver() sends and clears the outbox on success (SC2)
/// 2. failedJobStaysInOutboxAndFlushSendsItLater — a rejected send keeps the job; flush() re-sends and clears it (SC2)
/// 3. flushSendsOldestFirstAndCountsAccepted — flush order and return value (SC2)
/// 4. endpointReadsInfoPlistAndIgnoresUnexpandedVariables — Info.plist keys → endpoint; blank / $(VAR) / http are rejected (SC2)
/// 5. requestIsAuthenticatedJSONPost — method, bearer header, content type, body decodes to the job (SC2)
struct ShareMediaDeliveryTests {
    private func makeOutbox() throws -> ShareMediaOutbox {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareMediaOutbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ShareMediaOutbox(containerURL: url)
    }

    private func job(_ seconds: TimeInterval) -> ShareMediaJob {
        ShareMediaJob(captureId: UUID(), url: URL(string: "https://x.com/a/status/\(Int(seconds))")!, platform: .x,
                      notePath: "inbox/2026-09-23-1a2b3c4d.md", sharedAt: Date(timeIntervalSince1970: seconds), title: nil)
    }

    actor Recorder {
        var sent: [UUID] = []
        var failing = true
        func record(_ id: UUID) { sent.append(id) }
        func setFailing(_ value: Bool) { failing = value }
    }

    @Test func acceptedJobLeavesNoOutboxCopy() async throws {
        let outbox = try makeOutbox()
        let recorder = Recorder()
        let dispatcher = ShareMediaDispatcher(outbox: outbox) { await recorder.record($0.captureId) }
        let job = job(1)
        #expect(await dispatcher.deliver(job))
        #expect(await recorder.sent == [job.captureId])
        #expect(outbox.pending().isEmpty)
    }

    @Test func failedJobStaysInOutboxAndFlushSendsItLater() async throws {
        let outbox = try makeOutbox()
        let recorder = Recorder()
        let dispatcher = ShareMediaDispatcher(outbox: outbox) { job in
            if await recorder.failing { throw ShareMediaDeliveryError.rejected(status: 503) }
            await recorder.record(job.captureId)
        }
        let job = job(1)
        #expect(await dispatcher.deliver(job) == false)
        #expect(outbox.pending() == [job])

        await recorder.setFailing(false)
        #expect(await dispatcher.flush() == 1)
        #expect(outbox.pending().isEmpty)
        #expect(await recorder.sent == [job.captureId])
    }

    @Test func flushSendsOldestFirstAndCountsAccepted() async throws {
        let outbox = try makeOutbox()
        let late = job(30), early = job(10), middle = job(20)
        for item in [late, early, middle] { try outbox.enqueue(item) }
        let recorder = Recorder()
        let dispatcher = ShareMediaDispatcher(outbox: outbox) { await recorder.record($0.captureId) }
        #expect(await dispatcher.flush() == 3)
        #expect(await recorder.sent == [early.captureId, middle.captureId, late.captureId])
    }

    @Test func endpointReadsInfoPlistAndIgnoresUnexpandedVariables() {
        let good = ShareMediaEndpoint(infoDictionary: ["NotoShareMediaEndpoint": "https://example.com/noto/share-media", "NotoShareMediaToken": "abc"])
        #expect(good?.url.absoluteString == "https://example.com/noto/share-media")
        #expect(good?.token == "abc")
        #expect(ShareMediaEndpoint(infoDictionary: ["NotoShareMediaEndpoint": "https://example.com", "NotoShareMediaToken": "$(NOTO_SHARE_MEDIA_TOKEN)"]) == nil)
        #expect(ShareMediaEndpoint(infoDictionary: ["NotoShareMediaEndpoint": "https://example.com", "NotoShareMediaToken": ""]) == nil)
        #expect(ShareMediaEndpoint(infoDictionary: ["NotoShareMediaEndpoint": "http://example.com", "NotoShareMediaToken": "abc"]) == nil)
        #expect(ShareMediaEndpoint(infoDictionary: nil) == nil)
    }

    @Test func requestIsAuthenticatedJSONPost() throws {
        let endpoint = ShareMediaEndpoint(url: URL(string: "https://example.com/noto/share-media")!, token: "s3cret")
        let job = job(1)
        let request = try endpoint.request(for: job)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer s3cret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try ShareMediaJob.decoder.decode(ShareMediaJob.self, from: try #require(request.httpBody)) == job)
    }
}
