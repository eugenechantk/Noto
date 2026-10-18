import SwiftUI

/// Compatibility entry point for presentations outside Library.
struct OpenRouterSettingsSheet: View {
    var locationManager: VaultLocationManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LibrarySettingsScreen(locationManager: locationManager)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton")
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// Library pushes Settings, keeping the native back path and glass toolbar.
struct LibrarySettingsScreen: View {
    var locationManager: VaultLocationManager
    @ObservedObject private var indexStatus = SearchIndexStatusModel.shared
    @State private var confirmVaultReset = false
    @State private var confirmRebuild = false
    @State private var rebuilding = false
    @State private var errorMessage: String?

    private var isCloudVault: Bool { locationManager.vaultURL?.path.contains("Mobile Documents") == true }
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
    private var indexSummary: String {
        guard let count = indexStatus.keywordNotes else { return "Indexing…" }
        return "\(count.formatted()) notes · \(indexStatus.isKeywordPartial ? "indexing" : "up to date")"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotoTheme.ink)
                        .frame(width: 34, height: 34)
                        .background(NotoTheme.secondaryFill, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(locationManager.vaultURL?.lastPathComponent ?? "No vault").font(.body.weight(.semibold)).foregroundStyle(NotoTheme.ink)
                        Text(isCloudVault ? "iCloud Drive › \(locationManager.vaultURL?.lastPathComponent ?? "")" : "On this device")
                            .font(.caption).foregroundStyle(NotoTheme.muted)
                    }
                    Spacer()
                }
                Button("Choose a different vault") { confirmVaultReset = true }
                    .foregroundStyle(NotoTheme.accentText).accessibilityIdentifier("settingsChangeVaultButton")
            } header: { LibrarySectionHeading("Vault") } footer: {
                Text("Changing the vault rebuilds Noto 2's index. Your notes stay where they are.")
            }.listRowBackground(NotoTheme.card)
            Section {
                HStack {
                    Text("Index").foregroundStyle(NotoTheme.ink)
                    Spacer()
                    Text(indexSummary).font(.caption).foregroundStyle(NotoTheme.muted)
                }.accessibilityIdentifier("settingsIndexStatus")
                Button { confirmRebuild = true } label: {
                    HStack(spacing: 10) {
                        if rebuilding { ProgressView() } else { Image(systemName: "arrow.clockwise").foregroundStyle(NotoTheme.muted) }
                        Text(rebuilding ? "Rebuilding index…" : "Rebuild index").foregroundStyle(NotoTheme.ink)
                    }
                }.disabled(rebuilding).accessibilityIdentifier("settingsRebuildIndex")
            } header: { LibrarySectionHeading("Search") }
            .listRowBackground(NotoTheme.card)
            Section {
                HStack {
                    Text("Version").foregroundStyle(NotoTheme.ink)
                    Spacer()
                    Text(version).font(.caption).foregroundStyle(NotoTheme.muted)
                }
            } header: { LibrarySectionHeading("About") }
            .listRowBackground(NotoTheme.card)
        }
        .modifier(LibraryListStyle())
        .navigationTitle("Settings").toolbarTitleDisplayMode(.inlineLarge)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("librarySettings")
        .task {
            if let root = locationManager.vaultURL { indexStatus.start(vaultURL: root) }
        }
        .onDisappear { indexStatus.stop() }
        .confirmationDialog("Choose a different vault?", isPresented: $confirmVaultReset, titleVisibility: .visible) {
            Button("Choose new vault", role: .destructive) { locationManager.resetVault() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your notes stay where they are. Noto 2 asks you to choose the next vault.") }
        .confirmationDialog("Rebuild the search index?", isPresented: $confirmRebuild, titleVisibility: .visible) {
            Button("Rebuild index") { rebuild() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your notes are unchanged. Search may be incomplete while the index rebuilds.") }
        .alert("Could not rebuild index", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func rebuild() {
        guard let root = locationManager.vaultURL else { return }
        rebuilding = true
        Task {
            do { _ = try await SearchIndexController.shared.rebuildIndex(vaultURL: root) }
            catch { errorMessage = error.localizedDescription }
            rebuilding = false
        }
    }
}
