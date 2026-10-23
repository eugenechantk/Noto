#if os(macOS)
import AppKit
import SwiftUI
import NotoVault
import NotoDigest
import NotoSearch

enum MacLibraryDestination: Hashable {
    case capture, daily, inbox, all, folder(URL)
    var title: String {
        switch self {
        case .capture: "Capture"
        case .daily: "Daily Notes"
        case .inbox: "Inbox"
        case .all: "All Notes"
        case .folder(let url): url.lastPathComponent
        }
    }
    var symbol: String {
        switch self {
        case .capture: "square.and.pencil"
        case .daily: "calendar"
        case .inbox: "tray"
        case .all: "doc.text"
        case .folder: "folder"
        }
    }
}

enum MacPalettePurpose: String, Identifiable {
    case search, append, create, move
    var id: String { rawValue }
    var placeholder: String {
        switch self {
        case .search: "Search your notes"
        case .append: "Add to a note…"
        case .create: "New note in…"
        case .move: "Move to…"
        }
    }
}

struct MacPendingNoteMove: Equatable {
    let noteID: UUID
    let directory: URL
}

@MainActor @Observable
final class MacDesktopModel {
    static let editorAction = Notification.Name("NotoDesktop.editorAction")
    let store: MarkdownNoteStore
    var library: VaultLibrarySnapshot?
    var destination: MacLibraryDestination = .all
    var selectedNote: MarkdownNote?
    var selectedIsNew = false
    var document = ""
    var documentReady = false
    var activeEditorID: UUID?
    var selectedNoteShare: NoteMarkdownShare? {
        guard selectedNote != nil, documentReady else { return nil }
        return NoteMarkdownShare(markdown: document)
    }

    func markdownShare(for note: VaultLibraryNote) -> NoteMarkdownShare {
        if selectedNote?.id == note.id, let selectedNoteShare { return selectedNoteShare }
        return NoteMarkdownShare(fileURL: note.fileURL)
    }
    var isLoading = false
    var error: String?
    var palette: MacPalettePurpose?
    var paletteNeedsNewFolder = false
    var paletteUsesDraft = false
    var findQuery: String?
    var findRequest = UUID()
    var history = NoteNavigationHistory()
    var expandedFolders: Set<URL> = []
    var sortOrder: VaultLibrarySortOrder = .newest
    var includeSubfolders = false
    var toast: String?
    var toastNoteURL: URL?
    var activity: VaultDailyActivity
    var filedToday: Int { activity.count(.filed) }
    var processedToday: Int { activity.count(.processed) }
    var inboxProgressTotal: Int {
        processedToday + (library?.notes.filter { $0.isInbox && ($0.snoozedUntil == nil || $0.snoozedUntil! <= Date()) }.count ?? 0)
    }
    var completedCount: Int { filedToday + processedToday }
    var isWorking = false
    var deletingNoteID: UUID?
    var pendingMove: MacPendingNoteMove?
    var pendingDuplicate: UUID?
    var hiddenNoteURLs: Set<URL> = []
    var draft: String { didSet { UserDefaults.standard.set(draft, forKey: draftKey) } }
    @ObservationIgnored private var undoAction: (() -> Void)?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var draftKey: String { "noto.mac.capture." + store.vaultRootURL.path }
    var vaultURL: URL { store.vaultRootURL }
    private var activityKey: String { "noto.mac.activity." + vaultURL.path }

    private func recordActivity(_ kind: VaultDailyActivity.Kind, delta: Int = 1, at date: Date = Date()) {
        if let data = UserDefaults.standard.data(forKey: activityKey), let saved = try? JSONDecoder().decode(VaultDailyActivity.self, from: data) { activity = saved }
        activity.record(kind, delta: delta, at: date)
        if let data = try? JSONEncoder().encode(activity) { UserDefaults.standard.set(data, forKey: activityKey) }
    }

    init(store: MarkdownNoteStore) {
        self.store = store
        self.activity = UserDefaults.standard.data(forKey: "noto.mac.activity." + store.vaultRootURL.path)
            .flatMap { try? JSONDecoder().decode(VaultDailyActivity.self, from: $0) } ?? VaultDailyActivity()
        self.draft = UserDefaults.standard.string(forKey: "noto.mac.capture." + store.vaultRootURL.path) ?? ""
    }

