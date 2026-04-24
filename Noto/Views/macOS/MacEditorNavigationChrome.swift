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
    var canNavigateBack = false
    var canNavigateForward = false
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?
    var onOpenTodayNote: (() -> Void)?
    var onTapBreadcrumbLevel: ((URL) -> Void)?
    var onDeleteRequested: () -> Void
    var onSearchRequested: () -> Void

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .toolbar {
                if showsEditorToolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button {
                            onNavigateBack?()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!canNavigateBack)
                        .accessibilityIdentifier("note_history_back_button")
                        .accessibilityLabel("Back")
                        .help("Back")

                        Button {
                            onNavigateForward?()
                        } label: {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!canNavigateForward)
                        .accessibilityIdentifier("note_history_forward_button")
                        .accessibilityLabel("Forward")
                        .help("Forward")
                    }

                    if let onOpenTodayNote {
                        ToolbarItem(placement: .navigation) {
                            Button(action: onOpenTodayNote) {
                                Label("Today", systemImage: "calendar")
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("today_button")
                            .accessibilityLabel("Today")
                            .help("Today")
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        EditorBreadcrumbBar(
                            vaultRootURL: vaultRootURL,
                            noteFileURL: noteFileURL,
                            onTapLevel: onTapBreadcrumbLevel
                        )
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(action: onSearchRequested) {
                                Label("Search in Note", systemImage: "magnifyingglass")
                            }
                            .keyboardShortcut("f", modifiers: [.command])
                            .accessibilityIdentifier("search_in_note_menu_item")

                            Divider()

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
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("more_menu_button")
                        .accessibilityLabel("More")
                    }
                }
            }
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
#endif
