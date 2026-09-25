import Foundation

/// Jobs waiting to reach the Worker, one JSON file each in the App Group
/// (`pending-media-jobs/`), so a share made offline is not lost: the extension
/// writes here first, and both it and the app remove a job only after the
/// Worker accepted it.
public struct ShareMediaOutbox: Sendable {
    public static let folderName = "pending-media-jobs"
    public let folderURL: URL

    public init(containerURL: URL) {
        folderURL = containerURL.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    public static func appGroup(_ identifier: String = PendingCaptureStore.appGroupIdentifier) -> ShareMediaOutbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier).map(ShareMediaOutbox.init)
    }

    public func enqueue(_ job: ShareMediaJob) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try ShareMediaJob.encoder.encode(job).write(to: fileURL(for: job), options: .atomic)
    }

    /// Oldest first; undecodable files are skipped.
    public func pending() -> [ShareMediaJob] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { try? Data(contentsOf: folderURL.appendingPathComponent($0)) }
            .compactMap { try? ShareMediaJob.decoder.decode(ShareMediaJob.self, from: $0) }
            .sorted { $0.sharedAt == $1.sharedAt ? $0.captureId.uuidString < $1.captureId.uuidString : $0.sharedAt < $1.sharedAt }
    }

    public func remove(_ job: ShareMediaJob) {
        try? FileManager.default.removeItem(at: fileURL(for: job))
    }

    private func fileURL(for job: ShareMediaJob) -> URL {
        folderURL.appendingPathComponent("\(job.captureId.uuidString).json")
    }
}

/// Where jobs go: the Noto share-media Worker, authenticated with a bearer
/// token. Both values come from the bundle's Info.plist (filled from the
/// gitignored `Config/LocalSecrets.xcconfig` at build time).
public struct ShareMediaEndpoint: Sendable, Equatable {
    public static let endpointInfoKey = "NotoShareMediaEndpoint"
    public static let tokenInfoKey = "NotoShareMediaToken"

    public let url: URL
    public let token: String

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    /// nil when either value is missing, blank, or an unexpanded `$(VAR)`.
    public init?(infoDictionary: [String: Any]?) {
        guard let rawURL = (infoDictionary?[Self.endpointInfoKey] as? String)?.trimmingCharacters(in: .whitespaces),
              let token = (infoDictionary?[Self.tokenInfoKey] as? String)?.trimmingCharacters(in: .whitespaces),
              !rawURL.isEmpty, !token.isEmpty, !rawURL.contains("$("), !token.contains("$("),
              let url = URL(string: rawURL), url.scheme == "https" else {
            return nil
        }
        self.init(url: url, token: token)
    }

    public func request(for job: ShareMediaJob) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ShareMediaJob.encoder.encode(job)
        return request
    }
}

public enum ShareMediaDeliveryError: Error, Equatable {
    case rejected(status: Int)
}

/// Outbox-first delivery. `send` is injected so tests need no network.
public struct ShareMediaDispatcher: Sendable {
    public typealias Send = @Sendable (ShareMediaJob) async throws -> Void

    public let outbox: ShareMediaOutbox
    public let send: Send

    public init(outbox: ShareMediaOutbox, send: @escaping Send) {
        self.outbox = outbox
        self.send = send
    }

    /// Posts jobs to `endpoint` over `session`; any non-2xx status is a failure.
    public init(outbox: ShareMediaOutbox, endpoint: ShareMediaEndpoint, session: URLSession = .shared) {
        self.init(outbox: outbox) { job in
            let (_, response) = try await session.data(for: try endpoint.request(for: job))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw ShareMediaDeliveryError.rejected(status: status) }
        }
    }

    /// Writes the job to the outbox, then tries to send it. True when the Worker
    /// accepted it (and the outbox copy is gone); false leaves it for `flush`.
    @discardableResult
    public func deliver(_ job: ShareMediaJob) async -> Bool {
        do { try outbox.enqueue(job) } catch { return (try? await send(job)) != nil }
        return await attempt(job)
    }

    /// Re-sends everything still in the outbox. Returns how many were accepted.
    @discardableResult
    public func flush() async -> Int {
        var accepted = 0
        for job in outbox.pending() where await attempt(job) {
            accepted += 1
        }
        return accepted
    }

    private func attempt(_ job: ShareMediaJob) async -> Bool {
        do {
            try await send(job)
            outbox.remove(job)
            return true
        } catch {
            return false
        }
    }
}
