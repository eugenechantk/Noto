import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.noto.vault", category: "LibraryModel")

/// Library's data, shared by the home page and folder pages for one vault.
///
/// Cache first: `loadCache()` publishes the snapshot saved by the last scan, so
/// Library shows at once after a relaunch. `refresh()` rescans the vault off the
/// main actor and swaps the result in silently. The spinner state (`isFirstLoad`)
/// only exists when there is no saved snapshot yet.
@MainActor
@Observable
public final class LibraryModel {
    public private(set) var snapshot: LibrarySnapshot?
    /// Set only when a scan fails with nothing to show; a stale list beats an error.
    public private(set) var errorMessage: String?
    public private(set) var hasCheckedCache = false

    /// True while the very first scan runs with no saved snapshot to show.
    public var isFirstLoad: Bool { hasCheckedCache && snapshot == nil && errorMessage == nil }

    public let vaultRootURL: URL
    private let cache: LibrarySnapshotCache?
    /// Scans the vault, given the current snapshot so it reads only what changed.
    private let loader: @Sendable (URL, LibrarySnapshot?) throws -> LibrarySnapshot
    private var cacheRead: Task<Void, Never>?
    private var scan: Task<Void, Never>?
    private var needsAnotherPass = false
    /// The snapshot known to be on disk, so an unchanged scan skips the write.
    private var persisted: LibrarySnapshot?

    public init(
        vaultRootURL: URL,
        cache: LibrarySnapshotCache? = .standard,
        loader: @escaping @Sendable (URL, LibrarySnapshot?) throws -> LibrarySnapshot = { try LibraryCatalog(vaultRootURL: $0).load(previous: $1) }
    ) {
        self.vaultRootURL = vaultRootURL
        self.cache = cache
        self.loader = loader
    }

    /// Reads the saved snapshot off the main actor. Safe to call repeatedly; a
    /// read never replaces a snapshot a scan has already published.
    public func loadCache() async {
        if let cacheRead {
            await cacheRead.value
            return
        }
        let cache = cache
        let root = vaultRootURL
        let task = Task {
            let cached = await Task.detached(priority: .userInitiated) { cache?.read(vaultRootURL: root) }.value
            if snapshot == nil, let cached {
                snapshot = cached
                persisted = cached
            }
            hasCheckedCache = true
        }
        cacheRead = task
        await task.value
    }

    /// Rescans the vault in the background. A call made while a scan runs waits
    /// for it plus one more pass, so a change made mid-scan is never missed, and
    /// any number of such calls cost only that one extra pass.
    public func refresh() async {
        await loadCache()
        if let scan {
            needsAnotherPass = true
            await scan.value
            return
        }
        let task = Task {
            repeat {
                needsAnotherPass = false
                await scanOnce()
            } while needsAnotherPass
            scan = nil
        }
        scan = task
        await task.value
    }

    private func scanOnce() async {
        let root = vaultRootURL
        let loader = loader
        let previous = snapshot
        let started = Date()
        let result = await Task.detached(priority: .userInitiated) { Result { try loader(root, previous) } }.value
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        switch result {
        case .success(let fresh):
            logger.info("library scan: \(fresh.notes.count) notes in \(elapsed) ms (from \(previous == nil ? "nothing" : "saved snapshot", privacy: .public))")
            errorMessage = nil
            if snapshot != fresh { snapshot = fresh }
            guard persisted != fresh, let cache else { return }
            persisted = fresh
            await Task.detached(priority: .utility) {
                do {
                    try cache.write(fresh, vaultRootURL: root)
                } catch {
                    logger.error("library cache write failed: \(error.localizedDescription, privacy: .public)")
                }
            }.value
        case .failure(let error):
            logger.error("library scan failed: \(error.localizedDescription, privacy: .public)")
            if snapshot == nil { errorMessage = error.localizedDescription }
        }
    }
}
