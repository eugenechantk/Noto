import Foundation
import NotoDigest
import Observation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "DigestModel")

struct DigestIndexRequest: Sendable, Equatable {
    let vaultURL: URL
    let fileURL: URL
    let isRemoval: Bool
}

@MainActor
@Observable
final class DigestModel {
    struct Outcome: Equatable {
        let id = UUID()
        let glyph: String
        let text: String
        let fileURL: URL?
        var isUndoable = false
    }

    let vaultURL: URL
    private let inbox: DigestInbox
    private let filing: DigestFiling
    private let index: @Sendable (DigestIndexRequest) async -> Void
    private let now: @Sendable () -> Date
    private let defaults: UserDefaults
    private let tallyKey: String
    private var tally: DigestDailyTally
    private var undoEvent: UUID?
    private var undoReceipt: DigestFiling.UndoReceipt?
    private var snoozeReceipt: DigestFiling.SnoozedCapture?

    private(set) var allEntries: [DigestEntry] = []
    private(set) var entries: [DigestEntry] = []
    private(set) var hasLoaded = false
    private(set) var isBusy = false
    private(set) var outcome: Outcome?
    private(set) var lastDiscarded: DigestFiling.DiscardedCapture?
    var selectedEntryID: UUID?
    var errorMessage: String?

    init(vaultURL: URL, inbox: DigestInbox? = nil, filing: DigestFiling? = nil,
         now: @escaping @Sendable () -> Date = Date.init, defaults: UserDefaults = .standard,
         index: @escaping @Sendable (DigestIndexRequest) async -> Void = DigestModel.updateSearchIndex) {
        self.vaultURL = vaultURL
        self.inbox = inbox ?? DigestInbox(vaultURL: vaultURL)
        self.filing = filing ?? DigestFiling(vaultURL: vaultURL, now: now)
        self.now = now
        self.defaults = defaults
        self.index = index
        tallyKey = "noto2.inbox.tally." + vaultURL.standardizedFileURL.path
        tally = defaults.data(forKey: tallyKey).flatMap { try? JSONDecoder().decode(DigestDailyTally.self, from: $0) } ?? DigestDailyTally()
    }

    static let updateSearchIndex: @Sendable (DigestIndexRequest) async -> Void = { request in
        if request.isRemoval {
            _ = try? await SearchIndexController.shared.removeFile(vaultURL: request.vaultURL, fileURL: request.fileURL)
        } else {
            await SearchIndexController.shared.scheduleRefreshFile(vaultURL: request.vaultURL, fileURL: request.fileURL)
        }
    }

    var current: DigestEntry? {
        if let selectedEntryID { return allEntries.first { $0.id == selectedEntryID } }
        return entries.first
    }
    var next: DigestEntry? { selectedEntryID == nil ? entries.dropFirst().first : nil }
    var remaining: Int { entries.count }
    var isClear: Bool { hasLoaded && entries.isEmpty }
    var counts: DigestDailyTally.Counts { tally.counts(at: now()) }
    var sections: [DigestSection] { DigestPresentation.sections(allEntries, now: now()) }
    var futureSnoozed: [DigestEntry] { allEntries.filter { !$0.isDue(at: now()) } }

    func load() async {
        let inbox = self.inbox
        let date = now()
        let loaded = await Task.detached(priority: .userInitiated) { inbox.allEntries() }.value
        allEntries = DigestPresentation.ordered(loaded, now: date)
        entries = allEntries.filter { $0.isDue(at: date) }
        hasLoaded = true
    }

    func refresh() async { guard !isBusy else { return }; await load() }

    @discardableResult func snoozeCurrent() async -> Bool {
        let box = ReceiptBox()
        return await perform(.snoozed, action: { filing, entry in
            let receipt = try filing.snoozeWithUndo(entry)
            box.snoozed = receipt
            return Outcome(glyph: "clock", text: "Snoozed until \(receipt.wakeDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))", fileURL: nil, isUndoable: true)
        }, receipt: box)
    }

    @discardableResult func addCurrent(toNoteAt url: URL, titled title: String) async -> Bool {
        let box = ReceiptBox()
        return await perform(.filed, action: { filing, entry in
            let receipt = try filing.appendWithUndo(entry, toNoteAt: url)
            box.filed = receipt
            return Outcome(glyph: "text.append", text: "Added to \(title)", fileURL: receipt.destinationURL, isUndoable: true)
        }, receipt: box)
    }

    /// Legacy caller compatibility; new flows use the as-written variant below.
    @discardableResult func createNoteFromCurrent(title: String, inFolderAt folderURL: URL) async -> Bool {
        await perform(.filed, action: { filing, entry in
            let written = try filing.createNote(from: entry, title: title, inFolderAt: folderURL)
            return Outcome(glyph: "doc.badge.plus", text: "Created \(written.deletingPathExtension().lastPathComponent)", fileURL: written)
        })
    }

