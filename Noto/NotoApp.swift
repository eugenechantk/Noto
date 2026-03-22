import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

@main
struct NotoApp: App {
    @StateObject private var locationManager = VaultLocationManager()

    var body: some Scene {
        WindowGroup {
            if locationManager.isVaultConfigured, let vaultURL = locationManager.vaultURL {
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
    let locationManager: VaultLocationManager
    @StateObject private var store: MarkdownNoteStore
    @Environment(\.scenePhase) private var scenePhase

    init(vaultURL: URL, locationManager: VaultLocationManager) {
        self.vaultURL = vaultURL
        self.locationManager = locationManager
        _store = StateObject(wrappedValue: MarkdownNoteStore(vaultURL: vaultURL))
    }

    var body: some View {
        NoteListView(store: store, locationManager: locationManager)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    _ = store.todayNote()
                    store.loadItems()
                }
            }
    }
}
