import Foundation
import NotoVault
import Observation

/// Owns Daily Notes navigation while the shared editor owns text and autosave.
@MainActor
@Observable
final class TodayModel {
    let vaultController: VaultController
    let calendar: Calendar
    private let service: DailyNoteService
    private let now: () -> Date
    private var loadRevision = 0
    private var calendarRevision = 0

    private(set) var selectedDate: Date
    private(set) var session: NoteEditorSession?
    private(set) var isLoading = false
    private(set) var hasOpened = false
    private(set) var errorMessage: String?
    private(set) var writtenDays: Set<Date> = []
    private(set) var scrollRevision = 0

    init(vaultController: VaultController, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.vaultController = vaultController
        self.calendar = calendar
        self.now = now
        self.service = DailyNoteService(vaultRootURL: vaultController.vaultURL)
        self.selectedDate = calendar.startOfDay(for: now())
    }

    var today: Date { calendar.startOfDay(for: now()) }
    var canGoNext: Bool { selectedDate < today }
    var caption: String { DailyNoteDay.caption(for: selectedDate, now: now(), calendar: calendar) }
    var dateTitle: String { DailyNoteDay.title(for: selectedDate, calendar: calendar) }
    var scrollRestorationID: String { "daily-\(session?.note.id.uuidString ?? "empty")-\(scrollRevision)" }

    func openIfNeeded() async {
        guard !hasOpened else {
            await refreshSelectedDay()
            return
        }
        hasOpened = true
        await openSelectedDay(createIfMissing: calendar.isDate(selectedDate, inSameDayAs: today))
    }

    func refreshSelectedDay(changedURL: URL? = nil) async {
        guard hasOpened else { return }
        if let session {
            session.handleExternalChange(changedURL: changedURL)
            return
        }
        guard !isLoading else { return }
        await openSelectedDay(createIfMissing: calendar.isDate(selectedDate, inSameDayAs: today))
    }

    func previousDay() async {
        await select(DailyNoteDay.offset(selectedDate, by: -1, calendar: calendar))
    }

    func nextDay() async {
        guard canGoNext else { return }
        await select(DailyNoteDay.offset(selectedDate, by: 1, calendar: calendar))
    }

    func select(_ date: Date) async {
        let normalized = calendar.startOfDay(for: date)
        guard normalized <= today else { return }
        if normalized == selectedDate, session != nil { return }
        persistCurrentNote()
        selectedDate = normalized
        scrollRevision += 1
        await openSelectedDay(createIfMissing: calendar.isDate(normalized, inSameDayAs: today))
    }

    func reselectTab() async {
        persistCurrentNote()
        scrollRevision += 1
        selectedDate = today
        hasOpened = true
        await openSelectedDay(createIfMissing: true)
    }

    func startSelectedDay() async {
        guard !isLoading, selectedDate <= today else { return }
        await openSelectedDay(createIfMissing: true, focusEditor: true)
    }

    func retry() async {
        await openSelectedDay(createIfMissing: calendar.isDate(selectedDate, inSameDayAs: today))
    }

    func persistCurrentNote() {
        session?.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
    }

    func refreshWrittenDays(inMonthContaining date: Date) async {
        persistCurrentNote()
        calendarRevision += 1
        let revision = calendarRevision
        let service = service
        let calendar = calendar
        let result = await Task.detached(priority: .utility) {
            service.writtenDays(inMonthContaining: date, calendar: calendar)
        }.value
        guard revision == calendarRevision, !Task.isCancelled else { return }
        writtenDays = result
    }

    private func openSelectedDay(createIfMissing: Bool, focusEditor: Bool = false) async {
        loadRevision += 1
        let revision = loadRevision
        let date = selectedDate
        let service = service
        let calendar = calendar
        errorMessage = nil
        isLoading = true
        do {
            let resolution = try await Task.detached(priority: .userInitiated) {
                try service.open(date: date, createIfMissing: createIfMissing, calendar: calendar)
            }.value
            guard revision == loadRevision else { return }
            if let resolution {
                if session?.note.fileURL != resolution.fileURL {
                    session?.cancelBackgroundWork()
                    let note = MarkdownNote(
                        id: resolution.id,
                        fileURL: resolution.fileURL,
                        title: resolution.displayTitle,
                        modifiedDate: resolution.modifiedDate
                    )
                    let newSession = NoteEditorSession(
                        store: vaultController.store(for: resolution.dailyFolderURL, autoload: false),
                        note: note,
                        isNew: focusEditor,
                        vaultController: vaultController
                    )
                    session = newSession
                    await newSession.loadNoteContent()
                } else {
                    session?.handleExternalChange(changedURL: nil)
                }
            } else {
                session?.cancelBackgroundWork()
                session = nil
            }
        } catch {
            guard revision == loadRevision else { return }
            session = nil
            errorMessage = error.localizedDescription
        }
        guard revision == loadRevision else { return }
        isLoading = false
    }
}
