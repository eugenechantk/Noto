import Foundation
import NotoDigest
import Observation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "DigestModel")

/// One file the search index needs to hear about after a digest action.
struct DigestIndexRequest: Sendable, Equatable {
    let vaultURL: URL
    let fileURL: URL
    /// True when the file is gone (a filed or discarded capture), false when it
    /// was written (the note the capture landed in).
    let isRemoval: Bool
}

/// The Digest tab's queue: due captures from `inbox/`, newest first (a lapsed
/// snooze counts from its wake time), with the
/// front of the queue on the card.
///
/// Every action follows the same shape — do the filesystem work off the main
/// actor, and pop the card only if it succeeded. A failed action leaves the same
/// capture in front so the retry is obvious.
@MainActor
@Observable
final class DigestModel {
    /// A one-line result banner, mirroring Capture's status slot.
    struct Outcome: Equatable {
        let glyph: String
        let text: String
        /// Where the capture ended up, when there is somewhere to go look.
        let fileURL: URL?
        /// True when this outcome can be taken back — set for a discard, whose
        /// swipe commits with no confirmation dialog.
        var isUndoable = false
    }

    let vaultURL: URL
    private let inbox: DigestInbox
    private let filing: DigestFiling
    /// Injected so tests can run without touching the app's search index.
    private let index: @Sendable (DigestIndexRequest) async -> Void

    private(set) var entries: [DigestEntry] = []
    /// False until the first load finishes, so the empty state doesn't flash
    /// "inbox clear" before the folder has been read.
    private(set) var hasLoaded = false
    private(set) var isBusy = false
    private(set) var outcome: Outcome?
    /// The last discard, held for as long as its banner is on screen so the swipe
    /// can be taken back. Cleared when the banner clears.
    private(set) var lastDiscarded: DigestFiling.DiscardedCapture?
    var errorMessage: String?

    init(
        vaultURL: URL,
        inbox: DigestInbox? = nil,
        filing: DigestFiling? = nil,
        index: @escaping @Sendable (DigestIndexRequest) async -> Void = DigestModel.updateSearchIndex
    ) {
        self.vaultURL = vaultURL
        self.inbox = inbox ?? DigestInbox(vaultURL: vaultURL)
        self.filing = filing ?? DigestFiling(vaultURL: vaultURL)
        self.index = index
    }

    /// Default index hook: keep Noto 2's own FTS index in step with the vault, so
    /// a filed capture is searchable and a discarded one stops matching.
    static let updateSearchIndex: @Sendable (DigestIndexRequest) async -> Void = { request in
        if request.isRemoval {
            _ = try? await SearchIndexController.shared.removeFile(vaultURL: request.vaultURL, fileURL: request.fileURL)
        } else {
            await SearchIndexController.shared.scheduleRefreshFile(vaultURL: request.vaultURL, fileURL: request.fileURL)
        }
    }

    // MARK: - Queue

    var current: DigestEntry? { entries.first }
    /// The card behind the current one, so the stack looks deep while one remains.
    var next: DigestEntry? { entries.dropFirst().first }
    var remaining: Int { entries.count }
    /// True only once a load has completed and found nothing — the empty state.
    var isClear: Bool { hasLoaded && entries.isEmpty }

    func load() async {
        let inbox = self.inbox
        let now = Date()
        let loaded = await Task.detached(priority: .userInitiated) {
            inbox.dueEntries(now: now)
        }.value
        entries = loaded
        hasLoaded = true
        logger.info("digest loaded \(loaded.count) due captures")
    }

    /// Re-reads `inbox/` unless an action is in flight.
    ///
    /// The Digest tab is the back half of Capture's loop — you file a thought, then
    /// switch tabs to process it — so the queue must not be a one-shot load. Skipped
    /// while busy so a reload can't yank the card out from under a running action.
    func refresh() async {
        guard !isBusy else { return }
        await load()
    }

    // MARK: - Actions

    /// Pushes the current capture a week out. The file stays in `inbox/`, so the
    /// search index is untouched.
    @discardableResult
    func snoozeCurrent() async -> Bool {
        await perform(
            action: { filing, entry in
                let wake = try filing.snooze(entry)
                return Outcome(
                    glyph: "clock",
                    text: "Snoozed until \(Self.wakeFormatter.string(from: wake))",
                    fileURL: nil
                )
            },
            indexRequests: { _, _ in [] }
        )
    }

