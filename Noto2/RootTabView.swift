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
    @State private var hasStartedDeferredServices = false
    /// A note another tab asked Browse to open (a just-filed capture).
    @State private var pendingNoteURL: URL?
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
           let tab = Noto2Tab(rawValue: raw) {
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
        TabView(selection: tabSelection) {
            Tab("Capture", systemImage: "square.and.pencil", value: Noto2Tab.capture) {
                CaptureScreen(vaultURL: vaultURL, onOpenFiledNote: openFiledNote)
            }
            Tab("Digest", systemImage: "tray.full", value: Noto2Tab.digest) {
                if let vaultController {
                    DigestScreen(vaultController: vaultController)
                } else {
                    deferredTabPlaceholder
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: Noto2Tab.search) {
                if let vaultController {
                    SearchScreen(vaultController: vaultController, locationManager: locationManager)
                } else {
                    deferredTabPlaceholder
                }
            }
            Tab("Browse", systemImage: "folder", value: Noto2Tab.browse) {
                if let vaultController {
                    BrowseScreen(
                        vaultController: vaultController,
                        locationManager: locationManager,
                        pendingNoteURL: $pendingNoteURL
                    )
                } else {
                    deferredTabPlaceholder
                }
            }
        }
        .tint(AppTheme.primaryText)
        .background(NotoTheme.background.ignoresSafeArea())
        .task(id: vaultURL) {
            guard vaultURL != nil else { return }
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
            guard phase == .active, hasStartedDeferredServices else { return }
            if selectedTab == .browse {
                vaultController?.refreshRootForForegroundActivation()
            }
            startSearchMaintenance()
        }
        .onChange(of: launchRouter.requestRevision) { _, _ in
            guard let requestedTab = launchRouter.requestedTab else { return }
            tabSelection.wrappedValue = requestedTab
        }
        .onChange(of: fileWatcher.changeCount) { _, _ in
            guard let vaultURL else { return }
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
                if Noto2StartupPolicy.requiresWorkspace(newTab) {
                    startDeferredServicesIfNeeded()
                }
                selectedTab = newTab
            }
        )
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
        fileWatcher.watch(directory: vaultURL)
        SemanticSearch.configureAtStartup()
        startSearchMaintenance()
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
