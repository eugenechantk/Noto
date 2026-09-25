import Foundation
import NotoShareCapture

/// A downloaded post whose block is waiting for its capture note to appear
/// (Noto 2 files the note when it next becomes active). Persisted in the
/// state directory so a Hermes restart loses nothing.
public struct PendingAppend: Codable, Equatable, Sendable {
    public let job: ShareMediaJob
    public let block: String
    public let downloadedAt: Date
    public var lastSearchedAt: Date?
    /// Set once the block is in the note; the record then lives on for the
    /// verify window so an autosave that raced the append cannot drop it.
    public var appendedAt: Date?
    /// Vault-relative path of the note the block went into.
    public var appendedNotePath: String?
}

public struct PendingAppendStore: Sendable {
    let folderURL: URL

    public init(stateDirectory: URL) {
        folderURL = stateDirectory.appendingPathComponent("pending-appends", isDirectory: true)
    }

    public func save(_ item: PendingAppend) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try ShareMediaJob.encoder.encode(item).write(to: url(for: item.job), options: .atomic)
    }

    public func all() -> [PendingAppend] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { try? Data(contentsOf: folderURL.appendingPathComponent($0)) }
            .compactMap { try? ShareMediaJob.decoder.decode(PendingAppend.self, from: $0) }
            .sorted { $0.downloadedAt < $1.downloadedAt }
    }

    public func remove(_ item: PendingAppend) {
        try? FileManager.default.removeItem(at: url(for: item.job))
    }

    private func url(for job: ShareMediaJob) -> URL {
        folderURL.appendingPathComponent("\(job.captureId.uuidString).json")
    }
}

/// Everything Hermes does per run, minus the queue transport: resolve and
/// download a job's post, park the block, and append every parked block whose
/// note now exists.
public struct ShareMediaProcessor: Sendable {
    /// A parked block older than this is dropped (the capture was discarded).
    public static let giveUpAfter: TimeInterval = 7 * 24 * 3600
    /// How often a parked block may trigger a whole-vault search by URL.
    public static let searchInterval: TimeInterval = 15 * 60
    /// After appending, how long to keep checking that the block is still in
    /// the note. An editor autosave carrying text typed before the append can
    /// overwrite it; within this window it is put back.
    public static let verifyWindow: TimeInterval = 10 * 60

    let vaultURL: URL
    let store: PendingAppendStore
    let resolver: SocialPostResolver
    let downloader: MediaDownloader
    let now: @Sendable () -> Date

    public init(vaultURL: URL, stateDirectory: URL, http: any HTTPFetching = URLSessionFetcher(),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.vaultURL = vaultURL
        self.store = PendingAppendStore(stateDirectory: stateDirectory)
        self.resolver = SocialPostResolver(http: http)
        self.downloader = MediaDownloader(vaultURL: vaultURL, http: http)
        self.now = now
    }

    /// Resolves and downloads now (Instagram media URLs expire), then parks the block.
    public func accept(_ job: ShareMediaJob) async throws -> SocialPost {
        let post = try await resolver.resolve(job.url)
        let paths = try await downloader.download(post)
        let block = ShareMediaMarkdown.block(for: post, paths: paths)
        try store.save(PendingAppend(job: job, block: block, downloadedAt: now(), lastSearchedAt: nil))
        return post
    }

    public enum AppendOutcome: Equatable {
        case appended(job: UUID, note: String)
        case alreadyPresent(job: UUID, note: String)
        case restored(job: UUID, note: String)
        case waiting(job: UUID)
        case gaveUp(job: UUID)
        case failed(job: UUID, reason: String)
    }

    public func appendPending() -> [AppendOutcome] {
        let appender = CaptureNoteAppender(vaultURL: vaultURL)
        var outcomes: [AppendOutcome] = []
        for var item in store.all() {
            let id = item.job.captureId
            if let appendedAt = item.appendedAt {
                verify(&item, appendedAt: appendedAt, appender: appender, outcomes: &outcomes)
                continue
            }
            let mayScan = item.lastSearchedAt.map { now().timeIntervalSince($0) >= Self.searchInterval } ?? true
            guard let note = appender.locate(item.job, searchVault: mayScan) else {
                if now().timeIntervalSince(item.downloadedAt) > Self.giveUpAfter {
                    store.remove(item)
                    outcomes.append(.gaveUp(job: id))
                } else {
                    if mayScan { item.lastSearchedAt = now(); try? store.save(item) }
                    outcomes.append(.waiting(job: id))
                }
                continue
            }
            let relative = relativePath(of: note)
            do {
                switch try appender.append(item.block, to: note) {
                case .appended: outcomes.append(.appended(job: id, note: relative))
                case .alreadyPresent: outcomes.append(.alreadyPresent(job: id, note: relative))
                }
                item.appendedAt = now()
                item.appendedNotePath = relative
                try? store.save(item)
            } catch {
                outcomes.append(.failed(job: id, reason: error.localizedDescription))
            }
        }
        return outcomes
    }

    /// Within the verify window, puts the block back if it vanished; after it,
    /// forgets the job.
    private func verify(_ item: inout PendingAppend, appendedAt: Date, appender: CaptureNoteAppender,
                        outcomes: inout [AppendOutcome]) {
        guard now().timeIntervalSince(appendedAt) <= Self.verifyWindow,
              let relative = item.appendedNotePath else {
            store.remove(item)
            return
        }
        let note = vaultURL.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: note.path) else {
            // Moved or deleted since (Digest filed it) — nothing left to guard.
            store.remove(item)
            return
        }
        if (try? appender.append(item.block, to: note)) == .appended {
            outcomes.append(.restored(job: item.job.captureId, note: relative))
        }
    }

    private func relativePath(of note: URL) -> String {
        let root = vaultURL.standardizedFileURL.path
        let path = note.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }
}
