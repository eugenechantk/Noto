import Foundation
import Testing
@testable import NotoVault

/// Test case index — cache-first Library loading (feature noto2-library-cache, SC3–SC8).
/// 1. cachedSnapshotShowsWithoutScanning — a saved snapshot shows with no scan and no spinner
/// 2. firstLoadShowsUntilFirstScan — with no cache, the first-load state lasts until a scan publishes
/// 3. refreshReplacesSnapshotAndPersistsIt — a scan swaps in fresh data and saves it to disk
/// 4. failedScanKeepsLastSnapshot — a failing scan keeps the last snapshot and shows no error
/// 5. failedFirstScanSurfacesError — with nothing to show, a failing scan reports its error
/// 6. overlappingRefreshesCoalesceIntoOneExtraPass — refreshes during a scan add one pass, not one each
/// 7. lateCacheReadNeverReplacesFresherScan — a cache read after a scan does not roll the list back
/// 8. scanStartsFromTheCurrentSnapshot — each scan gets the snapshot on screen, so it reads only changes
@MainActor
struct LibraryModelTests {
    @Test func cachedSnapshotShowsWithoutScanning() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let cached = Fixture.snapshot(vault: fixture.vault)
        try fixture.cache.write(cached, vaultRootURL: fixture.vault)
        let scans = ScanRecorder(result: .success(Fixture.snapshot(vault: fixture.vault, titles: ["Fresh"])))
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: scans.load)

        await model.loadCache()

        #expect(model.snapshot == cached)
        #expect(!model.isFirstLoad)
        #expect(scans.count == 0)
    }

    @Test func firstLoadShowsUntilFirstScan() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let fresh = Fixture.snapshot(vault: fixture.vault)
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: ScanRecorder(result: .success(fresh)).load)

        #expect(!model.isFirstLoad) // the cache has not been checked yet: show nothing, not a spinner
        await model.loadCache()
        #expect(model.isFirstLoad)
        await model.refresh()
        #expect(!model.isFirstLoad)
        #expect(model.snapshot == fresh)
    }

    @Test func refreshReplacesSnapshotAndPersistsIt() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        try fixture.cache.write(Fixture.snapshot(vault: fixture.vault), vaultRootURL: fixture.vault)
        let fresh = Fixture.snapshot(vault: fixture.vault, titles: ["Roadmap", "Groceries", "New idea"])
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: ScanRecorder(result: .success(fresh)).load)

        await model.refresh()

        #expect(model.snapshot == fresh)
        #expect(fixture.cache.read(vaultRootURL: fixture.vault) == fresh)
    }

    @Test func failedScanKeepsLastSnapshot() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let cached = Fixture.snapshot(vault: fixture.vault)
        try fixture.cache.write(cached, vaultRootURL: fixture.vault)
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: ScanRecorder(result: .failure(CocoaError(.fileReadNoPermission))).load)

        await model.refresh()

        #expect(model.snapshot == cached)
        #expect(model.errorMessage == nil)
        #expect(fixture.cache.read(vaultRootURL: fixture.vault) == cached)
    }

    @Test func failedFirstScanSurfacesError() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: ScanRecorder(result: .failure(CocoaError(.fileReadNoPermission))).load)

        await model.refresh()

        #expect(model.snapshot == nil)
        #expect(model.errorMessage != nil)
        #expect(!model.isFirstLoad)
    }

    @Test func overlappingRefreshesCoalesceIntoOneExtraPass() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let scans = ScanRecorder(result: .success(Fixture.snapshot(vault: fixture.vault)), delay: 0.2)
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: scans.load)

        let first = Task { await model.refresh() }
        while scans.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
        // Three more requests while the first scan runs: a file changed mid-scan,
        // so one more pass is needed — but only one.
        async let a: Void = model.refresh()
        async let b: Void = model.refresh()
        async let c: Void = model.refresh()
        _ = await (a, b, c)
        await first.value

        #expect(scans.count == 2)
    }

    @Test func lateCacheReadNeverReplacesFresherScan() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let fresh = Fixture.snapshot(vault: fixture.vault, titles: ["Fresh"])
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: ScanRecorder(result: .success(fresh)).load)
        await model.refresh()
        // Another writer saves an older snapshot; reading the cache again must not roll back.
        try fixture.cache.write(Fixture.snapshot(vault: fixture.vault), vaultRootURL: fixture.vault)

        await model.loadCache()

        #expect(model.snapshot == fresh)
    }

    @Test func scanStartsFromTheCurrentSnapshot() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let cached = Fixture.snapshot(vault: fixture.vault)
        try fixture.cache.write(cached, vaultRootURL: fixture.vault)
        let fresh = Fixture.snapshot(vault: fixture.vault, titles: ["Fresh"])
        let scans = ScanRecorder(result: .success(fresh))
        let model = LibraryModel(vaultRootURL: fixture.vault, cache: fixture.cache, loader: scans.load)

        await model.refresh()
        await model.refresh()

        #expect(scans.previousSnapshots == [cached, fresh])
    }
}

/// Counts scans and returns a fixed result, optionally after a delay.
final class ScanRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var previous: [LibrarySnapshot?] = []
    private let result: Result<LibrarySnapshot, Error>
    private let delay: TimeInterval

    init(result: Result<LibrarySnapshot, Error>, delay: TimeInterval = 0) {
        self.result = result
        self.delay = delay
    }

    var count: Int { lock.withLock { calls } }
    var previousSnapshots: [LibrarySnapshot?] { lock.withLock { previous } }

    var load: @Sendable (URL, LibrarySnapshot?) throws -> LibrarySnapshot {
        { [self] _, previousSnapshot in
            lock.withLock {
                calls += 1
                previous.append(previousSnapshot)
            }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return try result.get()
        }
    }
}
