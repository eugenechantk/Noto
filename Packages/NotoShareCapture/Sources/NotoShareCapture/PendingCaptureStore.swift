import Foundation

/// A capture the share extension staged for the app to file into the vault.
public struct PendingCapture: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let body: String
    /// When it was shared — the app files it under this date, not the drain date.
    public let createdAt: Date

    public init(id: UUID = UUID(), body: String, createdAt: Date = Date()) {
        self.id = id
        self.body = body
        // Millisecond precision: that is what the file stores, so a capture
        // compares equal to itself after a round trip through disk.
        self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

/// The hand-off between the share extension and Noto 2. The extension cannot
/// reach the vault (an iCloud Drive folder held through the app's own
/// security-scoped bookmark), so it writes one JSON file per capture into the
/// App Group container and the app drains that folder on its next activation.
///
/// One file per capture, never a single mutable list: the extension and the
/// app can run concurrently and must not clobber each other's writes.
public struct PendingCaptureStore: Sendable {
    public static let appGroupIdentifier = "group.com.eugenechan.Noto2"
    public static let folderName = "pending-captures"

    public enum StoreError: Error, Equatable {
        case containerUnavailable
        case writeFailed(String)
    }

    public let folderURL: URL

    public init(containerURL: URL) {
        folderURL = containerURL.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    /// The store inside the shared App Group container, or nil when the process
    /// lacks the entitlement (a misconfigured build — never silently write elsewhere).
    public static func appGroup(_ identifier: String = appGroupIdentifier) -> PendingCaptureStore? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return PendingCaptureStore(containerURL: container)
    }

    @discardableResult
    public func enqueue(_ capture: PendingCapture) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw StoreError.writeFailed("could not create \(Self.folderName)/: \(error.localizedDescription)")
        }
        let fileURL = folderURL.appendingPathComponent(Self.fileName(for: capture))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        do {
            try encoder.encode(capture).write(to: fileURL, options: .atomic)
        } catch {
            throw StoreError.writeFailed("could not write \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        return fileURL
    }

    public func enqueue(body: String, at date: Date = Date()) throws -> PendingCapture {
        let capture = PendingCapture(body: body, createdAt: date)
        try enqueue(capture)
        return capture
    }

    /// Every staged capture, oldest first. Files that do not decode are skipped
    /// (logged by the caller if it cares) rather than blocking the rest.
    public func pending() -> [PendingCapture] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return names
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> PendingCapture? in
                guard let data = try? Data(contentsOf: folderURL.appendingPathComponent(name)) else { return nil }
                return try? decoder.decode(PendingCapture.self, from: data)
            }
            .sorted { lhs, rhs in
                lhs.createdAt == rhs.createdAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.createdAt < rhs.createdAt
            }
    }

    public var isEmpty: Bool { pending().isEmpty }

    public func remove(_ capture: PendingCapture) {
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(Self.fileName(for: capture)))
    }

    /// `<unix-ms>-<uuid>.json` — sortable by name too, and unique per capture.
    static func fileName(for capture: PendingCapture) -> String {
        let millis = Int64((capture.createdAt.timeIntervalSince1970 * 1000).rounded())
        return "\(String(format: "%015lld", millis))-\(capture.id.uuidString).json"
    }
}
