#if os(macOS)
import AppKit
import SwiftUI
import NotoVault

struct MacDesktopWorkspace: View {
    let store: MarkdownNoteStore
    var locationManager: VaultLocationManager?
    var fileWatcher: VaultFileWatcher?
    @ObservedObject var readwiseSyncController: ReadwiseSyncController
    @ObservedObject var deepLinkRouter: NotoDeepLinkRouter
    var initialDocumentLink: String?
    @State private var model: MacDesktopModel
    @State private var window: NSWindow?
    @State private var palettePreviousResponder: NSResponder?
    @State private var sidebarVisible = true
    @State private var listVisible = true
    @State private var listOverlay = false
    @State private var sidebarOverlay = false
    @State private var inspectorVisible = false
    @State private var focusMode = false
    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var folderName = ""
    @State private var showRenameNote = false
    @State private var renamedTitle = ""
    @State private var inboxEditing = false
    @Environment(\.openWindow) private var openWindow

    init(store: MarkdownNoteStore, locationManager: VaultLocationManager?, fileWatcher: VaultFileWatcher?, readwiseSyncController: ReadwiseSyncController, deepLinkRouter: NotoDeepLinkRouter, initialDocumentLink: String?) {
        self.store = store; self.locationManager = locationManager; self.fileWatcher = fileWatcher
        self.readwiseSyncController = readwiseSyncController; self.deepLinkRouter = deepLinkRouter
        self.initialDocumentLink = initialDocumentLink
        _model = State(initialValue: MacDesktopModel(store: store))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let wide = width >= 1100 && !focusMode
            let single = width < 760 || focusMode
            let contentLeading: CGFloat = (wide && sidebarVisible ? 264 : 0)
                + (!single && listVisible && model.destination != .capture && !(inspectorVisible && !wide) ? inspectorVisible && wide ? 281 : wide ? 305 : 301 : 0)
            let showsDocument = model.selectedNote != nil && model.destination != .capture && (model.destination != .inbox || inboxEditing)
            let editorWidth = width - contentLeading - (showsDocument && inspectorVisible && !single ? 296 : 0)
            ZStack {
                HStack(spacing: 0) {
                    if wide && sidebarVisible { sidebar }
                    if !single && listVisible && model.destination != .capture && !(inspectorVisible && !wide) {
                        noteList(isNarrow: !wide, onClose: nil).frame(width: inspectorVisible && wide ? 281 : wide ? 305 : 301)
                    }
                    VStack(spacing: 0) {
                        if !showsDocument { header(width: width, contentWidth: editorWidth, atWindowLeading: contentLeading == 0, single: single, wide: wide) }
                        content(width: width, single: single, embeddedHeader: showsDocument ? AnyView(header(width: width, contentWidth: editorWidth, atWindowLeading: contentLeading == 0, single: single, wide: wide)) : nil)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if sidebarOverlay {
                    overlayBackdrop { sidebarOverlay = false }
                    HStack { sidebar; Spacer(minLength: 0) }.transition(.move(edge: .leading))
                } else if listOverlay && single && model.destination != .capture {
                    overlayBackdrop { listOverlay = false }
                    HStack {
                        noteList(isNarrow: true, onClose: { listOverlay = false }).frame(width: min(320, width - 32))
                            .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
                            .padding(8)
                        Spacer(minLength: 0)
                    }.transition(.move(edge: .leading))
                }
                if model.palette != nil {
                    overlayBackdrop { model.palette = nil }
                    MacDesktopPalette(model: model, onOpenInNewWindow: { openWindow(id: "main", value: $0) }, isCompact: width < 760, isNarrow: width < 1100)
                        .frame(width: min(width >= 1100 ? 640 : 600, width - 32)).padding(.top, width >= 1100 ? 112 : width >= 760 ? 120 : 72).frame(maxHeight: .infinity, alignment: .top)
                }
                if let toast = model.toast {
                    VStack { Spacer(); toastView(toast).padding(.horizontal, 24).padding(.bottom, 57) }
                        .frame(maxWidth: .infinity).padding(.leading, contentLeading).allowsHitTesting(true)
                        .offset(x: wide && model.destination == .capture ? -4 : 0)
                }
            }
            .overlay(alignment: .topLeading) {
                MacDesktopWindowControls().frame(width: 60, height: 16).padding(.leading, 26).padding(.top, 24)
            }
            .padding(1)
            .animation(.easeInOut(duration: 0.18), value: sidebarOverlay)
            .animation(.easeInOut(duration: 0.18), value: listOverlay)
            .onChange(of: model.destination) { _, destination in
                listOverlay = false; sidebarOverlay = false; inboxEditing = false; model.palette = nil
                if destination == .capture || destination == .inbox { inspectorVisible = false; focusMode = false }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(MacDesktopStyle.background).foregroundStyle(Color(red: 236/255, green: 236/255, blue: 238/255))
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.macDesktopState, MacDesktopCommandState(
            sidebar: Binding(get: { (window?.contentView?.bounds.width ?? 1200) >= 1100 && !focusMode ? sidebarVisible : sidebarOverlay }, set: { value in
                if (window?.contentView?.bounds.width ?? 1200) >= 1100 && !focusMode { sidebarVisible = value } else { sidebarOverlay = value }
            }), list: Binding(get: { (window?.contentView?.bounds.width ?? 1200) < 760 ? listOverlay : listVisible }, set: { value in
                if (window?.contentView?.bounds.width ?? 1200) < 760 { listOverlay = value } else { listVisible = value }
            }), inspector: Binding(get: { inspectorVisible }, set: setInspector), focus: $focusMode, sortOrder: $model.sortOrder, includeSubfolders: $model.includeSubfolders,
            isCapture: model.destination == .capture, canActOnNote: model.palette == nil && model.destination != .capture && model.selectedNote != nil,
            canFileCapture: model.palette == nil && model.destination == .capture && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        .background(MacDesktopWindowReader(window: $window).frame(width: 0, height: 0))
        .task {
            await model.refresh()
            if let initialDocumentLink { openDocumentPath(initialDocumentLink) }
            else if let pending = deepLinkRouter.consumePendingDocumentPath() { openDocumentPath(pending) }
            else if !NotoPreviewConfiguration.isEnabled {
                if let saved = UserDefaults.standard.string(forKey: "lastOpenedNoteURL"), VaultPathResolver(vaultRootURL: model.vaultURL).contains(URL(fileURLWithPath: saved)) {
                    model.openURL(URL(fileURLWithPath: saved))
                } else { model.openToday() }
            }
        }
        .onChange(of: model.palette) { old, purpose in
            if old == nil, purpose != nil {
                palettePreviousResponder = window?.firstResponder
                window?.makeFirstResponder(nil)
            } else if purpose == nil {
                let responder = palettePreviousResponder
                palettePreviousResponder = nil
                DispatchQueue.main.async {
                    if let view = responder as? NSView, view.window === window { window?.makeFirstResponder(view) }
                }
            }
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in model.scheduleRefresh() }
        .onChange(of: deepLinkRouter.pendingDocumentPath) { _, path in
            if let path = deepLinkRouter.consumePendingDocumentPath() { openDocumentPath(path) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { notification in
            if NotoCommandTarget.matches(notification, window: window) { model.palette = .search }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openToday)) { notification in
            if NotoCommandTarget.matches(notification, window: window) { model.openToday() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.createNote)) { notification in
            if NotoCommandTarget.matches(notification, window: window) { newNoteCommand() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openSettings)) { notification in
            if NotoCommandTarget.matches(notification, window: window) { showSettings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: MacDesktopCommands.action)) { notification in
            guard NotoCommandTarget.matches(notification, window: window), let action = notification.userInfo?["action"] as? String else { return }
            handleCommand(action)
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $folderName).accessibilityIdentifier("macFolderName")
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename note", isPresented: $showRenameNote) {
            TextField("Title", text: $renamedTitle).accessibilityIdentifier("macRenameTitle")
            Button("Rename") {
                let title = renamedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, let note = model.selectedNote else { return }
                NotificationCenter.default.post(name: MacDesktopModel.editorAction, object: model, userInfo: ["action": "rename", "noteID": note.id, "title": title])
            }.disabled(renamedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not complete the action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showSettings) {
            if let locationManager {
                SettingsView(locationManager: locationManager, readwiseSyncController: readwiseSyncController).frame(minWidth: 460, minHeight: 600)
            }
        }
    }

    private var sidebar: some View {
        MacDesktopSidebar(model: model, onHide: { sidebarVisible = false; sidebarOverlay = false }, onNewFolder: beginNewFolder, onSettings: { showSettings = true })
    }
    private func noteList(isNarrow: Bool, onClose: (() -> Void)?) -> some View {
        MacDesktopNoteList(model: model, isNarrow: isNarrow, onSidebar: { sidebarOverlay.toggle() }, onClose: onClose,
            onSelect: { listOverlay = false; inboxEditing = false }, onMove: { model.palette = .move }, onPin: pin, onTrash: trash,
            onRename: { note in renamedTitle = note.title; showRenameNote = true })
    }
    private func overlayBackdrop(_ action: @escaping () -> Void) -> some View {
        Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture(perform: action).accessibilityIdentifier("macOverlayBackdrop")
    }
    @ViewBuilder private func header(width: CGFloat, contentWidth: CGFloat, atWindowLeading: Bool, single: Bool, wide: Bool) -> some View {
        if focusMode {
            HStack(spacing: 14) {
                MacDesktopIconButton(symbol: "sidebar.left", label: "Leave Focus mode", id: "macLeaveFocus") { focusMode = false }
                    .padding(.horizontal, 3).frame(height: 32).background(.white.opacity(0.05), in: Capsule())
                Spacer()
                Text(model.selectedNote?.title ?? "").font(.system(size: 13)).foregroundStyle(MacDesktopStyle.secondary)
                Spacer()
                Button { focusMode = false } label: {
                    HStack(spacing: 6) { Text("Focus").fontWeight(.semibold); Text("⇧⌘F") }
                        .font(.system(size: 12)).foregroundStyle(MacDesktopStyle.icon).padding(.horizontal, 10).frame(height: 32)
                }.buttonStyle(.plain).background(MacDesktopStyle.accent.opacity(0.14), in: Capsule()).accessibilityIdentifier("macFocusMode")
            }.padding(.leading, 88).padding(.trailing, 12).frame(height: 52)
        } else {
        let documentDestination = model.destination != .capture && model.destination != .daily && model.destination != .inbox
        let inspectorActions = inspectorVisible && !single && model.destination != .capture
        let compactDocumentActions = !wide && documentDestination && !inspectorActions
        HStack(spacing: compactDocumentActions ? 10 : 12) {
            if !wide && atWindowLeading && !single && model.destination != .capture {
                MacDesktopIconButton(symbol: "sidebar.left", label: "Show sidebar", id: "macShowSidebar") { sidebarOverlay = true }
            }
            if single {
                if model.destination == .capture { MacDesktopDestinationMenu(model: model).frame(maxWidth: 140) }
                else {
                    Button { listOverlay.toggle() } label: {
                        Label(model.destination.title, systemImage: model.destination.symbol).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: 30)
                    }.buttonStyle(.plain).background(.white.opacity(0.07), in: Capsule()).accessibilityIdentifier("macShowNotes")
                }
            } else if model.destination == .capture && !wide {
                MacDesktopIconButton(symbol: "sidebar.left", label: "Show sidebar", id: "macShowSidebar") { sidebarOverlay = true }
            } else if wide && !sidebarVisible {
                MacDesktopIconButton(symbol: "sidebar.left", label: "Show sidebar", id: "macShowSidebar") { sidebarVisible = true }
            }
            if model.destination == .capture {
                if wide { Text("Capture").font(.system(size: 15, weight: .semibold)); Text("Goes to Inbox").font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary) }
            } else if model.destination == .daily {
                HStack(spacing: 2) {
                MacDesktopIconButton(symbol: "chevron.left", label: "Previous day", id: "macPreviousDay") { adjacentDay(-1) }
                Button("Today") { model.openToday() }.buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 10)
                MacDesktopIconButton(symbol: "chevron.right", label: "Next day", id: "macNextDay") { adjacentDay(1) }
                }.padding(.horizontal, 3).frame(height: 32).background(.white.opacity(0.07), in: Capsule())
                if !single {
                    HStack(spacing: 4) {
                        Text("Daily Notes").foregroundStyle(MacDesktopStyle.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(MacDesktopStyle.secondary)
                        Text(model.selectedNote?.title ?? "").fontWeight(.semibold)
                    }.font(.system(size: 12)).lineLimit(1)
                }
            } else if model.destination == .inbox {
                Text(model.selectedNote?.modifiedDate.formatted(date: .abbreviated, time: .shortened) ?? "Inbox")
                    .font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).lineLimit(1)
            } else {
                HStack(spacing: 2) {
                    MacDesktopIconButton(symbol: "chevron.left", label: "Back", id: "macHistoryBack") { model.navigateHistory(back: true) }.disabled(!model.history.canGoBack)
                    MacDesktopIconButton(symbol: "chevron.right", label: "Forward", id: "macHistoryForward") { model.navigateHistory(back: false) }.disabled(!model.history.canGoForward)
                }.padding(.horizontal, compactDocumentActions ? 4 : 3).frame(height: compactDocumentActions ? 34 : 32).background(.white.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                if !single {
                    HStack(spacing: 4) {
                        Text(wide && !inspectorVisible ? model.currentLibraryNote?.breadcrumb ?? model.destination.title : model.selectedNote?.fileURL.deletingLastPathComponent().lastPathComponent ?? model.destination.title).foregroundStyle(MacDesktopStyle.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(MacDesktopStyle.secondary)
                        Text(model.selectedNote?.title ?? "").fontWeight(.semibold)
                    }.font(.system(size: 13)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if inspectorActions || compactDocumentActions {
                HStack(spacing: 2) {
                    Button { model.palette = .search } label: { Image(systemName: "magnifyingglass").font(.system(size: 15)).frame(width: 32, height: 26) }
                        .buttonStyle(.plain).accessibilityLabel("Search your notes").accessibilityIdentifier("macSearch")
                    if inspectorActions {
                        ShareLink(item: model.selectedNote?.fileURL ?? model.vaultURL) { Image(systemName: "square.and.arrow.up").font(.system(size: 16)).frame(width: 32, height: 26) }
                            .buttonStyle(.plain).accessibilityLabel("Share")
                        Button { setInspector(false) } label: { Image(systemName: "sidebar.right").font(.system(size: 15)).frame(width: 32, height: 26) }
                            .buttonStyle(.plain).accessibilityLabel("Hide inspector").accessibilityIdentifier("macToggleInspector")
                    } else {
                        Menu {
                            Toggle("Show Inspector", isOn: Binding(get: { inspectorVisible }, set: setInspector))
                            Toggle("Focus Mode", isOn: $focusMode)
                            Divider()
                            ShareLink(item: model.selectedNote?.fileURL ?? model.vaultURL) { Text("Share…") }
                        } label: { Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 32, height: 26) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 32, height: 26)
                            .accessibilityLabel("More").accessibilityIdentifier("macMore")
                    }
                }.padding(.horizontal, 4).frame(height: 34).background(.white.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            } else {
            if model.destination == .capture {
                Button { model.fileCapture() } label: { HStack(spacing: 8) { Text("File to Inbox"); Text("⌘↩").foregroundStyle(MacDesktopStyle.secondary) }.font(.system(size: 13, weight: .bold)).padding(.horizontal, 12).frame(width: 162, height: 32) }
                    .buttonStyle(.plain).background(model.draft.isEmpty ? Color.white.opacity(0.07) : MacDesktopStyle.accent, in: Capsule()).disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("macFileCapture")
            } else if !single {
                HStack(spacing: 2) {
                    if model.destination != .inbox { ShareLink(item: model.selectedNote?.fileURL ?? model.vaultURL) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).frame(width: 30, height: 28) }
                    MacDesktopIconButton(symbol: "sidebar.right", label: "Show inspector", id: "macToggleInspector") { setInspector(!inspectorVisible) }
                }.padding(.horizontal, 3).frame(height: 32).background(.white.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            }
            Button { model.palette = .search } label: {
                let full = wide && contentWidth >= 800
                HStack(spacing: full ? 8 : 6) {
                    Image(systemName: "magnifyingglass")
                    if full { Text("Search"); Spacer() }
                    Text("⌘K").font(.system(size: 11.5)).padding(.horizontal, 4).frame(height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.12)))
                }.font(.system(size: 13)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, full ? 11 : 8).frame(width: full ? 200 : 70, height: 32)
            }.buttonStyle(.plain).background(.white.opacity(0.07), in: Capsule()).accessibilityLabel("Search your notes").accessibilityIdentifier("macSearch")
            }
        }
        .padding(.leading, atWindowLeading ? 88 : compactDocumentActions ? 12 : 14)
        .padding(.trailing, compactDocumentActions ? 10 : 12).frame(height: 52)
        .accessibilityElement(children: .contain).accessibilityIdentifier("macEditorHeader")
        }
    }
    private func setInspector(_ visible: Bool) {
        guard model.destination != .capture else { return }
        if visible && model.destination == .inbox { inboxEditing = true }
        inspectorVisible = visible
    }
    @ViewBuilder private func content(width: CGFloat, single: Bool, embeddedHeader: AnyView?) -> some View {
        if model.destination == .capture {
            MacDesktopCapture(model: model, isWide: width >= 1100)
        } else if model.destination == .inbox && !inboxEditing {
            MacDesktopInbox(model: model, narrow: width < 1100, compact: single, onEdit: { inboxEditing = true })
        } else if let note = model.selectedNote {
            VStack(spacing: 0) {
                if inboxEditing {
                    HStack {
                        Text("Editing capture").font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary)
                        Spacer()
                        Button("Done") { inboxEditing = false; inspectorVisible = false }.keyboardShortcut(.cancelAction).accessibilityIdentifier("macFinishInboxEdit")
                    }.padding(.horizontal, 16).frame(height: 36)
                }
                MacDesktopEditor(model: model, note: note, fileWatcher: fileWatcher, hostingWindow: window,
                    inspectorVisible: $inspectorVisible, single: single, onOpenPath: openDocumentPath, header: embeddedHeader, focusEditorOnOpen: inboxEditing, focusMode: focusMode,
                    textColumnWidth: width >= 1100 ? inspectorVisible ? 540 : 640 : inspectorVisible && !single ? 440 : model.destination == .daily ? 480 : 500,
                    minimumTextInset: width < 760 || inspectorVisible ? 28 : 32, showsMetadataProperties: width >= 1100 && !inspectorVisible)
                    .id(note.id)
            }
        } else {
            ContentUnavailableView(model.destination == .inbox ? "Inbox is clear" : "Select a note", systemImage: model.destination == .inbox ? "tray" : "doc.text")
                .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("macEmptyEditor")
        }
    }
    private func toastView(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
            Text(text).font(.system(size: 13.5))
            if model.canUndo {
                Button { model.undo() } label: {
                    HStack(spacing: 6) {
                        Text("Undo").font(.system(size: 13.5, weight: .bold)).foregroundStyle(MacDesktopStyle.icon)
                        Text("⌘Z").font(.system(size: 11.5)).padding(.horizontal, 5).frame(height: 20)
                            .foregroundStyle(MacDesktopStyle.secondary).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.16)))
                    }.padding(.horizontal, 10).frame(height: 32)
                }.buttonStyle(.plain).accessibilityIdentifier("macUndoCapture")
            }
            if let url = model.toastNoteURL {
                Button("Open") { model.openURL(url); model.toast = nil }.buttonStyle(.plain).font(.system(size: 13.5, weight: .bold))
                    .padding(.leading, 4).padding(.trailing, 12).frame(height: 32).accessibilityIdentifier("macOpenFiledCapture")
            }
        }.padding(.leading, 16).padding(.trailing, 6).frame(height: 44).background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12))).accessibilityElement(children: .contain).accessibilityIdentifier("macOutcomeToast")
    }
    private func openDocumentPath(_ path: String) {
        guard let url = VaultPathResolver(vaultRootURL: model.vaultURL).noteURL(forVaultRelativePath: path) else { return }
        model.openURL(url)
    }
    private func handleCommand(_ action: String) {
        switch action {
        case "capture": model.select(.capture)
        case "daily": model.openToday()
        case "inbox": model.select(.inbox)
        case "all": model.select(.all)
        case "sidebar":
            if (window?.contentView?.bounds.width ?? 0) < 1100 { sidebarOverlay.toggle() } else { sidebarVisible.toggle() }
        case "inspector": inspectorVisible.toggle()
        case "focus": focusMode.toggle()
        case "folder": beginNewFolder()
        case "back": model.navigateHistory(back: true)
        case "forward": model.navigateHistory(back: false)
        case "file": if model.destination == .capture { model.fileCapture() }
        case "discardDraft": if model.destination == .capture { model.discardDraft() }
        case "undo": if model.canUndo { model.undo() } else { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
        case "reveal": if let note = model.selectedNote { NSWorkspace.shared.activateFileViewerSelecting([note.fileURL]) }
        case "duplicate": if let note = model.currentLibraryNote { model.duplicate(note) }
        case "copyLink":
            if let path = model.selectedNote.flatMap({ model.store.vaultRelativePath(for: $0.fileURL) }), let url = NotoDeepLink.webURL(vaultRelativePath: path) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        case "discardOrTrash":
            if model.destination == .capture { model.discardDraft() }
            else if let note = model.currentLibraryNote { trash(note) }
        case "previousDay": adjacentDay(-1)
        case "nextDay": adjacentDay(1)
        default: break
        }
    }
    private func newNoteCommand() {
        model.palette = nil
        if model.destination == .capture || model.destination == .inbox { model.select(.capture) } else { model.createNote() }
    }
    private func beginNewFolder() { folderName = ""; showNewFolder = true }
    private func createFolder() {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { model.error = "Choose a folder name without a slash."; return }
        let directory: URL
        if case .folder(let url) = model.destination { directory = url } else { directory = model.vaultURL }
        let folderStore = MarkdownNoteStore(directoryURL: directory, vaultRootURL: model.vaultURL, autoload: false)
        let folder = folderStore.createFolder(name: name)
        model.expandedFolders.insert(directory); model.select(.folder(folder.folderURL)); model.scheduleRefresh()
    }
    private func adjacentDay(_ step: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let date = model.selectedNote.flatMap { f.date(from: $0.fileURL.deletingPathExtension().lastPathComponent) } ?? Date()
        guard let next = Calendar.current.date(byAdding: .day, value: step, to: date) else { return }
        let service = DailyNoteService(vaultRootURL: model.vaultURL)
        let result = service.ensure(date: next)
        model.open(MarkdownNote(id: result.id, fileURL: result.fileURL, title: result.displayTitle, modifiedDate: result.modifiedDate))
        model.scheduleRefresh()
    }
    private func pin(_ note: VaultLibraryNote) {
        if model.selectedNote?.id == note.id {
            NotificationCenter.default.post(name: MacDesktopModel.editorAction, object: model, userInfo: ["action": "pin", "noteID": note.id]); return
        }
        guard let content = CoordinatedFileManager.readString(from: note.fileURL) else { return }
        let updated = NoteFrontmatter.setting("pinned", to: note.isPinned ? "false" : "true", in: content)
        if CoordinatedFileManager.writeString(updated, to: note.fileURL) { model.scheduleRefresh() }
        else { model.error = "The note could not be pinned." }
    }
    private func trash(_ note: VaultLibraryNote) {
        if model.selectedNote?.id == note.id {
            NotificationCenter.default.post(name: MacDesktopModel.editorAction, object: model, userInfo: ["action": "trash", "noteID": note.id]); return
        }
        do { model.deletingNoteID = note.id; try FileManager.default.trashItem(at: note.fileURL, resultingItemURL: nil); if model.selectedNote?.id == note.id { model.selectedNote = nil }; model.scheduleRefresh() }
        catch { model.error = error.localizedDescription }
    }
}

struct MacDesktopWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView { Reader(onWindow: { window = $0 }) }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Reader: NSView {
        var onWindow: (NSWindow?) -> Void
        init(onWindow: @escaping (NSWindow?) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titleVisibility = .hidden; window?.titlebarAppearsTransparent = true
            window?.styleMask.insert(.fullSizeContentView)
            window?.isMovableByWindowBackground = true
            DispatchQueue.main.async {
                if let width = NotoPreviewConfiguration.windowWidth {
                    self.window?.setContentSize(NSSize(width: width, height: NotoPreviewConfiguration.windowHeight ?? 900))
                }
                self.onWindow(self.window)
            }
        }
    }
}

/// Actual AppKit window buttons, hosted in the design's inset title-bar row.
struct MacDesktopWindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Controls() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Controls: NSView {
        private var controls: [NSButton] = []
        override init(frame: NSRect) {
            super.init(frame: frame)
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in types.enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
                button.frame.origin = NSPoint(x: index * 20, y: 1)
                button.setAccessibilityIdentifier(["macWindowClose", "macWindowMinimize", "macWindowZoom"][index])
                addSubview(button); controls.append(button)
            }
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for control in controls { control.target = window }
        }
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
#endif
