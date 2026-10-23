import NotoDigest
import NotoVault
import NotoLinkPreview
import SwiftUI
import UIKit

/// Inbox has two presentations of one file-backed queue. Native list swipes
/// intentionally follow Mail; card swipes keep the capture-specific mapping.
struct DigestScreen: View {
    let vaultController: VaultController
    var onOpenFiledNote: ((URL) -> Void)?
    var onCapture: (() -> Void)?

    @State private var model: DigestModel
    @State private var presentation: Presentation = .stack
    @State private var fileMode: DigestFileMode?
    @State private var showingDetail = false
    @State private var detailText = ""
    @State private var detailOriginal = ""
    @State private var detailEntry: DigestEntry?
    @State private var drag: CGSize = .zero
    @State private var flyDirection: DigestSwipe?
    @State private var hapticDirection: DigestSwipe?
    @State private var playingVideo: PlayingVideo?
    @State private var appearCount = 0
    @State private var isCommitting = false
    @State private var keyboardVisible = false
    @State private var restingStackHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .title) private var zeroTitleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var zeroDescriptionSize: CGFloat = 15
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Presentation: String, CaseIterable { case stack = "Stack", list = "List" }
    private var isCueDragActive: Bool { drag != .zero && flyDirection == nil }
    private var isCardInMotion: Bool { drag != .zero || flyDirection != nil || isCommitting }

    init(vaultController: VaultController, onOpenFiledNote: ((URL) -> Void)? = nil, onCapture: (() -> Void)? = nil) {
        self.vaultController = vaultController
        self.onOpenFiledNote = onOpenFiledNote
        self.onCapture = onCapture
        _model = State(wrappedValue: DigestModel(vaultURL: vaultController.vaultURL))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if presentation == .stack && !showingDetail && !model.isClear {
                    progressLine.opacity(isCueDragActive ? 0 : 1).accessibilityHidden(isCueDragActive)
                }
                if showingDetail || presentation == .stack {
                    if model.isClear && !showingDetail { emptyState }
                    else if let entry = model.current { stack(entry) }
                    else if !model.hasLoaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else { inboxList }
            }
            .background(NotoTheme.background.ignoresSafeArea())
            .overlay {
                // Keep every target above the moving card from the first drag
                // frame, including native scroll/editor content in the card.
                if isCueDragActive { cues.zIndex(1) }
            }
            .contextMenu {
                if presentation == .stack && !showingDetail, let entry = model.current {
                    actionMenu(entry)
                }
            }
            .toolbar {
                if showingDetail && !isCueDragActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { Task { if await persistDetail() { closeDetail() } } } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back to Inbox list")
                        .accessibilityIdentifier("inboxBackToList")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Inbox").fontWeight(.bold).foregroundStyle(NotoTheme.ink)
                        if model.remaining > 0 { Text("\(model.remaining)").foregroundStyle(NotoTheme.muted) }
                    }
                    .font(.system(size: showingDetail ? 26 : 28))
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(isCueDragActive ? 0.3 : 1)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("inboxTitle")
                }
                .sharedBackgroundVisibility(.hidden)
                if showingDetail && !isCueDragActive, let entry = detailEntry {
                    ToolbarItem(placement: .topBarTrailing) {
                        NoteMarkdownShareLink(item: shareItem(for: entry))
                            .accessibilityIdentifier("share_note_button")
                    }
                }
                if !showingDetail && !isCueDragActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("View", selection: $presentation) {
                            Text("Stack").tag(Presentation.stack).accessibilityIdentifier("inboxStackMode")
                            Text("List").tag(Presentation.list).accessibilityIdentifier("inboxListMode")
                        }
                        .pickerStyle(.segmented).frame(width: 132)
                        .accessibilityIdentifier("inboxViewPicker")
                    }
                    // The segmented control draws its own glass track; the
                    // toolbar's shared capsule would wrap it in a second one.
                    .sharedBackgroundVisibility(.hidden)
                } else if showingDetail && !isCueDragActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        if keyboardVisible {
                            Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                                .accessibilityIdentifier("inboxDismissKeyboard")
                        } else if let entry = model.current {
                            Text(Self.capturedStamp(entry.capturedAt)).font(.caption).foregroundStyle(NotoTheme.muted)
                        }
                    }
                }
            }
            .toolbar(isCueDragActive ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom) { toast }
            .accessibilityIdentifier(showingDetail ? "inboxCaptureDetail" : "inboxScreen")
        }
        .task(id: appearCount) { await model.refresh() }
        .task(id: detailText) {
            guard showingDetail else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            _ = await persistDetail()
        }
        .onDisappear { Task { _ = await persistDetail() } }
        .onAppear { appearCount &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: SharedCaptureDrain.didFileNotification)) { _ in Task { await model.refresh() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onChange(of: presentation) { _, _ in model.selectedEntryID = nil }
        .sheet(item: $fileMode, onDismiss: {
            if !showingDetail && !isCommitting { model.selectedEntryID = nil }
            springBack()
        }) { mode in
            if let entry = model.current {
                switch mode {
                case .addTo:
                    AddToNoteSheet(vaultURL: model.vaultURL, draft: entry.body) { candidate in
                        file(.addTo, entry: entry) { await model.addCurrent(toNoteAt: candidate.url, titled: candidate.title) }
                    }
                case .create:
                    NewNoteSheet(vaultURL: model.vaultURL, draft: entry.body, onCreateWithBody: { folder, body in
                        file(.create, entry: entry) { await model.createNoteFromCurrent(inFolderAt: folder.url, body: body) }
                    })
                }
            }
        }
        .fullScreenCover(item: $playingVideo) { video in VideoPlayerScreen(source: video.source).ignoresSafeArea() }
        .alert("Couldn't finish this action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .noteSharing()
    }

    private var progressLine: some View {
        HStack(spacing: 18) {
            Text("\(model.counts.total) of \(model.counts.total + model.remaining) done today")
                .font(.caption).foregroundStyle(NotoTheme.muted)
            Spacer()
            ProgressView(value: Double(model.counts.total), total: Double(max(1, model.counts.total + model.remaining)))
                .tint(NotoTheme.accent).frame(width: 120)
        }
        .padding(.horizontal, 20).padding(.top, 3).padding(.bottom, 14)
        .accessibilityIdentifier("inboxTodayProgress")
    }

    private func stack(_ entry: DigestEntry) -> some View {
        GeometryReader { geometry in
            let canvasHeight = isCardInMotion && restingStackHeight > 0 ? restingStackHeight : geometry.size.height
            ZStack {
                if model.next != nil && !showingDetail {
                    RoundedRectangle(cornerRadius: 28).fill(NotoTheme.peek)
                        .padding(.horizontal, 30).padding(.bottom, 44)
                        .offset(y: -10)
                        .accessibilityIdentifier("digestBackCard")
                }
                Group {
                    if showingDetail {
                        card(entry)
                            .contextMenu { actionMenu(entry) }
                            .padding(.horizontal, 16).padding(.bottom, 44)
                            .offset(cardOffset(size: geometry.size))
                            .rotationEffect(.degrees(reduceMotion ? 0 : min(9, max(-9, Double(drag.width) / 22))), anchor: .bottom)
                    } else {
                        card(entry)
                            .padding(.horizontal, 16).padding(.bottom, 44)
                            .offset(cardOffset(size: geometry.size))
                            .rotationEffect(.degrees(reduceMotion ? 0 : min(9, max(-9, Double(drag.width) / 22))), anchor: .bottom)
                    }
                }
                .simultaneousGesture(dragGesture)
                if !keyboardVisible && !isCueDragActive {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 12, weight: .medium)).frame(width: 14, height: 14)
                                .accessibilityHidden(true)
                            Text(showingDetail ? "Drag to file it, or tap the text to edit" : "Drag the card to file it · hold for a menu")
                        }
                        .font(.caption).foregroundStyle(NotoTheme.faint).padding(.bottom, 18)
                    }
                    .allowsHitTesting(false)
                }
            }
            // Native tab hiding expands the available region. Preserve the
            // card's size through the drag and commit while cues use the full
            // screen area. Do not record the expanded region during fly-out.
            .frame(height: canvasHeight, alignment: .top)
            .onChange(of: geometry.size.height, initial: true) { _, height in
                if !isCardInMotion { restingStackHeight = height }
            }
        }
    }

    private func card(_ entry: DigestEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !showingDetail {
                Text(Self.capturedStamp(entry.capturedAt)).font(.caption).foregroundStyle(NotoTheme.muted)
                    .padding(.horizontal, 20).padding(.top, 22).accessibilityIdentifier("digestCardDate")
            }
            if !entry.isAvailable {
                VStack(spacing: 8) { ProgressView(); Text("Downloading from iCloud…").font(.footnote).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("digestCardDownloading")
            } else if showingDetail {
                TextKit2EditorView(text: $detailText, documentID: entry.id.uuidString,
                                   autoFocus: false, onTextChange: { detailText = $0 },
                                   vaultRootURL: model.vaultURL, keyboardToolbarStyle: .floating,
                                   backgroundColorOverride: NotoTheme.uiCard, disablesScrollBounce: true,
                                   topTextInsetOverride: 22, bottomTextInsetOverride: 20)
                    .padding(.horizontal, 6).accessibilityIdentifier("inboxCaptureEditor")
            } else {
                readOnlyContent(entry).padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            if let direction = activeDirection {
                RoundedRectangle(cornerRadius: 28).stroke(Self.tint(direction).opacity(0.7), lineWidth: 1.5).allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("digestCard")
        .accessibilityAction(named: "Add to note") { choose(.addTo, entry: entry) }
        .accessibilityAction(named: "New note") { choose(.create, entry: entry) }
        .accessibilityAction(named: "Later") { choose(.snooze, entry: entry) }
        .accessibilityAction(named: "Discard") { choose(.discard, entry: entry) }
    }

    private func readOnlyContent(_ entry: DigestEntry) -> some View {
        let link = DigestLinkCardSplit.split(body: entry.body)
        let media = DigestMediaSplit.split(link.map { $0.remainder ?? "" } ?? entry.body, vaultURL: model.vaultURL)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let prose = media.text {
                    Text(DigestCardText.attributed(prose)).font(.system(size: NotoTheme.FontSize.body))
                        .foregroundStyle(NotoTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let link { DigestLinkCard(url: link.url).frame(height: LinkPreviewCardLayout.defaultHeight) }
                if !media.media.isEmpty {
                    DigestMediaStrip(items: media.media) { url in
                        if let source = VideoPlayback.prepare(url) { playingVideo = PlayingVideo(source: source) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("digestCardBody")
    }

    private var inboxList: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        Button { openDetail(entry) } label: { listRow(entry) }
                            .buttonStyle(.plain)
                            .listRowBackground(NotoTheme.card)
                            .accessibilityIdentifier("inboxRow_" + entry.fileURL.lastPathComponent)
                            .contextMenu { actionMenu(entry) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { choose(.snooze, entry: entry) } label: { Label("Snooze", systemImage: "clock") }
                                    .tint(NotoTheme.inboxLater).accessibilityIdentifier("inboxRowSnooze")
                                Button { choose(.discard, entry: entry) } label: { Label("Delete", systemImage: "trash") }
                                    .tint(NotoTheme.inboxDiscard).accessibilityIdentifier("inboxRowDelete")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { choose(.addTo, entry: entry) } label: { Label("Add to", systemImage: "text.append") }
                                    .tint(NotoTheme.inboxAddTo).accessibilityIdentifier("inboxRowAddTo")
                                Button { choose(.create, entry: entry) } label: { Label("New note", systemImage: "doc.badge.plus") }
                                    .tint(NotoTheme.inboxNewNote).accessibilityIdentifier("inboxRowNewNote")
                            }
                    }
                } header: {
                    HStack(spacing: 5) {
                        if section.kind == .snoozed {
                            Image(systemName: "clock").font(.caption).foregroundStyle(NotoTheme.muted)
                                .accessibilityHidden(true)
                        }
                        FilingSectionCaption(section.kind.rawValue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped).contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .overlay { if model.allEntries.isEmpty && model.hasLoaded { emptyState } }
        .accessibilityIdentifier("inboxList")
    }

    private func listRow(_ entry: DigestEntry) -> some View {
        let lines = entry.body.split(separator: "\n", omittingEmptySubsequences: true)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DigestMarkdown.noteTitle(fromFirstLineOf: entry.body) ?? "Downloading…")
                    .font(.body.weight(.semibold)).foregroundStyle(NotoTheme.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(rowStamp(entry)).font(.caption).foregroundStyle(NotoTheme.muted).fixedSize()
            }
            if lines.count > 1 { Text(String(lines[1])).font(.subheadline).foregroundStyle(NotoTheme.muted).lineLimit(1) }
        }
        .padding(.vertical, 3).frame(maxWidth: .infinity, alignment: .leading)
        .opacity(entry.isDue(at: Date()) ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    private func actionMenu(_ entry: DigestEntry) -> some View {
        Group {
            NoteMarkdownShareLink(item: shareItem(for: entry))
                .accessibilityIdentifier("share_note_context_item")
            Button("Add to note…", systemImage: "text.append") { choose(.addTo, entry: entry) }.accessibilityIdentifier("inboxMenuAddTo")
            Button("New note…", systemImage: "doc.badge.plus") { choose(.create, entry: entry) }.accessibilityIdentifier("inboxMenuNewNote")
            Button("Later", systemImage: "clock") { choose(.snooze, entry: entry) }.accessibilityIdentifier("inboxMenuLater")
            Button("Discard", systemImage: "trash", role: .destructive) { choose(.discard, entry: entry) }.accessibilityIdentifier("inboxMenuDiscard")
        }
        .disabled(model.isBusy || !entry.isAvailable)
    }

    private func shareItem(for entry: DigestEntry) -> NoteMarkdownShare? {
        guard entry.isAvailable else { return nil }
        if showingDetail && detailEntry?.id == entry.id && detailText != detailOriginal {
            return NoteMarkdownShare(body: detailText)
        }
        return NoteMarkdownShare(fileURL: entry.fileURL)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 18) {
                    Image(systemName: "tray").font(.system(size: 34, weight: .light))
                        .foregroundStyle(NotoTheme.ink)
                        .overlay {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NotoTheme.accent).offset(y: -7)
                        }
                        .frame(width: 112, height: 112)
                        .background(NotoTheme.card, in: Circle())
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text("Inbox zero").font(.system(size: zeroTitleSize, weight: .bold)).foregroundStyle(NotoTheme.ink)
                        Text("Everything you captured is filed or\nsnoozed.")
                            .font(.system(size: zeroDescriptionSize)).foregroundStyle(NotoTheme.muted)
                            .lineSpacing(2).multilineTextAlignment(.center)
                            .frame(maxWidth: 280).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 0) {
                    countCell(model.counts.filed, label: "Filed today")
                    Divider().frame(height: 52)
                    countCell(model.counts.discarded, label: "Discarded")
                    Divider().frame(height: 52)
                    countCell(model.counts.snoozed, label: "Snoozed")
                }
                .padding(.vertical, 18).background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("inboxTodayCounts")
                if let wake = model.futureSnoozed.compactMap(\.snoozedUntil).min() {
                    Button { presentation = .list } label: {
                        HStack {
                            Image(systemName: "clock").foregroundStyle(NotoTheme.inboxLater)
                            Text("\(model.futureSnoozed.count) snoozed").foregroundStyle(NotoTheme.ink)
                            Spacer()
                            Text("Back \(wake.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))").font(.caption).foregroundStyle(NotoTheme.muted)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(NotoTheme.muted)
                        }
                        .padding(16).background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("inboxSnoozedRow")
                }
                Button { onCapture?() } label: { Label("Capture something", systemImage: "square.and.pencil") }
                    .buttonStyle(.glass).controlSize(.large).padding(.top, 16).accessibilityIdentifier("inboxCaptureButton")
            }
            .padding(.horizontal, 20).padding(.top, 64).padding(.bottom, 24)
        }
        .accessibilityIdentifier("digestEmptyState")
    }

    private func countCell(_ count: Int, label: String) -> some View {
        VStack(spacing: 4) { Text("\(count)").font(.title.bold()); Text(label).font(.caption).foregroundStyle(NotoTheme.muted) }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var toast: some View {
        if let outcome = model.outcome {
            let icon = toastIcon(for: outcome)
            GlassToastView(message: outcome.text, systemImage: icon.symbol, iconColor: icon.color,
                           onUndo: outcome.isUndoable ? { Task { _ = await model.undoLastAction() } } : nil,
                           onOpen: outcome.fileURL.map { url in { onOpenFiledNote?(url) } }, identifier: "inboxToast")
                .padding(.horizontal, 12).padding(.bottom, 8)
                .task(id: outcome.id) {
                    do { try await Task.sleep(for: .seconds(6)) } catch { return }
                    model.clearOutcome(outcome)
                }
        }
    }

    private func toastIcon(for outcome: DigestModel.Outcome) -> (symbol: String, color: Color) {
        switch outcome.glyph {
        case "text.append", "doc.badge.plus": ("checkmark", NotoTheme.inboxNewNote)
        case "clock": ("clock", NotoTheme.inboxLater)
        case "trash": ("trash", NotoTheme.inboxDiscard)
        default: (outcome.glyph, NotoTheme.ink)
        }
    }

    private var cues: some View {
        ZStack {
            VStack { cue(.create); Spacer(); cue(.discard) }.padding(.vertical, 0).padding(.bottom, 42)
            HStack { cue(.snooze); Spacer(); cue(.addTo) }.padding(.leading, 12).padding(.trailing, 18)
        }
        .allowsHitTesting(false)
    }

    private func cue(_ direction: DigestSwipe) -> some View {
        let active = activeDirection == direction
        return VStack(spacing: 6) {
            Image(systemName: Self.glyph(direction)).font(.system(size: active ? 28 : 22, weight: .medium))
                .foregroundStyle(active ? NotoTheme.onAction : Self.tint(direction))
                .frame(width: active ? 80 : 56, height: active ? 80 : 56)
                .background(active ? Self.tint(direction) : NotoTheme.card, in: Circle())
                .background {
                    if active { Circle().fill(Self.tint(direction).opacity(0.25)).padding(-10) }
                }
            Text(Self.label(direction)).font(.system(size: 13, weight: .bold)).foregroundStyle(active ? Self.tint(direction) : NotoTheme.muted)
        }
        .opacity(active ? 1 : 0.6)
        .accessibilityIdentifier("inboxCueTarget_" + direction.rawValue)
    }

    private var activeDirection: DigestSwipe? { DigestSwipe.allCases.max(by: { strength($0) < strength($1) }).flatMap { strength($0) > 0.15 ? $0 : nil } }
    private func strength(_ direction: DigestSwipe) -> CGFloat { DigestSwipeResolver.signalStrength(for: direction, translation: drag) }
    private static func tint(_ direction: DigestSwipe) -> Color {
        switch direction { case .addTo: NotoTheme.inboxAddTo; case .create: NotoTheme.inboxNewNote; case .snooze: NotoTheme.inboxLater; case .discard: NotoTheme.inboxDiscard }
    }
    private static func glyph(_ direction: DigestSwipe) -> String {
        switch direction { case .addTo: "text.append"; case .create: "doc.badge.plus"; case .snooze: "clock"; case .discard: "trash" }
    }
    private static func label(_ direction: DigestSwipe) -> String {
        switch direction { case .addTo: "Add to note"; case .create: "New note"; case .snooze: "Later"; case .discard: "Discard" }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12).onChanged { value in
            guard !model.isBusy, !isCommitting, fileMode == nil, !keyboardVisible else { return }
            if drag == .zero { InboxDragDiagnostics.record("begin", value: value) }
            drag = value.translation
            let thresholdDirection = DigestSwipeResolver.resolveRelease(translation: value.translation, predicted: value.translation, velocity: .zero)
            if let thresholdDirection, thresholdDirection != hapticDirection {
                InboxDragDiagnostics.record("threshold-" + thresholdDirection.rawValue, value: value)
                UISelectionFeedbackGenerator().selectionChanged()
                hapticDirection = thresholdDirection
            } else if thresholdDirection == nil { hapticDirection = nil }
        }.onEnded { value in
            InboxDragDiagnostics.record("end", value: value)
            guard !model.isBusy, !isCommitting, fileMode == nil, !keyboardVisible, let entry = model.current else { springBack(); return }
            if let direction = DigestSwipeResolver.resolveRelease(translation: value.translation, predicted: value.predictedEndTranslation,
                                                                  velocity: CGSize(width: value.velocity.width, height: value.velocity.height)) {
                choose(direction, entry: entry)
            } else { springBack() }
        }
    }

    private func choose(_ direction: DigestSwipe, entry: DigestEntry) {
        guard !isCommitting, !model.isBusy, entry.isAvailable else { return }
        Task {
            guard await persistDetail() else { return }
            model.selectedEntryID = entry.id
            if direction.opensSheet {
                fileMode = direction == .addTo ? .addTo : .create
                springBack()
            } else {
                file(direction, entry: entry) {
                    direction == .snooze ? await model.snoozeCurrent() : await model.discardCurrent()
                }
            }
        }
    }

    private func file(_ direction: DigestSwipe, entry: DigestEntry, action: @escaping @MainActor () async -> Bool) {
        isCommitting = true
        model.selectedEntryID = entry.id
        fileMode = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { flyDirection = direction }
        Task {
            let started = ContinuousClock.now
            let ok = await action()
            if !reduceMotion { try? await Task.sleep(until: started.advanced(by: .milliseconds(220)), clock: .continuous) }
            if ok { showingDetail = false; detailEntry = nil; detailOriginal = ""; detailText = "" }
            flyDirection = nil
            drag = .zero
            isCommitting = false
            if !showingDetail { model.selectedEntryID = nil }
        }
    }

    private func openDetail(_ entry: DigestEntry) {
        model.selectedEntryID = entry.id
        detailEntry = entry
        detailText = entry.body
        detailOriginal = entry.body
        showingDetail = true
    }
    private func closeDetail() { showingDetail = false; model.selectedEntryID = nil; detailEntry = nil; detailOriginal = ""; detailText = "" }
    private func persistDetail() async -> Bool {
        guard showingDetail, let entry = detailEntry, detailText != detailOriginal else { return true }
        let text = detailText
        if await model.saveBody(text, for: entry) { detailOriginal = text; return true }
        return false
    }
    private func springBack() { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero; flyDirection = nil }; hapticDirection = nil }
    private func cardOffset(size: CGSize) -> CGSize {
        guard let direction = flyDirection else { return drag }
        switch direction {
        case .addTo: return CGSize(width: size.width + 200, height: 0)
        case .snooze: return CGSize(width: -size.width - 200, height: 0)
        case .create: return CGSize(width: 0, height: -size.height - 200)
        case .discard: return CGSize(width: 0, height: size.height + 200)
        }
    }
    private static func capturedStamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday" : date.formatted(.dateTime.month(.abbreviated).day())
        return day + ", " + date.formatted(.dateTime.hour().minute())
    }
    private func rowStamp(_ entry: DigestEntry) -> String {
        guard let wake = entry.snoozedUntil else { return entry.capturedAt.formatted(.dateTime.hour().minute()) }
        return entry.isDue(at: Date()) ? "Back today" : "Back " + wake.formatted(.dateTime.weekday(.abbreviated))
    }
}
