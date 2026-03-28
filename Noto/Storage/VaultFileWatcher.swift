import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "VaultFileWatcher")

/// Monitors a vault directory for external file changes (iCloud sync, other apps).
/// Publishes `onChange` notifications debounced to avoid rapid-fire reloads.
@MainActor
final class VaultFileWatcher: ObservableObject {

    /// Fires when external changes are detected. Subscribers should reload their data.
    @Published private(set) var changeCount: Int = 0

    /// The URL of the specific file that was last changed externally, if known.
    /// nil means the directory itself changed (add/delete) — reload everything.
    @Published private(set) var lastChangedFileURL: URL?

    private var presenter: VaultPresenter?
    private var debounceTask: Task<Void, Never>?

    /// Starts watching the given directory for external changes.
    func watch(directory url: URL) {
        stop()
        let presenter = VaultPresenter(directory: url) { [weak self] changedURL in
            Task { @MainActor [weak self] in
                self?.handleChange(fileURL: changedURL)
            }
        }
        self.presenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
        logger.info("Started watching \(url.lastPathComponent)")
    }

    /// Stops watching.
    func stop() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            self.presenter = nil
            logger.info("Stopped watching")
        }
        debounceTask?.cancel()
    }

    private func handleChange(fileURL: URL?) {
        // Debounce: wait 500ms after the last change before notifying.
        // iCloud often syncs multiple files in rapid succession.
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.lastChangedFileURL = fileURL
            self?.changeCount += 1
            logger.info("External change detected (count: \(self?.changeCount ?? 0))")
        }
    }

    deinit {
        // Can't call stop() from deinit on a MainActor class directly,
        // but we can remove the presenter synchronously.
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
    }
}

// MARK: - NSFilePresenter (non-isolated, runs on its own queue)

private final class VaultPresenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()

    private let onChange: @Sendable (URL?) -> Void

    init(directory: URL, onChange: @escaping @Sendable (URL?) -> Void) {
        self.presentedItemURL = directory
        self.onChange = onChange
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue.qualityOfService = .utility
    }

    // MARK: - Directory-level changes

    /// Called when a file is added, removed, or renamed within the directory.
    func presentedSubitemDidChange(at url: URL) {
        // Only care about .md files and directories
        let ext = url.pathExtension
        if ext == "md" || ext.isEmpty {
            onChange(url)
        }
    }

    func presentedSubitemDidAppear(at url: URL) {
        onChange(url)
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        onChange(nil) // directory structure changed — full reload
    }

    /// Called when the directory itself changes (e.g. iCloud replaces the folder).
    func presentedItemDidChange() {
        onChange(nil)
    }
}
