#if os(macOS)
import Foundation
import NotoVault
import SwiftUI

struct EditorNavigationChrome: ViewModifier {
    let mode: EditorChromeMode
    let title: String
    let vaultRootURL: URL
    let noteFileURL: URL
    let statusCount: WordCounter.Count
    var leadingControls: EditorLeadingChromeControls = .none
    var canNavigateBack = false
    var canNavigateForward = false
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?
    var onOpenTodayNote: (() -> Void)?
    var onTapBreadcrumbLevel: ((URL) -> Void)?
    var onMoveRequested: () -> Void
    var onDeleteRequested: () -> Void
    var onSearchRequested: () -> Void
    var onShowProperties: (() -> Void)?
    var propertyCount: Int = 0
    var showsScrolledTitle = false
    var scrolledTitle = ""

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // v2 design (NotoMac): the detail buttons live in the NATIVE window toolbar so the
    // top bar spans the window, the sidebar is full-height (no floating gap), the traffic
    // lights are placed natively in the sidebar's top, and everything aligns — matching
    // the macOS apps (Notes/Mail). The native split provides the sidebar-toggle.
    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .macInContent:
            // Keep a (near-empty) native toolbar so the unified window chrome stays:
            // full-height source-list sidebar + traffic lights placed in the sidebar
            // top. The editor's own controls render IN-CONTENT below the title-bar
            // strip (via safeAreaInset), so they follow the editor's right edge and
            // align with the chat sidebar's header (also below the strip).
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    inContentTopBar
                }
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                .toolbarBackground(.hidden, for: .windowToolbar)
        case .macToolbar, .splitClean:
            nativeToolbarBody(content)
        case .compactNavigation:
            content
        }
    }

    // MARK: In-content top bar (when a chat sidebar is docked beside the editor)

    private var inContentTopBar: some View {
        ZStack {
            // Center: scrolled title.
            Text(scrolledTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotoTheme.head)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 360)
                .opacity(showsScrolledTitle ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showsScrolledTitle)
                .accessibilityIdentifier("editor_scrolled_title")

            HStack(spacing: 2) {
                if let onToggleSidebar = leadingControls.onToggleSidebar,
                   let sidebarSystemImage = leadingControls.sidebarSystemImage {
                    inContentButton(sidebarSystemImage, id: "sidebar_toggle_button",
                                    label: leadingControls.sidebarAccessibilityLabel ?? "Toggle Sidebar",
                                    action: onToggleSidebar)
                }
                inContentButton("chevron.left", id: "note_history_back_button", label: "Back") {
                    onNavigateBack?()
                }
                .disabled(!canNavigateBack)

                Spacer(minLength: 0)

                inContentButton("magnifyingglass", id: "editor_search_button", label: "Search in Note",
                                shortcut: ("f", [.command]), action: onSearchRequested)
                inContentMoreMenu
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(NotoTheme.background)
    }

    private func inContentButton(
        _ systemImage: String,
        id: String,
        label: String,
        shortcut: (Character, EventModifiers)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NotoTheme.head)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .help(label)
        if let shortcut {
            return AnyView(button.keyboardShortcut(KeyEquivalent(shortcut.0), modifiers: shortcut.1))
        }
        return AnyView(button)
    }

    private var inContentMoreMenu: some View {
        Menu {
            moreMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NotoTheme.head)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("more_menu_button")
        .accessibilityLabel("More")
        .help("More")
    }

    private func nativeToolbarBody(_ content: Content) -> some View {
            content
                .navigationTitle("")
                .toolbar {
                    // LEADING: sidebar toggle + back (matches the iPad editor chrome).
                    ToolbarItemGroup(placement: .navigation) {
                        if let onToggleSidebar = leadingControls.onToggleSidebar,
                           let sidebarSystemImage = leadingControls.sidebarSystemImage {
                            Button(action: onToggleSidebar) {
                                Image(systemName: sidebarSystemImage)
                            }
                            .accessibilityIdentifier("sidebar_toggle_button")
                            .accessibilityLabel(leadingControls.sidebarAccessibilityLabel ?? "Toggle Sidebar")
                            .help(leadingControls.sidebarAccessibilityLabel ?? "Toggle Sidebar")
                        }

                        Button {
                            onNavigateBack?()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!canNavigateBack)
                        .accessibilityIdentifier("note_history_back_button")
                        .accessibilityLabel("Back")
                        .help("Back")
                    }

                    // CENTER: the note title rises into the top bar once the document
                    // title scrolls out of view (matches the iPad scrolled top-bar state).
                    ToolbarItem(placement: .principal) {
                        Text(scrolledTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NotoTheme.head)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 360)
                            .opacity(showsScrolledTitle ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: showsScrolledTitle)
                            .accessibilityIdentifier("editor_scrolled_title")
                    }
                    .plainToolbarBackground()

                    // TRAILING: search + more.
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: onSearchRequested) {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityIdentifier("editor_search_button")
                        .accessibilityLabel("Search in Note")
                        .help("Search in Note")
                        .keyboardShortcut("f", modifiers: [.command])

                        moreMenu
                    }
                }
                // Hide the toolbar's own material so the detail header shows the editor's
                // scroll-view background (#0E1116) — not a darker translucent bar — while
                // the sidebar column keeps its native Liquid Glass under the toolbar.
                .toolbarBackground(.hidden, for: .windowToolbar)
    }

    @ViewBuilder
    private var moreMenuItems: some View {
            if let onShowProperties {
                Button(action: onShowProperties) {
                    Text("Properties")
                    Text("\(propertyCount) \(propertyCount == 1 ? "property" : "properties")")
                    Image(systemName: "info.circle")
                }
                .accessibilityIdentifier("properties_menu_item")

                Divider()
            }

            Button(action: onMoveRequested) {
                Label("Move Note", systemImage: "folder")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .accessibilityIdentifier("move_note_menu_item")

            Button(role: .destructive, action: onDeleteRequested) {
                Label("Delete Note", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            Divider()

            Text("\(formatted(statusCount.words)) words")
                .accessibilityIdentifier("editor_word_count_menu_item")
            Text("\(formatted(statusCount.characters)) characters")
                .accessibilityIdentifier("editor_character_count_menu_item")
    }

    /// Native-toolbar variant of the more menu (used by `.macToolbar`).
    private var moreMenu: some View {
        Menu {
            moreMenuItems
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier("more_menu_button")
        .accessibilityLabel("More")
        .help("More")
    }

    private func formatted(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private extension ToolbarContent {
    /// Removes the toolbar item's shared glass/pill background (macOS 26+) so the
    /// scrolled title reads as bare text. Passthrough on earlier macOS.
    @ToolbarContentBuilder
    func plainToolbarBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
#endif
