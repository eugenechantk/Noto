import NotoShareCapture
import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "RootTabView")

enum Noto2StartupPolicy {
    /// Keep launch and the first keystrokes clear of vault-wide work. Search
    /// and Browse still start their dependencies immediately when selected.
    static let backgroundWorkDelay: Duration = .seconds(3)

    static func requiresWorkspace(_ tab: Noto2Tab) -> Bool {
        tab != .capture
    }

    static func canPresentCapture(isConfigured: Bool, hasDeferredResolution: Bool) -> Bool {
        isConfigured || hasDeferredResolution
    }
}

/// Presents Capture without constructing or scanning the Browse/Search
/// workspace. Vault-wide collaborators start when those tabs are selected,
/// or after the capture-critical launch window has passed.
struct RootTabView: View {
    let vaultURL: URL?
    var locationManager: VaultLocationManager
    let launchRouter: Noto2LaunchRouter

    @State private var vaultController: VaultController?
    @State private var fileWatcher = VaultFileWatcher()
    @State private var selectedTab: Noto2Tab = .capture
    @State private var todayReselectRevision = 0
    @State private var inboxBadge = InboxBadgeModel()
    @State private var hasStartedDeferredServices = false
    /// A note another tab asked Browse to open (a just-filed capture).
    @State private var pendingNoteURL: URL?
    /// Where each share-sheet capture drained this session was filed, keyed by
    /// its staged id, so the extension's "Add notes" link can open that note.
    @State private var sharedCaptureNotes: [UUID: URL] = [:]
    /// Launch, activation and the "Keep editing" link all drain; one pass at a time (bug 036).
    @State private var drainQueue = SharedCaptureDrainQueue()
    @Environment(\.scenePhase) private var scenePhase

    init(
        vaultURL: URL?,
        locationManager: VaultLocationManager,
        launchRouter: Noto2LaunchRouter = .shared
    ) {
        self.vaultURL = vaultURL
        self.locationManager = locationManager
        self.launchRouter = launchRouter
        // UI-automation hook (set by .maestro/seed-vault.sh --initial-tab):
        // lets tooling open a specific tab without tapping the tab bar.
        let initialTab: Noto2Tab
        if let requestedTab = launchRouter.requestedTab {
            initialTab = requestedTab
        } else if let raw = UserDefaults.standard.string(forKey: "noto2.debug.initialTab"),
           let tab = Noto2Tab.resolving(raw) {
            initialTab = tab
        } else {
            initialTab = .capture
        }
        _selectedTab = State(wrappedValue: initialTab)
        _vaultController = State(wrappedValue: Noto2StartupPolicy.requiresWorkspace(initialTab)
            ? vaultURL.map { VaultController(vaultURL: $0, autoloadRoot: false) }
            : nil)
    }

