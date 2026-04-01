import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "VaultSetupView")

/// First-launch screen where the user picks where to store their notes.
struct VaultSetupView: View {
    var locationManager: VaultLocationManager
    @State private var showCreatePicker = false
    @State private var showOpenPicker = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Welcome to Noto")
                    .font(.largeTitle.bold())
                Text("Your notes, your files, your folders.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                // Create New Vault
                Button(action: createNewVault) {
                    HStack {
                        Image(systemName: "plus.rectangle.on.folder.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create New Vault")
                                .font(.headline)
                            Text("Pick a location — a Noto folder will be created")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.quaternary)
                    .cornerRadius(12)
                }
                .accessibilityIdentifier("create_vault_button")

                // Open Existing Vault
                Button(action: openExistingVault) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Existing Vault")
                                .font(.headline)
                            Text("Choose a folder that already has markdown files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.quaternary)
                    .cornerRadius(12)
                }
                .accessibilityIdentifier("open_vault_button")
            }
            .padding(.horizontal)

            Spacer()
        }
        #if os(iOS)
        .sheet(isPresented: $showCreatePicker) {
            FolderPickerView { url in
                if let url {
                    locationManager.setVault(toParent: url)
                }
            }
        }
        .sheet(isPresented: $showOpenPicker) {
            FolderPickerView { url in
                if let url {
                    locationManager.setVault(directURL: url)
                }
            }
        }
        #endif
    }

    private func createNewVault() {
        #if os(iOS)
        showCreatePicker = true
        #elseif os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick a location. A Noto folder will be created inside."
        panel.prompt = "Create Here"

        if panel.runModal() == .OK, let url = panel.url {
            locationManager.setVault(toParent: url)
        }
        #endif
    }

    private func openExistingVault() {
        #if os(iOS)
        showOpenPicker = true
        #elseif os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder that contains your markdown notes."
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            locationManager.setVault(directURL: url)
        }
        #endif
    }
}

// MARK: - iOS Folder Picker

#if os(iOS)
import UIKit

/// UIDocumentPickerViewController wrapper for selecting a folder.
struct FolderPickerView: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
#endif
