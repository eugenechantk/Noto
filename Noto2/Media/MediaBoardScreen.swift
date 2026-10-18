import CryptoKit
import os.log
import NotoLinkPreview
import NotoShareCapture
import NotoVault
import SwiftUI

private let mediaLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MediaBoardScreen")

struct MediaBoardScreen: View {
    let vaultController: VaultController
    @Environment(VaultFileWatcher.self) private var fileWatcher
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var items: [VaultMediaItem] = []
    @State private var query = ""
    @State private var path: [Destination] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var unavailableNoteCount = 0
    @State private var refreshRevision = 0
    @State private var thumbnailRevision = 0
    @State private var navigationError = false
    @State private var isVisible = false

    private enum Destination: Hashable {
        case search
        case source(BrowseDestination)
    }

    var body: some View {
        NavigationStack(path: $path) {
            mediaContent(searching: false)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Media")
                            .font(.headline)
                            .foregroundStyle(NotoTheme.head)
                            .accessibilityIdentifier("media_title")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            query = ""
                            path.append(.search)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search media")
                        .accessibilityIdentifier("media_search_button")
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .search:
                        MediaSearchScreen(query: $query) {
                            mediaContent(searching: true)
                        }
                    case .source(let source):
                        BrowseDestinationView(destination: source, vaultController: vaultController, onOpen: { path.append(.source($0)) })
                            .id(source)
                    }
                }
                .alert("Note unavailable", isPresented: $navigationError) {
                    Button("OK", role: .cancel) { refreshRevision += 1 }
                } message: {
                    Text("The source note may have moved or may still be downloading. Refresh the board and try again.")
                }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(isVisible)|\(refreshRevision)") {
            guard isVisible else { return }
            if !items.isEmpty {
                // A refresh: one vault change fans out into several notifications
                // (file watcher, note sync, link previews); a new revision cancels
                // this wait, so a burst ends in one scan.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            await reload()
        }
        .onChange(of: fileWatcher.changeCount) { _, _ in refreshRevision += 1 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshRevision += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { _ in refreshRevision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: SharedCaptureDrain.didFileNotification)) { _ in refreshRevision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: LinkPreviewService.didChangeNotification)) { _ in refreshRevision += 1 }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { refreshRevision += 1 }
        }
    }

    private func mediaContent(searching: Bool) -> some View {
        let visibleItems = searching ? VaultMediaLibrary.filtered(items, query: query) : items
        return GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let loadError {
                        statusMessage(loadError, symbol: "exclamationmark.triangle")
                            .accessibilityIdentifier("media_load_error")
                    }
                    if unavailableNoteCount > 0 {
                        statusMessage("\(unavailableNoteCount) notes aren’t available yet. Pull to refresh after iCloud finishes downloading.", symbol: "icloud.and.arrow.down")
                            .accessibilityIdentifier("media_pending_notes")
                    }
                    if isLoading && items.isEmpty {
                        ProgressView("Finding your media…")
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .accessibilityIdentifier("media_loading")
                    } else if visibleItems.isEmpty && loadError == nil {
                        ContentUnavailableView(
                            items.isEmpty ? "Your media, together" : "No matching media",
                            systemImage: items.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass",
                            description: Text(items.isEmpty
                                ? "Images, videos, audio, and PDFs saved in your notes appear here, including media extracted from shared links."
                                : "Try another search.")
                        )
                        .accessibilityIdentifier("media_empty_state")
                    } else {
                        board(visibleItems, width: geometry.size.width - 32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { refreshRevision += 1 }
            .background(NotoTheme.background.ignoresSafeArea())
        }
    }

    private func board(_ displayedItems: [VaultMediaItem], width: CGFloat) -> some View {
        let count = dynamicTypeSize.isAccessibilitySize ? max(1, Int(width / 300)) : max(2, Int(width / 190))
        let tileWidth = max(1, (width - CGFloat(count - 1) * 12) / CGFloat(count))
        return HStack(alignment: .top, spacing: 12) {
            ForEach(0..<count, id: \.self) { column in
                LazyVStack(spacing: 18) {
                    ForEach(Array(displayedItems.enumerated()).filter { $0.offset % count == column }.map(\.element)) { item in
                        Button { open(item) } label: {
                            MediaBoardTile(item: item, width: tileWidth, revision: thumbnailRevision)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.kind.title): \(item.caption.isEmpty ? item.mediaURL.lastPathComponent : item.caption). \(item.noteTitle)")
                        .accessibilityHint("Opens the source note")
                        .accessibilityIdentifier("media_item_\(item.noteRelativePath)_\(item.mediaURL.lastPathComponent)")
                    }
                }
                .frame(width: tileWidth)
            }
        }
        .accessibilityIdentifier("media_board")
    }

    private func statusMessage(_ message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: symbol)
                .font(.footnote)
                .foregroundStyle(NotoTheme.muted)
            Button("Refresh") { refreshRevision += 1 }
                .accessibilityIdentifier("media_retry_button")
        }
    }

    private func open(_ item: VaultMediaItem) {
        guard let destination = BrowseDestination.note(at: item.noteURL, in: vaultController) else {
            navigationError = true
            return
        }
        path.append(.source(destination))
    }

    @MainActor
    private func reload() async {
        isLoading = true
        let previewCache = LinkPreviewSupport.service.cache
        let library = VaultMediaLibrary(vaultURL: vaultController.vaultURL,
                                        indexURL: MediaBoardIndex.url(for: vaultController.vaultURL),
                                        linkSearchText: { previewCache.searchText(for: $0) })
        if items.isEmpty {
            // Show the last scan in this very frame (a small JSON read), so the
            // "Finding your media…" placeholder never flashes; the refresh below
            // reads only changed notes.
            let cached = library.cachedSnapshot()
            if !cached.items.isEmpty {
                items = cached.items
                thumbnailRevision += 1
            }
            MediaBoardIndex.pruneStale(keeping: MediaBoardIndex.url(for: vaultController.vaultURL))
        }
        let started = Date()
        let scan = Task.detached(priority: .utility) { try library.scan() }
        do {
            let snapshot = try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
            try Task.checkCancellation()
            mediaLogger.info("Media scan: \(snapshot.items.count) items, \(snapshot.unavailableNoteCount) unavailable, \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            items = snapshot.items
            unavailableNoteCount = snapshot.unavailableNoteCount
            loadError = nil
            thumbnailRevision += 1
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Couldn’t read your media library. \(error.localizedDescription)"
        }
        isLoading = false
    }
}

extension VaultMediaKind {
    var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .pdf: "PDF"
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "play.fill"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        }
    }
}

/// Where the media board remembers its last scan: one index per vault in Caches
/// (a purge only costs one full scan).
enum MediaBoardIndex {
    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("MediaIndex", isDirectory: true)
    }

    static func url(for vaultURL: URL) -> URL {
        let name = SHA256.hash(data: Data(stablePath(vaultURL).utf8))
            .prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }

    /// A path that survives the app's data folder moving (reinstalls change its
    /// UUID): inside the app's home it is written relative to it. An iCloud
    /// Drive vault lives outside the home and keeps its absolute path.
    static func stablePath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
        return path.hasPrefix(home) ? "~/" + path.dropFirst(home.count) : path
    }

    /// Drops indexes of vaults not opened for 30 days (a switched or moved vault).
    static func pruneStale(keeping current: URL) {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.standardizedFileURL != current.standardizedFileURL {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
