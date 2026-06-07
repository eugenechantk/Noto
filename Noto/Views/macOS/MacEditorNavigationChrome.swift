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
    func body(content: Content) -> some View {
        if showsEditorToolbar {
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
        } else {
            content
        }
    }

    private var moreMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier("more_menu_button")
        .accessibilityLabel("More")
        .help("More")
    }

    private var showsEditorToolbar: Bool {
        switch mode {
        case .macToolbar, .splitClean:
            true
        case .compactNavigation:
            false
        }
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