    @discardableResult func createNoteFromCurrent(inFolderAt folder: URL, body: String? = nil) async -> Bool {
        let box = ReceiptBox()
        let name = folder.standardizedFileURL == vaultURL.standardizedFileURL ? "Library" : folder.lastPathComponent
        return await perform(.filed, action: { filing, entry in
            let receipt = try filing.createWithUndo(entry, inFolderAt: folder, body: body)
            box.filed = receipt
            return Outcome(glyph: "doc.badge.plus", text: "Created in \(name)", fileURL: receipt.destinationURL, isUndoable: true)
        }, receipt: box)
    }

    @discardableResult func discardCurrent() async -> Bool {
        let box = ReceiptBox()
        return await perform(.discarded, action: { filing, entry in
            let discarded = try filing.discard(entry)
            box.discarded = discarded
            return Outcome(glyph: "trash", text: "Discarded", fileURL: nil, isUndoable: !discarded.document.isEmpty)
        }, receipt: box)
    }

    @discardableResult func saveBody(_ body: String, for entry: DigestEntry) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        let filing = self.filing
        let result = await Task.detached(priority: .userInitiated) { Result { try filing.updateBody(body, of: entry) } }.value
        isBusy = false
        switch result {
        case .success:
            await load()
            await index(.init(vaultURL: vaultURL, fileURL: entry.fileURL, isRemoval: false))
            return true
        case .failure(let error): report(error); return false
        }
    }

    @discardableResult func undoDiscard() async -> Bool { await undoLastAction() }

    @discardableResult func undoLastAction() async -> Bool {
        guard !isBusy, outcome?.isUndoable == true else { return false }
        isBusy = true
        defer { isBusy = false }
        let filing = self.filing
        let filed = undoReceipt, snoozed = snoozeReceipt, discarded = lastDiscarded
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                if let filed { try filing.undo(filed) }
                else if let snoozed { try filing.undoSnooze(snoozed) }
                else if let discarded { try filing.restore(discarded) }
            }
        }.value
        switch result {
        case .success:
            if let undoEvent { tally.undo(undoEvent); persistTally() }
            if let capture = filed?.capture.entry ?? discarded?.entry ?? snoozed?.entry {
                await index(.init(vaultURL: vaultURL, fileURL: capture.fileURL, isRemoval: false))
            }
            if let target = filed?.destinationURL {
                await index(.init(vaultURL: vaultURL, fileURL: target, isRemoval: filed?.destinationBefore == nil))
            }
            clearUndo()
            outcome = nil
            await load()
            return true
        case .failure(let error): report(error); return false
        }
    }

    func clearOutcome(_ shown: Outcome) {
        guard outcome == shown else { return }
        outcome = nil
        clearUndo()
    }

    private func clearUndo() {
        lastDiscarded = nil; undoReceipt = nil; snoozeReceipt = nil; undoEvent = nil
    }

    private final class ReceiptBox: @unchecked Sendable {
        var filed: DigestFiling.UndoReceipt?
        var snoozed: DigestFiling.SnoozedCapture?
        var discarded: DigestFiling.DiscardedCapture?
    }

    private func perform(_ kind: DigestDailyTally.Action,
                         action: @escaping @Sendable (DigestFiling, DigestEntry) throws -> Outcome,
                         receipt: ReceiptBox? = nil) async -> Bool {
        guard !isBusy, let entry = current else { return false }
        isBusy = true
        defer { isBusy = false }
        let filing = self.filing
        let result = await Task.detached(priority: .userInitiated) { Result { try action(filing, entry) } }.value
        switch result {
        case .success(let result):
            clearUndo()
            outcome = result
            undoReceipt = receipt?.filed
            snoozeReceipt = receipt?.snoozed
            lastDiscarded = receipt?.discarded
            undoEvent = tally.record(kind, at: now())
            persistTally()
            selectedEntryID = nil
            await load()
            if let target = result.fileURL { await index(.init(vaultURL: vaultURL, fileURL: target, isRemoval: false)) }
            await index(.init(vaultURL: vaultURL, fileURL: entry.fileURL, isRemoval: kind != .snoozed))
            return true
        case .failure(let error): report(error); return false
        }
    }

    private func persistTally() { if let data = try? JSONEncoder().encode(tally) { defaults.set(data, forKey: tallyKey) } }
    private func report(_ error: Error) {
        let message = (error as? DigestFiling.FilingError)?.message ?? error.localizedDescription
        logger.error("Inbox operation failed: \(message, privacy: .public)")
        errorMessage = message
    }
}
