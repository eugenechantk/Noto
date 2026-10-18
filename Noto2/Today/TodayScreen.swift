import NotoVault
import SwiftUI

struct TodayScreen: View {
    let reselectRevision: Int
    @State private var model: TodayModel
    @State private var showsCalendar = false
    @State private var focusedEditorID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VaultFileWatcher.self) private var fileWatcher: VaultFileWatcher?

    init(vaultController: VaultController, reselectRevision: Int = 0) {
        self.reselectRevision = reselectRevision
        _model = State(initialValue: TodayModel(vaultController: vaultController))
    }

    init(model: TodayModel, reselectRevision: Int = 0) {
        self.reselectRevision = reselectRevision
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .background(NotoTheme.background.ignoresSafeArea())
                .navigationTitle("Daily Notes")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar(focusedEditorID != nil && focusedEditorID == model.session?.editorSessionID ? .hidden : .visible, for: .tabBar)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await model.previousDay() }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Previous day")
                        .accessibilityIdentifier("dailyPreviousDayButton")

                        Button {
                            model.persistCurrentNote()
                            showsCalendar = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityLabel("Choose a day")
                        .accessibilityIdentifier("dailyCalendarButton")

                        Button {
                            Task { await model.nextDay() }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!model.canGoNext)
                        .accessibilityLabel("Next day")
                        .accessibilityIdentifier("dailyNextDayButton")
                    }
                }
                .accessibilityIdentifier("dailyNotesScreen")
        }
        .tint(NotoTheme.ink)
        .task { await model.openIfNeeded() }
        .onChange(of: reselectRevision) { _, _ in
            showsCalendar = false
            Task { await model.reselectTab() }
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            let changedURL = fileWatcher?.lastChangedFileURL
            Task { await model.refreshSelectedDay(changedURL: changedURL) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshSelectedDay() }
            } else {
                model.persistCurrentNote()
            }
        }
        .onDisappear {
            focusedEditorID = nil
            model.persistCurrentNote()
        }
        .sheet(isPresented: $showsCalendar) {
            DailyCalendarSheet(
                selectedDate: model.selectedDate,
                today: model.today,
                calendar: model.calendar,
                writtenDays: model.writtenDays,
                onSelect: { date in
                    showsCalendar = false
                    Task { await model.select(date) }
                },
                onMonthChange: { date in
                    Task { await model.refreshWrittenDays(inMonthContaining: date) }
                }
            )
            .task { await model.refreshWrittenDays(inMonthContaining: model.selectedDate) }
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.caption.uppercased())
                .font(.caption.weight(.medium))
                .tracking(0.7)
                .foregroundStyle(NotoTheme.muted)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .accessibilityIdentifier("dailyDayCaption")

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("dailyNoteLoading")
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't open this day", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.retry() } }
                        .accessibilityIdentifier("dailyRetryButton")
                }
            } else if let session = model.session {
                DailyNoteEditor(
                    session: session,
                    scrollRestorationID: model.scrollRestorationID,
                    onFocusChange: { focused in
                        if focused {
                            focusedEditorID = session.editorSessionID
                        } else if focusedEditorID == session.editorSessionID {
                            focusedEditorID = nil
                        }
                    }
                )
                .id(session.editorSessionID)
            } else {
                emptyDay
            }
        }
    }

    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.dateTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(NotoTheme.faint)
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .accessibilityIdentifier("dailyEmptyDateTitle")

            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(NotoTheme.muted)
                        .frame(width: 56, height: 56)
                        .background(NotoTheme.subdued, in: Circle())
                    Text("No note for this day")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NotoTheme.head)
                        .frame(minHeight: 26)
                    Text("Past days stay empty until you write in them.")
                        .font(.subheadline)
                        .foregroundStyle(NotoTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 22)
                    Button("Start this day's note") {
                        Task { await model.startSelectedDay() }
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(NotoTheme.accent)
                    .foregroundStyle(NotoTheme.onAccent)
                    .controlSize(.large)
                    .padding(.top, 6)
                    .accessibilityIdentifier("dailyStartNoteButton")
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                // Board 56 separates the date line and empty group by 128 pt.
                // Keep that spacing stable rather than centering in leftover height.
                .padding(.top, 128)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("dailyEmptyState")
    }
}

/// Composes the current editor without changing its rendering or text behavior.
private struct DailyNoteEditor: View {
    @Bindable var session: NoteEditorSession
    let scrollRestorationID: String
    let onFocusChange: (Bool) -> Void

    var body: some View {
        Group {
            if session.downloadFailed {
                ContentUnavailableView {
                    Label("Note Not Available", systemImage: "exclamationmark.icloud")
                } description: {
                    Text("This note hasn't finished downloading from iCloud.")
                } actions: {
                    Button("Try Again") { Task { await session.loadNoteContent() } }
                        .accessibilityIdentifier("dailyDownloadRetryButton")
                }
            } else {
                TextKit2EditorView(
                    text: $session.content,
                    documentID: session.note.id.uuidString,
                    autoFocus: session.isNew,
                    onTextChange: session.handleEditorChange,
                    vaultRootURL: session.store.vaultRootURL,
                    onImportImageData: session.importImageAttachment(data:suggestedFilename:),
                    pageMentionProvider: { query in
                        session.vaultController.rootStore.pageMentionDocuments(matching: query, excluding: session.note.fileURL)
                    },
                    scrollRestorationID: scrollRestorationID,
                    initialContentOffsetY: -CGFloat.greatestFiniteMagnitude,
                    onFocusChange: onFocusChange,
                    keyboardToolbarStyle: .floating,
                    topTextInsetOverride: 4,
                    bottomTextInsetOverride: 20
                )
                .tint(NotoTheme.accent)
                .accessibilityIdentifier("dailyNoteEditor")
            }
        }
    }
}
