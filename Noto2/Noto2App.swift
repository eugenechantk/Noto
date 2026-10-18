import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "Noto2App")

/// Noto 2 — a deliberately small, separate app over the same vault:
/// Capture (editor + send), Search (hybrid hits + streamed summary), Browse.
/// It shares Noto's editor, storage, and search layers via `NotoShared/`.
@main
struct Noto2App: App {
    @State private var locationManager = VaultLocationManager(resolveExternalVaultOnInit: false)
    @State private var launchRouter = Noto2LaunchRouter.shared

    init() {
        // Before launch finishes, so a notification tap that launches the app is delivered.
        UNUserNotificationCenter.current().delegate = Noto2NotificationDelegate.shared
        DebugTrace.reset()
        DebugTrace.record("noto2 init bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "unknown"
            logger.error("[CRASH] \(exception.name.rawValue): \(reason)")
        }
    }

    /// True when the process is a unit test runner (not the app itself).
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if Self.isRunningTests {
                    Color.clear
                } else if Noto2StartupPolicy.canPresentCapture(
                    isConfigured: locationManager.isVaultConfigured,
                    hasDeferredResolution: locationManager.hasDeferredExternalVaultResolution
                ) {
                    RootTabView(
                        vaultURL: locationManager.vaultURL,
                        locationManager: locationManager,
                        launchRouter: launchRouter
                    )
                        .task {
                            await locationManager.resolveDeferredExternalVault()
                        }
                } else {
                    VaultSetupView(locationManager: locationManager)
                }
            }
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                _ = launchRouter.handle(url, stageText: CaptureTextStager.stageInAppGroup)
            }
            // "Save Quick Capture" can confirm with a notification ("Notify When Done"). Ask once,
            // here — a background Shortcut can't show the permission prompt.
            .task {
                guard !Self.isRunningTests else { return }
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
        }
    }
}
