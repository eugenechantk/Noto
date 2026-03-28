import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "VaultSetupView")

/// First-launch screen where the user picks where to store their notes.
struct VaultSetupView: View {
    var locationManager: VaultLocationManager
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Welcome to Noto")
                    .font(.largeTitle.bold())
                Text("Choose where to store your notes")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 16) {
                    Button(action: { showFolderPicker = true }) {
                        HStack {
                            Image(systemName: "icloud.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Choose Location")
                                    .font(.headline)
                                Text("A Noto folder will be created here")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    .accessibilityIdentifier("choose_location_button")

                    Button(action: { locationManager.setLocalVault() }) {
                        HStack {
                            Image(systemName: "iphone")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("On This Device")
                                    .font(.headline)
                                Text("Notes are deleted if the app is removed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    .accessibilityIdentifier("local_vault_button")
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView { url in
                if let url {
                    locationManager.setVault(toParent: url)
                }
            }
        }
    }
}

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