    var body: some View {
        // System TabView: iOS 26 draws the floating Liquid Glass bar, and the
        // search-role tab becomes its own circle at the trailing end. Icons
        // only (Eugene, 2026-10-17); each tab's name is its accessibility label.
        TabView(selection: tabSelection) {
            Tab(value: Noto2Tab.capture) {
                CaptureScreen(vaultURL: vaultURL, onOpenFiledNote: openFiledNote)
            } label: { tabIcon(.capture) }
            Tab(value: Noto2Tab.today) {
                if let vaultController {
                    TodayScreen(vaultController: vaultController, reselectRevision: todayReselectRevision)
                } else {
                    deferredTabPlaceholder
                }
            } label: { tabIcon(.today) }
            Tab(value: Noto2Tab.digest) {
                if let vaultController {
                    DigestScreen(
                        vaultController: vaultController,
                        onOpenFiledNote: openFiledNote,
                        onCapture: { tabSelection.wrappedValue = .capture }
                    )
                } else {
                    deferredTabPlaceholder
                }
            } label: { tabIcon(.digest) }
            .badge(inboxBadge.count)
            Tab(value: Noto2Tab.browse) {
                if let vaultController {
                    BrowseScreen(
                        vaultController: vaultController,
                        locationManager: locationManager,
                        pendingNoteURL: $pendingNoteURL
                    )
                } else {
                    deferredTabPlaceholder
                }
            } label: { tabIcon(.browse) }
            Tab(value: Noto2Tab.search, role: .search) {
                if let vaultController {
                    SearchScreen(vaultController: vaultController, locationManager: locationManager)
                } else {
                    deferredTabPlaceholder
                }
            } label: { tabIcon(.search) }
        }
        .tint(NotoTheme.accent)
        // Open notes reload when their file changes on disk (iCloud edits from
        // another device, or Hermes adding share-sheet media).
        .environment(fileWatcher)
        .background(NotoTheme.background.ignoresSafeArea())
        .task(id: vaultURL) {
            guard vaultURL != nil else { return }
            // Share-sheet captures staged while the app was closed: file them
            // as soon as the vault is usable, before any vault-wide work.
            await drainSharedCaptures()
            // A notification tap that launched the app arrives before the vault resolves.
            openRequestedNoteIfNeeded()
            if Noto2StartupPolicy.requiresWorkspace(selectedTab) {
                startDeferredServicesIfNeeded()
                return
            }
            do {
                try await Task.sleep(for: Noto2StartupPolicy.backgroundWorkDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            startDeferredServicesIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await drainSharedCaptures() }
            guard hasStartedDeferredServices else { return }
            refreshInboxBadge()
            if selectedTab == .browse {
                vaultController?.refreshRootForForegroundActivation()
            }
            startSearchMaintenance()
        }
        .onChange(of: launchRouter.requestRevision) { _, _ in
            if launchRouter.requestedNotePath != nil {
                openRequestedNoteIfNeeded()
                return
            }
            guard let requestedTab = launchRouter.requestedTab else { return }
            if launchRouter.requestedSharedCaptureID != nil {
                // The share extension's "Add notes": file the staged capture
                // (if the activation drain has not already) and open its note.
                Task { await drainSharedCaptures() }
                return
            }
            tabSelection.wrappedValue = requestedTab
        }
        .onChange(of: fileWatcher.changeCount) { _, _ in
            guard let vaultURL else { return }
            refreshInboxBadge()
            if selectedTab == .browse {
                vaultController?.refreshRootForForegroundActivation()
            }
            let changedURL = fileWatcher.lastChangedFileURL
            Task.detached(priority: .utility) {
                if let changedURL {
                    try? await SearchIndexController.shared.refresh(vaultURL: vaultURL, fileURL: changedURL)
                } else {
                    await Self.refreshSearchIndex(vaultURL: vaultURL)
                }
            }
        }
        .onChange(of: selectedTab) { _, _ in refreshInboxBadge() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if hasStartedDeferredServices { refreshInboxBadge() }
        }
        .onReceive(NotificationCenter.default.publisher(for: SharedCaptureDrain.didFileNotification)) { _ in
            refreshInboxBadge()
        }
    }

    /// Files whatever the share extension staged in the App Group into
    /// `inbox/`, then indexes each note and tells Digest to reload. Cheap when
    /// nothing is staged (one directory listing), so it runs on every activation.
    private func drainSharedCaptures() async {
        await drainQueue.run { await drainSharedCapturesOnce() }
        // Only once no pass is left: a pass that did not file the requested
        // capture must not give up on it while another is still filing it.
        openRequestedSharedCaptureIfNeeded()
    }

    private func drainSharedCapturesOnce() async {
        await flushShareMediaJobs()
        guard let vaultURL, let drain = SharedCaptureDrain.appGroup(vaultURL: vaultURL) else { return }
        let outcome = await Task.detached(priority: .userInitiated) { drain.drain() }.value
        if !outcome.filed.isEmpty {
            logger.info("Drained \(outcome.filed.count) shared capture(s); \(outcome.failed.count) left staged")
            for entry in outcome.filed {
                sharedCaptureNotes[entry.capture.id] = entry.filed.fileURL
                await SearchIndexController.shared.scheduleRefreshFile(vaultURL: vaultURL, fileURL: entry.filed.fileURL)
            }
            NotificationCenter.default.post(name: SharedCaptureDrain.didFileNotification, object: nil)
        }
    }

    /// Re-sends X / Instagram media jobs the share extension could not deliver
    /// (offline, or the extension closed before the Worker answered).
    private func flushShareMediaJobs() async {
        guard let outbox = ShareMediaOutbox.appGroup(), !outbox.pending().isEmpty,
              let endpoint = ShareMediaEndpoint(infoDictionary: Bundle.main.infoDictionary) else { return }
        let sent = await ShareMediaDispatcher(outbox: outbox, endpoint: endpoint).flush()
        logger.info("Re-sent \(sent) share media job(s)")
    }

    /// The share extension asked for one capture's note. Open it if this
    /// session filed it; otherwise (filed by an earlier launch, or the staged
    /// file is gone) fall back to Digest, where every inbox capture lives.
    private func openRequestedSharedCaptureIfNeeded() {
        guard let id = launchRouter.requestedSharedCaptureID else { return }
        launchRouter.clearSharedCaptureRequest()
        if let noteURL = sharedCaptureNotes[id] {
            logger.info("Opening shared capture \(id.uuidString, privacy: .public) at \(noteURL.lastPathComponent, privacy: .public)")
            openFiledNote(noteURL)
        } else {
            logger.info("Shared capture \(id.uuidString, privacy: .public) not filed this session; showing Digest")
            tabSelection.wrappedValue = .digest
        }
    }

    /// A `noto2://note?path=` link (a "Save Quick Capture" notification): open that note, or
    /// Digest if it is gone. Waits for the vault; `.task(id: vaultURL)` calls this again then.
    private func openRequestedNoteIfNeeded() {
        guard let path = launchRouter.requestedNotePath, let vaultURL else { return }
        launchRouter.clearNoteRequest()
        let fileURL = vaultURL.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            logger.info("Opening note from link: \(path, privacy: .public)")
            openFiledNote(fileURL)
        } else {
            logger.info("Linked note missing: \(path, privacy: .public); showing Digest")
            tabSelection.wrappedValue = .digest
        }
    }

