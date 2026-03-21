import SwiftUI
import os.log
import NotoVault

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

@MainActor
private let sharedVaultManager: VaultManager = {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let vaultURL = documentsURL.appendingPathComponent("Noto")
    let manager = VaultManager(rootURL: vaultURL)
    do {
        try manager.ensureVaultExists()
    } catch {
        logger.error("Failed to create vault directory: \(error)")
    }
    return manager
}()

@main
struct NotoApp: App {
    var body: some Scene {
        WindowGroup {
            VaultNotesListView(vault: sharedVaultManager)
        }
    }
}
