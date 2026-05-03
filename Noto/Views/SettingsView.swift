import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "SettingsView")

struct SettingsView: View {
    var locationManager: VaultLocationManager
    @ObservedObject var readwiseSyncController: ReadwiseSyncController
    @State private var showResetConfirmation = false
    @State private var isTokenSheetPresented = false
    @State private var isRebuildingIndex = false
    @State private var indexRebuildMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault Location")
                            .font(.body)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(displayPath)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
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

            Section {
                Button {
                    rebuildSearchIndex()
                } label: {
                    HStack {
                        Label("Refresh search index", systemImage: "magnifyingglass.circle")
                        if isRebuildingIndex {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRebuildingIndex || locationManager.vaultURL == nil)
                .accessibilityIdentifier("refresh_search_index_button")
            } header: {
                Text("Search")
            } footer: {
                if let indexRebuildMessage {
                    Text(indexRebuildMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("Deletes the local search database and re-indexes every note in the vault. Use this if mention or search results look stale.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Section {
                Button("Set Token") {
                    isTokenSheetPresented = true
                }
                .accessibilityIdentifier("readwise_set_token_button")

                Button("Test Connection") {
                    readwiseSyncController.testConnection()
                }
                .disabled(!readwiseSyncController.canRunActions || readwiseSyncController.isSyncing)
                .accessibilityIdentifier("readwise_test_connection_button")

                Button("Sync Now") {
                    readwiseSyncController.syncNow(vaultURL: locationManager.vaultURL)
                }
                .disabled(!readwiseSyncController.canRunActions || readwiseSyncController.isSyncing || locationManager.vaultURL == nil)
                .accessibilityIdentifier("readwise_sync_now_button")
            } header: {
                Text("Readwise Sync")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(readwiseSyncController.tokenStatusMessage)
                    Text(readwiseSyncController.syncStatusMessage)
                    if let formattedLastSyncedAt = readwiseSyncController.formattedLastSyncedAt {
                        Text("Last synced: \(formattedLastSyncedAt)")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .accessibilityIdentifier("readwise_status_caption_group")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityIdentifier("back_button")
            }
        }
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
        .sheet(isPresented: $isTokenSheetPresented) {
            ReadwiseTokenSheet(
                token: $readwiseSyncController.tokenInput,
                save: {
                    if readwiseSyncController.saveToken() {
                        isTokenSheetPresented = false
                    }
                },
                cancel: {
                    readwiseSyncController.tokenInput = ""
                    isTokenSheetPresented = false
                }
            )
        }
    }

    private func rebuildSearchIndex() {
        guard let vaultURL = locationManager.vaultURL, !isRebuildingIndex else { return }
        isRebuildingIndex = true
        indexRebuildMessage = "Rebuilding search index…"
        Task {
            do {
                let result = try await SearchIndexController.shared.rebuildIndex(vaultURL: vaultURL)
                await MainActor.run {
                    isRebuildingIndex = false
                    indexRebuildMessage = "Indexed \(result.upserted) notes."
                }
            } catch {
                logger.error("Search index rebuild failed: \(error.localizedDescription)")
                await MainActor.run {
                    isRebuildingIndex = false
                    indexRebuildMessage = "Rebuild failed — check Console for details."
                }
            }
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

private struct ReadwiseTokenSheet: View {
    @Binding var token: String
    let save: () -> Void
    let cancel: () -> Void

    private var canSave: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    #if os(iOS)
                    SecureField("Readwise access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("readwise_token_field")
                    #else
                    SecureField("Readwise access token", text: $token)
                        .accessibilityIdentifier("readwise_token_field")
                    #endif
                }
            }
            .navigationTitle("Set Readwise Token")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .accessibilityIdentifier("readwise_token_cancel_button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("readwise_token_save_button")
                }
            }
        }
    }
}