    var visibleNotes: [VaultLibraryNote] {
        let notes = unsortedVisibleNotes.filter { !hiddenNoteURLs.contains($0.fileURL.standardizedFileURL) }
        return destination == .daily ? notes : sortOrder.sorted(notes)
    }
    private var unsortedVisibleNotes: [VaultLibraryNote] {
        guard let library else { return [] }
        switch destination {
        case .capture: return []
        case .all: return library.notes
        case .daily: return library.notes.filter(\.isDaily).sorted { $0.fileURL.lastPathComponent > $1.fileURL.lastPathComponent }
        case .inbox: return library.notes.filter(\.isInbox)
        case .folder(let url): return library.notes(in: url, includingDescendants: includeSubfolders)
        }
    }
    var pinned: [VaultLibraryNote] { library?.notes.filter(\.isPinned) ?? [] }
    var currentLibraryNote: VaultLibraryNote? { library?.notes.first { $0.id == selectedNote?.id && !hiddenNoteURLs.contains($0.fileURL.standardizedFileURL) } }
    var currentEntry: DigestEntry? {
        guard destination == .inbox, let note = selectedNote else { return nil }
        // Entry body is refreshed by DigestFiling at the actual write boundary.
        return DigestEntry(id: note.id, fileURL: note.fileURL, relativePath: "inbox/" + note.fileURL.lastPathComponent,
            body: VaultMarkdown.stripFrontmatter(document), capturedAt: note.modifiedDate,
            isAvailable: currentLibraryNote?.isAvailable ?? false)
    }

