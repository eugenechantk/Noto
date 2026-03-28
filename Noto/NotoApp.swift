import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

@main
struct NotoApp: App {
    @State private var locationManager = VaultLocationManager()

    init() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "unknown"
            let stack = exception.callStackSymbols.prefix(10).joined(separator: "\n")
            logger.error("[CRASH] \(exception.name.rawValue): \(reason)\n\(stack)")
        }
    }

    /// True when the process is a unit test runner (not the app itself).
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                Color.clear
            } else if locationManager.isVaultConfigured, let vaultURL = locationManager.vaultURL {
                MainAppView(vaultURL: vaultURL, locationManager: locationManager)
            } else {
                VaultSetupView(locationManager: locationManager)
            }
        }
    }
}

/// Wrapper that owns the MarkdownNoteStore for a given vault URL.
struct MainAppView: View {
    let vaultURL: URL
    var locationManager: VaultLocationManager
    @State private var store: MarkdownNoteStore
    @State private var fileWatcher = VaultFileWatcher()
    @Environment(\.scenePhase) private var scenePhase

    init(vaultURL: URL, locationManager: VaultLocationManager) {
        self.vaultURL = vaultURL
        self.locationManager = locationManager
        _store = State(wrappedValue: MarkdownNoteStore(vaultURL: vaultURL))
    }

    var body: some View {
        NoteListView(store: store, locationManager: locationManager, fileWatcher: fileWatcher)
            .onAppear {
                fileWatcher.watch(directory: vaultURL)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    _ = store.todayNote()
                    store.loadItems()
                }
            }
            .onChange(of: fileWatcher.changeCount) { _, _ in
                store.loadItems()
            }
    }
}
