import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")


#if os(macOS)
/// Hides the app instead of closing the window when the user clicks the red X.
/// Clicking the dock icon unhides it — window size and position are preserved automatically.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set ourselves as delegate on all windows so we intercept close
        for window in NSApp.windows {
            window.delegate = self
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure any new windows also get our delegate
        for window in NSApp.windows where window.delegate == nil {
            window.delegate = self
        }
        // If no windows are visible (user closed via red X then clicked dock), show them
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}
#endif

@main
struct NotoApp: App {
    @State private var locationManager = VaultLocationManager()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

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
        WindowGroup(id: "main") {
            if Self.isRunningTests {
                Color.clear
            } else if locationManager.isVaultConfigured, let vaultURL = locationManager.vaultURL {
                MainAppView(vaultURL: vaultURL, locationManager: locationManager)
            } else {
                VaultSetupView(locationManager: locationManager)
            }
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        #endif
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
