#if os(macOS)
import SwiftUI

struct EditorNavigationChrome: ViewModifier {
    let mode: EditorChromeMode
    let title: String
    var onDeleteRequested: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar {
                if case .macToolbar = mode {
                    ToolbarItem(placement: .automatic) {
                        Button(action: { NoteEditorCommands.requestToggleStrikethrough() }) {
                            Label("Strikethrough", systemImage: "strikethrough")
                        }
                        .accessibilityIdentifier("toggle_strikethrough_button")
                        .keyboardShortcut("x", modifiers: [.command, .shift])
                        .help("Strikethrough (Shift-Command-X)")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive, action: onDeleteRequested) {
                            Label("Delete Note", systemImage: "trash")
                        }
                        .accessibilityIdentifier("delete_note_button")
                        .keyboardShortcut(.delete, modifiers: [.command])
                    }
                }
            }
    }
}
#endif
