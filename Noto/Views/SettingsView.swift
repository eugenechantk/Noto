import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "SettingsView")

struct SettingsView: View {
    var locationManager: VaultLocationManager
    @State private var showResetConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault Location")
                            .font(.body)
                        Text(displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                Button(role: .destructive, action: { showResetConfirmation = true }) {
                    Label("Change Vault", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Changing your vault returns you to the welcome screen where you can create or open a different vault.")
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #elseif os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
        .alert("Change Vault?", isPresented: $showResetConfirmation) {
            Button("Change Vault", role: .destructive) {
                locationManager.resetVault()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This won't delete any files. You'll be returned to the welcome screen to choose a new vault.")
        }
    }

    private var displayPath: String {
        guard let url = locationManager.vaultURL else { return "Not set" }
        let path = url.path
        if path.contains("Mobile Documents") {
            if path.contains("com~apple~CloudDocs") {
                let components = path.components(separatedBy: "com~apple~CloudDocs/")
                if let last = components.last {
                    return "iCloud Drive/\(last)"
                }
            }
            return "iCloud Drive"
        }
        if path.contains("/Documents/Noto") {
            return "On This Device"
        }
        return url.lastPathComponent
    }
}