    func refresh() async {
        if let data = UserDefaults.standard.data(forKey: activityKey), let saved = try? JSONDecoder().decode(VaultDailyActivity.self, from: data) { activity = saved }
        guard !isLoading else { return }
        isLoading = true
        let root = vaultURL
        let result = await BoundedFileRead.run(timeout: 8) { try? VaultLibrarySnapshot.load(vaultURL: root) }
        isLoading = false
        switch result {
        case .value(let snapshot):
            library = snapshot
            let paths = Set(snapshot.notes.map { $0.fileURL.standardizedFileURL })
            hiddenNoteURLs.formIntersection(paths)
            if destination == .inbox, let selectedNote, !visibleNotes.contains(where: { $0.id == selectedNote.id }) { nextInbox() }
            if selectedNote == nil {
                let first = destination == .inbox ? visibleNotes.first(where: { $0.snoozedUntil == nil || $0.snoozedUntil! <= Date() }) : visibleNotes.first
                if let first { open(first) }
            }
        case .failed: error = "The vault could not be read. Try opening the folder again."
        case .timedOut: error = "iCloud is still loading the vault. Try again shortly."
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func select(_ destination: MacLibraryDestination) {
        palette = nil
        pendingMove = nil; pendingDuplicate = nil
        self.destination = destination
        if destination == .capture { return }
        if destination == .daily { openToday(); return }
        let notes = visibleNotes
        if !notes.contains(where: { $0.id == selectedNote?.id }) {
            let first = destination == .inbox ? notes.first(where: { $0.snoozedUntil == nil || $0.snoozedUntil! <= Date() }) : notes.first
            if let first {
                open(first)
            } else { selectedNote = nil; document = "" }
        }
    }

    func open(_ note: VaultLibraryNote, recordHistory: Bool = true, query: String? = nil) {
        let preservesLoadedDocument = selectedNote?.id == note.id && documentReady
        open(MarkdownNote(id: note.id, fileURL: note.fileURL, title: note.title, modifiedDate: note.record.modifiedDate),
             recordHistory: recordHistory, query: query)
        if !preservesLoadedDocument { document = note.content }
    }

    func open(_ note: MarkdownNote, recordHistory: Bool = true, query: String? = nil, isNew: Bool = false) {
        if selectedNote?.id != note.id { documentReady = false }
        if pendingMove?.noteID != note.id { pendingMove = nil }
        if pendingDuplicate != note.id { pendingDuplicate = nil }
        selectedNote = note
        selectedIsNew = isNew
        findQuery = query
        findRequest = UUID()
        if recordHistory {
            history.visit(NoteStackEntry(note: note, directoryURL: note.fileURL.deletingLastPathComponent(), vaultRootURL: vaultURL, isNew: isNew))
        }
        if !NotoPreviewConfiguration.isEnabled {
            UserDefaults.standard.set(note.fileURL.path, forKey: "lastOpenedNoteURL")
        }
    }

    func navigateHistory(back: Bool) {
        let entry = back ? history.goBack() : history.goForward()
        guard let entry else { return }
        destination = .folder(entry.directoryURL)
        open(entry.note, recordHistory: false)
    }

    func openURL(_ url: URL, query: String? = nil) {
        if let note = library?.notes.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            destination = .folder(url.deletingLastPathComponent())
            open(note, query: query)
        } else if let path = VaultPathResolver(vaultRootURL: vaultURL).relativePath(for: url),
                  let result = store.note(atVaultRelativePath: path) {
            destination = .folder(url.deletingLastPathComponent())
            open(result.note, query: query)
        }
    }

    func openToday() {
        palette = nil
        pendingMove = nil; pendingDuplicate = nil
        destination = .daily
        openDaily(Date())
    }

    func openDaily(_ date: Date) {
        destination = .daily
        let result = DailyNoteService(vaultRootURL: vaultURL).ensure(date: date)
        open(MarkdownNote(id: result.id, fileURL: result.fileURL, title: result.displayTitle, modifiedDate: result.modifiedDate))
        scheduleRefresh()
    }

    func createNote() {
        let directory: URL
        if case .folder(let url) = destination { directory = url } else { directory = vaultURL }
        let noteStore = MarkdownNoteStore(directoryURL: directory, vaultRootURL: vaultURL, autoload: false)
        destination = .folder(directory)
        open(noteStore.createNote(), isNew: true)
        scheduleRefresh()
    }

    func duplicate(_ note: VaultLibraryNote) {
        pendingMove = nil
        if selectedNote?.id != note.id { open(note); pendingDuplicate = note.id; return }
        guard documentReady else { error = "Wait for the note to finish loading."; return }
        do {
            let repo = NoteRepository(directoryURL: note.fileURL.deletingLastPathComponent(), vaultRootURL: vaultURL)
            let duplicate = try repo.duplicate(note.record, content: document)
            destination = .folder(duplicate.fileURL.deletingLastPathComponent())
            open(MarkdownNote(id: duplicate.id, fileURL: duplicate.fileURL, title: duplicate.title, modifiedDate: duplicate.modifiedDate))
            scheduleRefresh()
            Task { await SearchIndexController.shared.scheduleRefresh(vaultURL: vaultURL, fileURL: duplicate.fileURL) }
        } catch { self.error = "The note could not be duplicated." }
    }

    func requestMove(_ note: VaultLibraryNote, to directory: URL) {
        pendingDuplicate = nil
        if selectedNote?.id != note.id { open(note) }
        pendingMove = MacPendingNoteMove(noteID: note.id, directory: directory)
    }

    func update(_ note: MarkdownNote) {
        guard selectedNote?.id == note.id else { return }
        selectedNote = note
        history.replaceEntries(for: note)
        scheduleRefresh()
    }

    func showToast(_ message: String, url: URL? = nil, undo: (() -> Void)? = nil) {
        toastTask?.cancel()
        toast = message; toastNoteURL = url; undoAction = undo
        toastTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            toast = nil; toastNoteURL = nil; undoAction = nil
        }
    }

    func undo() {
        guard let action = undoAction else { return }
        toastTask?.cancel(); undoAction = nil; toast = nil; toastNoteURL = nil
        action()
        scheduleRefresh()
    }
    var canUndo: Bool { undoAction != nil }

