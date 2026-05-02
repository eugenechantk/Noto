import SwiftUI
import os.log
import NotoSearch
import NotoVault

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

enum NotoAppCommands {
    static let openToday = Notification.Name("NotoAppCommands.openToday")
    static let openSettings = Notification.Name("NotoAppCommands.openSettings")
    static let toggleSidebar = Notification.Name("NotoAppCommands.toggleSidebar")
    static let showSearch = Notification.Name("NotoAppCommands.showSearch")
    static let createNote = Notification.Name("NotoAppCommands.createNote")
}

#if os(macOS)
enum NotoCommandTarget {
    static var activeWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    static func matches(_ notification: Notification, window: NSWindow?) -> Bool {
        if let targetWindow = notification.object as? NSWindow {
            return targetWindow === window
        }

        guard let window else { return false }
        return window.isKeyWindow || window.isMainWindow
    }
}
#endif

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct DefaultWindowHeightReader: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowHeightReaderView {
        let view = WindowHeightReaderView()
        view.onWindowChange = { window in
            context.coordinator.configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowHeightReaderView, context: Context) {
        nsView.onWindowChange = { window in
            context.coordinator.configure(window)
        }
        context.coordinator.configure(nsView.window)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?

        func configure(_ window: NSWindow?) {
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window

            DispatchQueue.main.async {
                Self.expandToVisibleScreenHeight(window)
            }
        }

        private static func expandToVisibleScreenHeight(_ window: NSWindow) {
            let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            guard let visibleFrame, visibleFrame.height > 0 else { return }

            let currentFrame = window.frame
            let fullHeightFrame = NSRect(
                x: currentFrame.origin.x,
                y: visibleFrame.minY,
                width: currentFrame.width,
                height: visibleFrame.height
            )

            window.setFrame(fullHeightFrame, display: true)
        }
    }
}

private final class WindowHeightReaderView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
#endif

private struct NotoCommands: Commands {
    var body: some Commands {
        CommandMenu("Noto") {
            #if os(macOS)
            Button("New Note") {
                NotificationCenter.default.post(name: NotoAppCommands.createNote, object: NotoCommandTarget.activeWindow)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            #endif

            Button("Today") {
                #if os(macOS)
                NotificationCenter.default.post(name: NotoAppCommands.openToday, object: NotoCommandTarget.activeWindow)
                #else
                NotificationCenter.default.post(name: NotoAppCommands.openToday, object: nil)
                #endif
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("Search in Note") {
                NoteEditorCommands.requestShowFind()
            }
            .keyboardShortcut("f", modifiers: [.command])

            #if os(macOS)
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: NotoAppCommands.toggleSidebar, object: NotoCommandTarget.activeWindow)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button("Search") {
                NotificationCenter.default.post(name: NotoAppCommands.showSearch, object: NotoCommandTarget.activeWindow)
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

            Button("Strikethrough") {
                NoteEditorCommands.requestToggleStrikethrough()
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])

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
}

@main
struct NotoApp: App {
    @State private var locationManager = VaultLocationManager()
    @State private var readwiseSyncController = ReadwiseSyncController()
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
        #if os(macOS)
        WindowGroup(id: "main", for: String.self) { initialDocumentLink in
            appContent(initialDocumentLink: initialDocumentLink.wrappedValue)
        }
        .commands {
            NotoCommands()
        }
        .defaultSize(width: 800, height: 600)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView(locationManager: locationManager, readwiseSyncController: readwiseSyncController)
                .frame(minWidth: 400, minHeight: 200)
                .environment(\.colorScheme, .dark)
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.primaryText)
        }
        #else
        WindowGroup(id: "main") {
            appContent(initialDocumentLink: nil)
        }
        .commands {
            NotoCommands()
        }
        #endif
    }

