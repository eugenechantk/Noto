import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. slugIsDateAndSha8 — relative path is inbox/<YYYY-MM-DD>-<8 hex>.md from the normalized body (SC1)
/// 2. frontmatterHasRequiredKeys — id/created/updated/type: note/status: inbox, body verbatim after (SC1)
/// 3. writesFileUnderInbox — filing creates inbox/ and the file with the expected content (SC1)
/// 4. sameBodySameDayIsIdempotent — second filing of identical text returns the same path, didCreate false, file untouched (SC1)
/// 5. whitespaceBodyIsRejected — empty / whitespace-only bodies throw emptyBody and plannedURL is nil (SC2)
/// 6. normalizationIgnoresLineEndingsAndOuterWhitespace — CRLF and padding hash the same (SC1)
struct CaptureFilingServiceTests {
    private func makeVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Noto2CaptureVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeService(vault: URL, date: Date, id: UUID = UUID()) -> CaptureFilingService {
        var service = CaptureFilingService(vaultURL: vault)
        service.now = { date }
        service.makeID = { id }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        service.calendar = utc
        return service
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17T20:53:20Z

    @Test func slugIsDateAndSha8() throws {
        let body = CaptureFilingService.normalizedBody("Ship the capture screen")
        let path = CaptureFilingService.relativePath(for: body, date: fixedDate, calendar: {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
        }())
        #expect(path.hasPrefix("inbox/2026-08-17-"))
        #expect(path.hasSuffix(".md"))
        let hash = path.dropFirst("inbox/2026-08-17-".count).dropLast(3)
        #expect(hash.count == 8)
        #expect(hash.allSatisfy { $0.isHexDigit })
        #expect(String(hash) == CaptureFilingService.hash8(of: body))
    }

    @Test func frontmatterHasRequiredKeys() throws {
        let id = UUID()
        let doc = CaptureFilingService.document(body: "A thought\nwith two lines", id: id, date: fixedDate)
        let lines = doc.components(separatedBy: "\n")
        #expect(lines[0] == "---")
        #expect(lines[1] == "id: \(id.uuidString)")
        #expect(lines[2] == "created: 2026-08-17T20:53:20Z")
        #expect(lines[3] == "updated: 2026-08-17T20:53:20Z")
        #expect(lines[4] == "type: note")
        #expect(lines[5] == "status: inbox")
        #expect(lines[6] == "---")
        #expect(doc.hasSuffix("---\n\nA thought\nwith two lines\n"))
    }

    @Test func writesFileUnderInbox() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let id = UUID()
        let service = makeService(vault: vault, date: fixedDate, id: id)

        let filed = try service.file("  Buy oat milk  \n")

        #expect(filed.didCreate)
        #expect(filed.id == id)
        #expect(filed.relativePath == "inbox/2026-08-17-\(CaptureFilingService.hash8(of: "Buy oat milk")).md")
        #expect(filed.fileURL == vault.appendingPathComponent(filed.relativePath))
        let content = try String(contentsOf: filed.fileURL, encoding: .utf8)
        #expect(content == CaptureFilingService.document(body: "Buy oat milk", id: id, date: fixedDate))
        #expect(service.plannedURL(for: "Buy oat milk") == filed.fileURL)
    }

    @Test func sameBodySameDayIsIdempotent() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let first = try makeService(vault: vault, date: fixedDate, id: UUID()).file("Same thought")
        let before = try String(contentsOf: first.fileURL, encoding: .utf8)

        let second = try makeService(vault: vault, date: fixedDate.addingTimeInterval(3600), id: UUID()).file("Same thought")

        #expect(second.didCreate == false)
        #expect(second.fileURL == first.fileURL)
        #expect(second.id == first.id)
        #expect(try String(contentsOf: first.fileURL, encoding: .utf8) == before)
    }

    @Test func whitespaceBodyIsRejected() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = makeService(vault: vault, date: fixedDate)
        #expect(service.plannedURL(for: "   \n\t ") == nil)
        #expect(throws: CaptureFilingService.FilingError.emptyBody) {
            try service.file("   \n\t ")
        }
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("inbox").path))
    }

    @Test func normalizationIgnoresLineEndingsAndOuterWhitespace() {
        let a = CaptureFilingService.normalizedBody("line one\r\nline two\r\n")
        let b = CaptureFilingService.normalizedBody("\n  line one\nline two  ")
        #expect(a == b)
        #expect(CaptureFilingService.hash8(of: a) == CaptureFilingService.hash8(of: b))
        #expect(CaptureFilingService.hash8(of: "x") != CaptureFilingService.hash8(of: "y"))
    }
}
