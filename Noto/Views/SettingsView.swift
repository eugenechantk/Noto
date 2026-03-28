import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "SettingsView")

struct SettingsView: View {
    @ObservedObject var locationManager: VaultLocationManager
    @State private var showFolderPicker = false
    @State private var isMoving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button(action: { showFolderPicker = true }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vault Location")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(displayPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if isMoving {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isMoving)
            } header: {
                Text("Storage")
            } footer: {
                Text("Choose a new location to move your entire Noto folder. iCloud Drive is recommended for persistence across app reinstalls.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView { url in
                if let url {
                    moveVault(to: url)
                }
            }
        }
    }

    private var displayPath: String {
        guard let url = locationManager.vaultURL else { return "Not set" }
        let path = url.path
        // Simplify iCloud paths
        if path.contains("Mobile Documents") {
            if path.contains("com~apple~CloudDocs") {
                let components = path.components(separatedBy: "com~apple~CloudDocs/")
                if let last = components.last {
                    return "iCloud Drive/\(last)"
                }
            }
            return "iCloud Drive"
        }
        // Local sandbox
        if path.contains("/Documents/Noto") {
            return "On This Device"
        }
        return url.lastPathComponent
    }

    private func moveVault(to newParentURL: URL) {
        guard let currentVaultURL = locationManager.vaultURL else { return }
        let newVaultURL = newParentURL.appendingPathComponent("Noto")

        // Don't move to the same location
        if currentVaultURL.standardizedFileURL == newVaultURL.standardizedFileURL {
            logger.info("Same location selected, skipping move")
            return
        }

        isMoving = true

        DispatchQueue.global(qos: .userInitiated).async {
            _ = newParentURL.startAccessingSecurityScopedResource()
            let fm = FileManager.default

            do {
                // If destination Noto folder already exists, merge by copying contents
                if fm.fileExists(atPath: newVaultURL.path) {
                    // Copy each item from current vault to new vault
                    let items = try fm.contentsOfDirectory(at: currentVaultURL, includingPropertiesForKeys: nil)
                    for item in items {
                        let dest = newVaultURL.appendingPathComponent(item.lastPathComponent)
                        if !fm.fileExists(atPath: dest.path) {
                            try fm.copyItem(at: item, to: dest)
                        }
                    }
                } else {
                    try fm.copyItem(at: currentVaultURL, to: newVaultURL)
                }

                // Remove old vault
                try fm.removeItem(at: currentVaultURL)

                logger.info("Moved vault from \(currentVaultURL.path) to \(newVaultURL.path)")

                DispatchQueue.main.async {
                    locationManager.setVault(toParent: newParentURL)
                    isMoving = false
                }
            } catch {
                logger.error("Failed to move vault: \(error)")
                DispatchQueue.main.async {
                    isMoving = false
                }
            }
        }
    }
}
