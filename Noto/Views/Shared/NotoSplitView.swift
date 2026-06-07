import SwiftUI

#if os(macOS)
import AppKit
#endif

struct NotoSplitView<SidebarContent: View, DetailContent: View, IOSDetailRoot: View, IOSDestination: View>: View {
    var store: MarkdownNoteStore
    @Binding var isSearchPresented: Bool
    @Binding var noteStackPath: [NoteStackEntry]
    var onSearchResult: (NoteSearchResult) -> Void
    var onOpenTodayNote: (() -> Void)? = nil
    var onCreateRootNote: (() -> Void)? = nil
    var onNativeStackChanged: (() -> Void)? = nil
    var onToggleSidebarCommand: (() -> Void)? = nil
    var onShowSearchCommand: (() -> Void)? = nil
    @ViewBuilder var sidebar: (_ searchText: Binding<String>, _ onToggleSidebar: @escaping () -> Void) -> SidebarContent
    @ViewBuilder var detail: (_ onToggleSidebar: @escaping () -> Void) -> DetailContent
    @ViewBuilder var iosDetailRoot: (_ onToggleSidebar: @escaping () -> Void) -> IOSDetailRoot
    @ViewBuilder var iosDestination: (_ entry: NoteStackEntry, _ onToggleSidebar: @escaping () -> Void) -> IOSDestination

    #if os(iOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    #else
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #endif
    @State private var sidebarSearchText = ""
    #if os(macOS)
    @State private var hostingWindow: NSWindow?
    #endif

    var body: some View {
        #if os(iOS)
        iOSSplitView
        #else
        macOSSplitView
        #endif
    }

    #if os(macOS)
    // v2 design (NotoMac): a floating Liquid Glass source-list sidebar + editor detail.
    // On macOS 26 (Tahoe) NavigationSplitView provides the floating glass sidebar,
    // resizable column, and correct traffic-light placement NATIVELY — we keep the
    // native split (a custom panel would draw over the traffic lights) and only theme
    // the content. (No backgroundExtensionEffect: with side-by-side native columns the
    // detail doesn't sit behind the sidebar, and the effect's mirrored blur read as a
    // distracting reflection at the top.)
    private var macOSSplitView: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar($sidebarSearchText, toggleSidebar)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
                    .environment(\.notoSidebarVisible, isSidebarVisible)
            } detail: {
                // Let the editor's NSView extend under the (material-hidden) window toolbar
                // so the top bar reads as the editor's own #0E1116 body color. The editor's
                // scroll view is pinned to the NSView safe-area guide (see the macOS editor
                // controller), so the text still clips below the toolbar and does NOT smear
                // behind the buttons on scroll. The sidebar column keeps its Liquid Glass.
                detail(toggleSidebar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NotoTheme.background)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .navigationSplitViewStyle(.balanced)
            .navigationTitle("Noto")

            if isSearchPresented {
                macOSSearchOverlay
            }
        }
        .background {
            WindowReader(window: $hostingWindow)
                .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.toggleSidebar)) { notification in
            guard handlesWindowScopedCommand(notification) else { return }
            onToggleSidebarCommand?()
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { notification in
            guard handlesWindowScopedCommand(notification) else { return }
            onShowSearchCommand?()
            showSearch()
        }
    }

    private var macOSSearchOverlay: some View {
        ZStack {
            MacSearchDismissBackdrop {
                isSearchPresented = false
            }
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("note_search_dismiss_overlay")

            NoteSearchSheet(
                rootStore: store,
                onClose: {
                    isSearchPresented = false
                }
            ) { result in
                onSearchResult(result)
            }
            .padding(.horizontal, 16)
            .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
        .zIndex(10)
    }
    #endif

    #if os(iOS)
    private var iOSSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar($sidebarSearchText, toggleSidebar)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            NavigationStack(path: $noteStackPath) {
                iosDetailRoot(toggleSidebar)
                    .navigationDestination(for: NoteStackEntry.self) { entry in
                        iosDestination(entry, toggleSidebar)
                    }
            }
            .background(AppTheme.background)
            .notoAppBottomToolbar(
                onOpenTodayNote: onOpenTodayNote,
                onSearch: { isSearchPresented.toggle() },
                onCreateRootNote: onCreateRootNote,
                isSidebarVisible: isSidebarVisible
            )
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $isSearchPresented) {
            NavigationStack {
                NoteSearchSheet(rootStore: store) { result in
                    onSearchResult(result)
                    columnVisibility = .detailOnly
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .noteSearchSheetPresentationStyle()
        }
        .background {
            AppTheme.background
                .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.toggleSidebar)) { _ in
            onToggleSidebarCommand?()
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { _ in
            onShowSearchCommand?()
            showSearch()
        }
        .onChange(of: noteStackPath) { _, _ in
            onNativeStackChanged?()
        }
    }
    #endif

    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    private func toggleSidebar() {
        if isSidebarVisible {
            columnVisibility = .detailOnly
        } else {
            columnVisibility = .all
        }
    }

    private func showSearch() {
        guard !isSearchPresented else { return }
        #if os(iOS)
        isSearchPresented = true
        #else
        columnVisibility = .all
        DispatchQueue.main.async {
            isSearchPresented = true
        }
        #endif
    }

    #if os(macOS)
    private func handlesWindowScopedCommand(_ notification: Notification) -> Bool {
        NotoCommandTarget.matches(notification, window: hostingWindow)
    }
    #endif
}

private extension View {
    @ViewBuilder
    func notoBackgroundExtension() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}

#if os(macOS)
private struct MacSearchDismissBackdrop: NSViewRepresentable {
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> DismissBackdropView {
        let view = DismissBackdropView(frame: .zero)
        view.onDismiss = onDismiss
        view.setAccessibilityIdentifier("note_search_dismiss_overlay")
        return view
    }

    func updateNSView(_ view: DismissBackdropView, context: Context) {
        view.onDismiss = onDismiss
    }

    final class DismissBackdropView: NSView {
        var onDismiss: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            onDismiss?()
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if window !== view.window {
                window = view.window
            }
        }
    }
}
#endif