    @ViewBuilder
    private func appContent(initialDocumentLink: String?) -> some View {
        Group {
            if Self.isRunningTests {
                Color.clear
            } else if locationManager.isVaultConfigured, let vaultURL = locationManager.vaultURL {
                MainAppView(
                    vaultURL: vaultURL,
                    locationManager: locationManager,
                    readwiseSyncController: readwiseSyncController,
                    initialDocumentLink: initialDocumentLink
                )
                #if os(macOS)
                .background(DefaultWindowHeightReader().frame(width: 0, height: 0))
                #endif
            } else {
                VaultSetupView(locationManager: locationManager)
                    #if os(macOS)
                .background(DefaultWindowHeightReader().frame(width: 0, height: 0))
                #endif
            }
        }
        .environment(\.colorScheme, .dark)
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

@MainActor
final class DailyNotePrewarmer {
    private let calendar: Calendar
    private var prewarmTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var lastPrewarmedStartOfDay: Date?

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    deinit {
        prewarmTask?.cancel()
        midnightTask?.cancel()
    }

    func start(vaultURL: URL) {
        prewarmToday(vaultURL: vaultURL)
        scheduleNextMidnightPrewarm(vaultURL: vaultURL)
    }

    func stop() {
        prewarmTask?.cancel()
        midnightTask?.cancel()
        prewarmTask = nil
        midnightTask = nil
    }

    private func prewarmToday(vaultURL: URL) {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        guard lastPrewarmedStartOfDay != startOfDay else { return }
        lastPrewarmedStartOfDay = startOfDay

        prewarmTask?.cancel()
        let calendar = calendar
        prewarmTask = Task.detached(priority: .utility) {
            let resolved = DailyNoteFile.ensure(vaultRootURL: vaultURL, date: now, calendar: calendar)
            if resolved.didCreate {
                do {
                    _ = try await SearchIndexController.shared.refreshFile(
                        vaultURL: vaultURL,
                        fileURL: resolved.fileURL
                    )
                } catch {
                    DebugTrace.record("daily note prewarm search refresh failed file=\(resolved.fileURL.lastPathComponent) error=\(String(describing: error))")
                }
            } else if resolved.didApplyTemplate {
                await SearchIndexController.shared.scheduleRefreshFile(
                    vaultURL: vaultURL,
                    fileURL: resolved.fileURL
                )
            }
        }
    }

    private func scheduleNextMidnightPrewarm(vaultURL: URL) {
        midnightTask?.cancel()
        let now = Date()
        guard let nextStartOfDay = DailyNoteFile.nextStartOfDay(after: now, calendar: calendar) else { return }
        let delay = max(0, nextStartOfDay.timeIntervalSince(now) + 1)
        let nanoseconds = UInt64(delay * 1_000_000_000)

        midnightTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.prewarmToday(vaultURL: vaultURL)
                self.scheduleNextMidnightPrewarm(vaultURL: vaultURL)
            }
        }
    }
}

/// Wrapper that owns the MarkdownNoteStore for a given vault URL.
struct MainAppView: View {
    let vaultURL: URL
    var locationManager: VaultLocationManager
    @ObservedObject var readwiseSyncController: ReadwiseSyncController
    var initialDocumentLink: String?
    @State private var store: MarkdownNoteStore
    @State private var fileWatcher = VaultFileWatcher()
    @State private var dailyNotePrewarmer = DailyNotePrewarmer()
    @Environment(\.scenePhase) private var scenePhase

    init(
        vaultURL: URL,
        locationManager: VaultLocationManager,
        readwiseSyncController: ReadwiseSyncController,
        initialDocumentLink: String? = nil
    ) {
        self.vaultURL = vaultURL
        self.locationManager = locationManager
        self.readwiseSyncController = readwiseSyncController
        self.initialDocumentLink = initialDocumentLink
        _store = State(wrappedValue: MarkdownNoteStore(
            vaultURL: vaultURL,
            autoload: false,
            directoryLoader: VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)
        ))
    }

    var body: some View {
        VaultWorkspaceView(
            store: store,
            locationManager: locationManager,
            fileWatcher: fileWatcher,
            readwiseSyncController: readwiseSyncController,
            initialDocumentLink: initialDocumentLink
        )
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.primaryText)
            .task {
                store.loadItemsInBackground()
                dailyNotePrewarmer.start(vaultURL: vaultURL)
                readwiseSyncController.refreshSavedTokenState()
                readwiseSyncController.startAutomaticSync(vaultURL: vaultURL)
                await refreshSearchIndex()
            }
            .onAppear {
                fileWatcher.watch(directory: vaultURL)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.refreshForForegroundActivation()
                    dailyNotePrewarmer.start(vaultURL: vaultURL)
                    readwiseSyncController.startAutomaticSync(vaultURL: vaultURL)
                    Task {
                        await refreshSearchIndex()
                    }
                } else if newPhase == .background {
                    dailyNotePrewarmer.stop()
                }
            }
            .onChange(of: fileWatcher.changeCount) { _, _ in
                store.loadItemsInBackground()
                Task {
                    await refreshSearchIndex()
                }
            }
    }

    private func refreshSearchIndex() async {
        do {
            _ = try await SearchIndexController.shared.refresh(vaultURL: vaultURL)
        } catch {
            logger.error("Search index refresh failed: \(error.localizedDescription)")
        }
    }
}