    /// Appends the current capture to an existing note, then clears it from the inbox.
    @discardableResult
    func addCurrent(toNoteAt targetURL: URL, titled title: String) async -> Bool {
        await perform(
            action: { filing, entry in
                let written = try filing.append(entry, toNoteAt: targetURL)
                return Outcome(glyph: "text.append", text: "Added to \(title)", fileURL: written)
            },
            indexRequests: { entry, outcome in
                [outcome.fileURL.map { ($0, false) }, (entry.fileURL, true)].compactMap { $0 }
            }
        )
    }

    /// Turns the current capture into a new note, then clears it from the inbox.
    @discardableResult
    func createNoteFromCurrent(title: String, inFolderAt folderURL: URL) async -> Bool {
        await perform(
            action: { filing, entry in
                let written = try filing.createNote(from: entry, title: title, inFolderAt: folderURL)
                return Outcome(
                    glyph: "doc.badge.plus",
                    text: "Created \(written.deletingPathExtension().lastPathComponent)",
                    fileURL: written
                )
            },
            indexRequests: { entry, outcome in
                [outcome.fileURL.map { ($0, false) }, (entry.fileURL, true)].compactMap { $0 }
            }
        )
    }

    /// Deletes the current capture, keeping its bytes so the swipe can be undone.
    @discardableResult
    func discardCurrent() async -> Bool {
        let box = DiscardBox()
        let ok = await perform(
            action: { filing, entry in
                box.value = try filing.discard(entry)
                return Outcome(glyph: "trash", text: "Discarded", fileURL: nil, isUndoable: true)
            },
            indexRequests: { entry, _ in [(entry.fileURL, true)] }
        )
        if ok { lastDiscarded = box.value }
        return ok
    }

    /// Puts the last discarded capture back and returns it to the queue.
    ///
    /// Swipe-down deletes with no confirmation — the red trash target is the
    /// warning — so this is the only recourse for a mis-swipe.
    @discardableResult
    func undoDiscard() async -> Bool {
        guard !isBusy, let discarded = lastDiscarded else { return false }
        isBusy = true
        defer { isBusy = false }

        let filing = self.filing
        let restored: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            Result { try filing.restore(discarded) }
        }.value

        switch restored {
        case .success:
            lastDiscarded = nil
            outcome = nil
            let index = self.index
            let request = DigestIndexRequest(vaultURL: vaultURL, fileURL: discarded.entry.fileURL, isRemoval: false)
            Task.detached(priority: .utility) { await index(request) }
            isBusy = false
            await load()
            DebugTrace.record("digest restored \(discarded.entry.relativePath)")
            return true
        case .failure(let error):
            let message = (error as? DigestFiling.FilingError)?.message ?? error.localizedDescription
            logger.error("digest undo failed: \(message, privacy: .public)")
            errorMessage = message
            return false
        }
    }

    /// Clears the outcome banner after it has had its moment on screen. The undo
    /// window closes with it — an undo you can no longer see is not an undo.
    func clearOutcome(_ shown: Outcome) {
        guard outcome == shown else { return }
        outcome = nil
        lastDiscarded = nil
    }

    /// Escape hatch for handing a value out of the `@Sendable` action closure.
    private final class DiscardBox: @unchecked Sendable {
        var value: DigestFiling.DiscardedCapture?
    }

    // MARK: - Plumbing

    /// Runs `action` off the main actor against the front of the queue, pops the
    /// card on success, and reports the failure without popping otherwise.
    private func perform(
        action: @escaping @Sendable (DigestFiling, DigestEntry) throws -> Outcome,
        indexRequests: (DigestEntry, Outcome) -> [(URL, Bool)]
    ) async -> Bool {
        guard !isBusy, let entry = current else { return false }
        isBusy = true
        defer { isBusy = false }

        let filing = self.filing
        let result: Result<Outcome, Error> = await Task.detached(priority: .userInitiated) {
            Result { try action(filing, entry) }
        }.value

        switch result {
        case .success(let outcome):
            entries.removeFirst()
            self.outcome = outcome
            DebugTrace.record("digest \(outcome.text) — \(entry.relativePath)")

            let requests = indexRequests(entry, outcome).map {
                DigestIndexRequest(vaultURL: vaultURL, fileURL: $0.0, isRemoval: $0.1)
            }
            if !requests.isEmpty {
                let index = self.index
                Task.detached(priority: .utility) {
                    for request in requests { await index(request) }
                }
            }
            return true

        case .failure(let error):
            let message = (error as? DigestFiling.FilingError)?.message ?? error.localizedDescription
            logger.error("digest action failed: \(message, privacy: .public)")
            errorMessage = message
            return false
        }
    }

    private static let wakeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
