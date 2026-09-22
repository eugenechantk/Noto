import NotoVault
import SwiftUI

private struct MoveNoteDestination: Identifiable, Equatable {
    let url: URL
    let name: String
    let depth: Int

    var id: String {
        url.standardizedFileURL.path
    }
}

struct MoveNoteDestinationPicker: View {
    let vaultRootURL: URL
    let currentDirectoryURL: URL
    let directoryLoader: VaultDirectoryLoader
    var onCancel: () -> Void
    var onMove: (URL) -> Void

    @State private var destinations: [MoveNoteDestination] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    onMove(destination.url)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: destination.url.standardizedFileURL == vaultRootURL.standardizedFileURL ? "tray.full" : "folder")
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name)
                                .foregroundStyle(AppTheme.primaryText)
                            if destination.url.standardizedFileURL == currentDirectoryURL.standardizedFileURL {
                                Text("Current location")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(destination.depth) * 16)
                    .contentShape(Rectangle())
                }
                .disabled(destination.url.standardizedFileURL == currentDirectoryURL.standardizedFileURL)
                .accessibilityIdentifier("move_destination_\(destination.name)")
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if destinations.isEmpty {
                    ContentUnavailableView("No folders", systemImage: "folder")
                }
            }
            .navigationTitle("Move Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("move_note_cancel_button")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
        .task {
            loadDestinations()
        }
    }

    private func loadDestinations() {
        isLoading = true
        let rootDestination = MoveNoteDestination(
            url: vaultRootURL.standardizedFileURL,
            name: "Vault Root",
            depth: 0
        )

        let folderRows = (try? SidebarTreeLoader(directoryLoader: directoryLoader)
            .loadRows(rootURL: vaultRootURL)
            .compactMap { row -> MoveNoteDestination? in
                guard case .folder = row.kind else { return nil }
                return MoveNoteDestination(
                    url: row.url,
                    name: row.name,
                    depth: row.depth + 1
                )
            }) ?? []

        destinations = [rootDestination] + folderRows
        isLoading = false
    }
}
