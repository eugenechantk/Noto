import NotoVault
import SwiftUI

/// The editor More menu shared by Noto and Noto 2. Keeping the menu in the
/// shared layer prevents the two apps from drifting as editor actions evolve.
struct NoteEditorActionsMenu: View {
    let statusCount: WordCounter.Count
    let onSearchRequested: () -> Void
    let onShowProperties: (() -> Void)?
    let propertyCount: Int
    let onMoveRequested: () -> Void
    let onDeleteRequested: () -> Void

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        Menu {
            Button(action: onSearchRequested) {
                Label("Search in Note", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .accessibilityIdentifier("search_in_note_menu_item")

            if let onShowProperties {
                Button(action: onShowProperties) {
                    Text("Properties")
                    Text("\(propertyCount) \(propertyCount == 1 ? "property" : "properties")")
                    Image(systemName: "info.circle")
                }
                .accessibilityIdentifier("properties_menu_item")
            }

            Divider()

            Button(action: onMoveRequested) {
                Label("Move Note", systemImage: "folder")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .accessibilityIdentifier("move_note_menu_item")

            Button(role: .destructive, action: onDeleteRequested) {
                Label("Delete Note", systemImage: "trash")
            }
            .accessibilityIdentifier("delete_note_menu_item")

            Divider()

            Text("\(formatted(statusCount.words)) words")
                .accessibilityIdentifier("editor_word_count_menu_item")
            Text("\(formatted(statusCount.characters)) characters")
                .accessibilityIdentifier("editor_character_count_menu_item")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .regular))
        }
        .accessibilityIdentifier("more_menu_button")
        .accessibilityLabel("More")
    }

    private func formatted(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