    func fileCapture() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let body = draft
            let service = CaptureFilingService(vaultURL: vaultURL)
            let filed = try service.file(body)
            hiddenNoteURLs.remove(filed.fileURL.standardizedFileURL)
            let filedDocument = CoordinatedFileManager.readString(from: filed.fileURL)
            let completedAt = Date()
            draft = ""; recordActivity(.filed, at: completedAt)
            Task { await SearchIndexController.shared.scheduleRefresh(vaultURL: vaultURL, fileURL: filed.fileURL) }
            showToast("Filed to Inbox", url: filed.fileURL) { [weak self] in
                guard let self else { return }
                if filed.didCreate {
                    guard CoordinatedFileManager.readString(from: filed.fileURL) == filedDocument, service.undo(filed) else {
                        self.error = "The capture changed after filing. It has been kept."; return
                    }
                    self.hiddenNoteURLs.insert(filed.fileURL.standardizedFileURL)
                    if self.selectedNote?.fileURL.standardizedFileURL == filed.fileURL.standardizedFileURL {
                        if self.activeEditorID == self.selectedNote?.id { self.deletingNoteID = self.selectedNote?.id }
                        self.selectedNote = nil; self.document = ""; self.destination = .capture
                    }
                }
                self.draft = body
                self.recordActivity(.filed, delta: -1, at: completedAt)
            }
            scheduleRefresh()
        } catch { self.error = "The capture could not be filed. Your text is still here." }
    }

    func discardDraft() {
        let body = draft
        guard !body.isEmpty else { return }
        draft = ""
        showToast("Capture discarded") { [weak self] in self?.draft = body }
    }

    func inboxAction(_ action: String) {
        guard let entry = currentEntry, entry.isAvailable, let note = selectedNote else { return }
        do {
            let filing = DigestFiling(vaultURL: vaultURL)
            let completedAt = Date()
            if action == "later" {
                let date = try filing.snooze(entry)
                showToast("Snoozed until \(date.formatted(date: .abbreviated, time: .omitted))")
            } else {
                let discarded = try filing.discard(entry)
                hiddenNoteURLs.insert(entry.fileURL.standardizedFileURL)
                showToast("Capture discarded") { [weak self] in
                    do {
                        guard let self else { return }
                        guard !FileManager.default.fileExists(atPath: entry.fileURL.path) else { self.error = "A capture already exists there. It has been kept."; return }
                        try filing.restore(discarded)
                        self.hiddenNoteURLs.remove(entry.fileURL.standardizedFileURL)
                        self.recordActivity(.processed, delta: -1, at: completedAt)
                        self.destination = .inbox
                        self.open(note)
                        self.document = discarded.document
                    } catch { self?.error = "The capture could not be restored." }
                }
            }
            recordActivity(.processed)
            nextInbox(excluding: entry.id)
            scheduleRefresh()
        } catch { self.error = (error as? DigestFiling.FilingError)?.message ?? error.localizedDescription }
    }

    func nextInbox(excluding id: UUID? = nil, direction: Int = 1) {
        let notes = visibleNotes.filter { $0.id != id && ($0.snoozedUntil == nil || $0.snoozedUntil! <= Date()) }
        guard !notes.isEmpty else { selectedNote = nil; document = ""; return }
        let current = notes.firstIndex { $0.id == selectedNote?.id } ?? (direction > 0 ? -1 : 0)
        open(notes[(current + direction + notes.count) % notes.count])
    }

    func file(to url: URL, purpose: MacPalettePurpose) {
        do {
            if purpose == .move, let note = selectedNote {
                NotificationCenter.default.post(name: Self.editorAction, object: self, userInfo: ["action": "move", "url": url, "noteID": note.id])
                return
            }
            let entry: DigestEntry
            if paletteUsesDraft {
                let filed = try CaptureFilingService(vaultURL: vaultURL).file(draft)
                guard let loaded = DigestInbox(vaultURL: vaultURL).entry(at: filed.fileURL) else { throw CocoaError(.fileReadUnknown) }
                entry = loaded
            } else {
                guard let currentEntry else { return }; entry = currentEntry
            }
            let filing = DigestFiling(vaultURL: vaultURL)
            let destinationURL = try purpose == .append ? filing.append(entry, toNoteAt: url) : filing.createNoteAsWritten(from: entry, inFolderAt: url)
            hiddenNoteURLs.insert(entry.fileURL.standardizedFileURL)
            if paletteUsesDraft { draft = "" } else { nextInbox(excluding: entry.id) }
            palette = nil; recordActivity(paletteUsesDraft ? .filed : .processed)
            showToast(purpose == .append ? "Added to note" : "New note created", url: destinationURL)
            Task { await SearchIndexController.shared.scheduleRefresh(vaultURL: vaultURL, fileURL: destinationURL) }
            scheduleRefresh()
        } catch { self.error = (error as? DigestFiling.FilingError)?.message ?? error.localizedDescription }
    }
}
#endif