    /// Capture filed a note and the user tapped its status line. Browse owns the
    /// editor, and its workspace may not exist yet on a capture-first launch, so
    /// start it before handing the note over.
    private func openFiledNote(_ fileURL: URL) {
        startDeferredServicesIfNeeded()
        pendingNoteURL = fileURL
        selectedTab = .browse
    }

    private var tabSelection: Binding<Noto2Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .today, selectedTab == .today {
                    todayReselectRevision += 1
                }
                if Noto2StartupPolicy.requiresWorkspace(newTab) {
                    startDeferredServicesIfNeeded()
                }
                selectedTab = newTab
            }
        )
    }

    private func tabIcon(_ tab: Noto2Tab) -> some View {
        Image(systemName: tab.systemImage)
            .accessibilityLabel(tab.title)
            .accessibilityIdentifier("tab_\(tab.rawValue)")
    }

    private var deferredTabPlaceholder: some View {
        NotoTheme.background
            .ignoresSafeArea()
    }

    private func prepareWorkspaceIfNeeded() {
        guard vaultController == nil, let vaultURL else { return }
        // Search resolves notes by path and Browse loads its visible directory
        // on demand, so creating this controller must not enumerate the root.
        vaultController = VaultController(vaultURL: vaultURL, autoloadRoot: false)
    }

    private func startDeferredServicesIfNeeded() {
        guard let vaultURL else { return }
        prepareWorkspaceIfNeeded()
        guard !hasStartedDeferredServices else { return }
        hasStartedDeferredServices = true
        refreshInboxBadge()
        fileWatcher.watch(directory: vaultURL)
        SemanticSearch.configureAtStartup()
        startSearchMaintenance()
    }

    private func refreshInboxBadge() {
        Task { await inboxBadge.refresh(vaultURL: vaultURL) }
    }

    private func startSearchMaintenance() {
        guard let vaultURL else { return }
        Task.detached(priority: .utility) {
            await SearchIndexController.shared.drainPendingQueue(vaultURL: vaultURL)
            await Self.refreshSearchIndex(vaultURL: vaultURL)
        }
    }

    nonisolated private static func refreshSearchIndex(vaultURL: URL) async {
        do {
            let result = try await SearchIndexController.shared.refresh(vaultURL: vaultURL)
            // Noto 2 keeps its own index (separate app container), so a search
            // that "finds nothing" is usually an index that never filled —
            // typically because iCloud has evicted the note bodies. Log the
            // shape of every sweep so that is visible without a debugger.
            logger.info(
                "Search index sweep: scanned=\(result.scanned) upserted=\(result.upserted) deleted=\(result.deleted) skippedUnavailable=\(result.skippedUnavailable) indexedNotes=\(result.stats.noteCount) sections=\(result.stats.sectionCount)"
            )
        } catch {
            logger.error("Search index refresh failed: \(error.localizedDescription)")
        }
    }
}
