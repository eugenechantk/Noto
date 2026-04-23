import SwiftUI
import os.log

#if os(iOS)
import UIKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

enum NotoAppCommands {
    static let openToday = Notification.Name("NotoAppCommands.openToday")
    static let openSettings = Notification.Name("NotoAppCommands.openSettings")
    static let toggleSidebar = Notification.Name("NotoAppCommands.toggleSidebar")
    static let showSearch = Notification.Name("NotoAppCommands.showSearch")
}

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
        DebugTrace.reset()
        DebugTrace.record("app init bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        #if os(iOS)
        Self.configureNavigationBarAppearance()
        #endif
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
        .environment(\.colorScheme, .dark)
        .commands {
            CommandMenu("Noto") {
                Button("Today") {
                    NotificationCenter.default.post(name: NotoAppCommands.openToday, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])

                #if os(macOS)
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: NotoAppCommands.toggleSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Search") {
                    NotificationCenter.default.post(name: NotoAppCommands.showSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Bold") {
                    NoteEditorCommands.requestToggleBold()
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button("Italic") {
                    NoteEditorCommands.requestToggleItalic()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Link") {
                    NoteEditorCommands.requestToggleHyperlink()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                #endif

                #if os(iOS)
                Button("Settings") {
                    NotificationCenter.default.post(name: NotoAppCommands.openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
                #endif
            }
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(locationManager: locationManager)
                .frame(minWidth: 400, minHeight: 200)
                .environment(\.colorScheme, .dark)
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.primaryText)
        }
        #endif
    }

    #if os(iOS)
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: AppTheme.uiPrimaryText]
        appearance.largeTitleTextAttributes = [.foregroundColor: AppTheme.uiPrimaryText]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    #endif
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
        _store = State(wrappedValue: MarkdownNoteStore(vaultURL: vaultURL, autoload: false))
    }

    var body: some View {
        NoteListView(store: store, locationManager: locationManager, fileWatcher: fileWatcher)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.primaryText)
            .task {
                store.loadItemsInBackground()
            }
            .onAppear {
                fileWatcher.watch(directory: vaultURL)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.refreshForForegroundActivation()
                }
            }
            .onChange(of: fileWatcher.changeCount) { _, _ in
                store.loadItemsInBackground()
            }
    }
}
