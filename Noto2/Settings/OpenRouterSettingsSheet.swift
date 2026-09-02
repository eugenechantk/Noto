import SwiftUI

/// The only settings Noto 2 has: the OpenRouter key (for summaries), an
/// optional base-URL override, and the vault location. A sheet, not a screen.
struct OpenRouterSettingsSheet: View {
    var locationManager: VaultLocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = OpenRouterKeyStore.load() ?? ""
    @State private var baseURL: String = OpenRouterBaseURLStore.load() ?? ""
    @State private var confirmVaultReset = false
    @State private var savedFlash = false

    private var hasBundledKey: Bool { OpenRouterKeyStore.bundledKey()?.isEmpty == false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-or-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("openRouterKeyField")
                    HStack {
                        Button("Save key") { saveKey() }
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("openRouterSaveKeyButton")
                        Spacer()
                        if OpenRouterKeyStore.hasKey {
                            Button("Remove", role: .destructive) {
                                OpenRouterKeyStore.delete()
                                apiKey = ""
                            }
                            .accessibilityIdentifier("openRouterRemoveKeyButton")
                        }
                    }
                } header: {
                    Text("OpenRouter API key")
                } footer: {
                    if OpenRouterKeyStore.hasKey {
                        Text("Saved in the Keychain. Used only for search summaries.")
                    } else if hasBundledKey {
                        Text("Using the key bundled with this build. Paste your own to override it.")
                    } else {
                        Text("Summaries need an OpenRouter key. Get one at openrouter.ai/keys.")
                    }
                }

                Section {
                    TextField(OpenRouterBaseURLStore.defaultBaseURL.absoluteString, text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("openRouterBaseURLField")
                    Button("Save base URL") {
                        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty { OpenRouterBaseURLStore.clear() } else { OpenRouterBaseURLStore.save(trimmed) }
                        flashSaved()
                    }
                    .accessibilityIdentifier("openRouterSaveBaseURLButton")
                } header: {
                    Text("Base URL override")
                } footer: {
                    Text("Leave empty for openrouter.ai. Model: \(SummaryPromptBuilder.model).")
                }

                Section {
                    if let vaultURL = locationManager.vaultURL {
                        Text(vaultURL.lastPathComponent)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(vaultURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Button("Choose a different vault…", role: .destructive) {
                        confirmVaultReset = true
                    }
                    .accessibilityIdentifier("settingsChangeVaultButton")
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Noto 2 keeps its own index of this folder; changing the vault rebuilds it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(NotoTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDoneButton")
                }
            }
            .overlay(alignment: .bottom) {
                if savedFlash {
                    Text("Saved")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .confirmationDialog("Choose a different vault?", isPresented: $confirmVaultReset, titleVisibility: .visible) {
                Button("Choose new vault", role: .destructive) {
                    dismiss()
                    locationManager.resetVault()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your notes stay where they are; only Noto 2's bookmark and index are reset.")
            }
        }
        .presentationDetents([.large])
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        OpenRouterKeyStore.save(trimmed)
        flashSaved()
    }

    private func flashSaved() {
        withAnimation { savedFlash = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { savedFlash = false }
        }
    }
}
