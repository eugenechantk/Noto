#if os(macOS)
import SwiftUI
import NotoVault

struct MacDesktopCommandState {
    var sidebar: Binding<Bool>
    var list: Binding<Bool>
    var inspector: Binding<Bool>
    var focus: Binding<Bool>
    var sortOrder: Binding<VaultLibrarySortOrder>
    var includeSubfolders: Binding<Bool>
    var isCapture: Bool
    var canActOnNote: Bool
    var canFileCapture: Bool
}
private struct MacDesktopCommandStateKey: FocusedValueKey { typealias Value = MacDesktopCommandState }
extension FocusedValues {
    var macDesktopState: MacDesktopCommandState? {
        get { self[MacDesktopCommandStateKey.self] }
        set { self[MacDesktopCommandStateKey.self] = newValue }
    }
}

struct MacDesktopCommands: Commands {
    @FocusedValue(\.macDesktopState) private var state
    static let action = Notification.Name("NotoDesktop.action")
    @Environment(\.openWindow) private var openWindow
    private func send(_ action: String) {
        NotificationCenter.default.post(name: Self.action, object: NotoCommandTarget.activeWindow, userInfo: ["action": action])
    }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { NotificationCenter.default.post(name: NotoAppCommands.createNote, object: NotoCommandTarget.activeWindow) }.keyboardShortcut("n")
            Button("New Folder…") { send("folder") }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Window") { openWindow(id: "main", value: UUID().uuidString) }.keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Search…") { NotificationCenter.default.post(name: NotoAppCommands.showSearch, object: NotoCommandTarget.activeWindow) }.keyboardShortcut("k")
            Button("Quick Open…") { NotificationCenter.default.post(name: NotoAppCommands.showSearch, object: NotoCommandTarget.activeWindow) }.keyboardShortcut("o")
            Button("Move To…") { NoteEditorCommands.requestShowMoveNote() }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(state?.canActOnNote != true)
            Button("Duplicate") { send("duplicate") }.keyboardShortcut("d").disabled(state?.canActOnNote != true)
            Button("Reveal in Finder") { send("reveal") }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(state?.canActOnNote != true)
            Button("Copy Link") { send("copyLink") }.keyboardShortcut("c", modifiers: [.command, .control]).disabled(state?.canActOnNote != true)
            Divider()
            Button("File Capture to Inbox") { send("file") }.keyboardShortcut(.return, modifiers: .command).disabled(state?.canFileCapture != true)
            Button(state?.isCapture == true ? "Discard Capture" : "Move to Trash") { send("discardOrTrash") }.keyboardShortcut(.delete, modifiers: .command).disabled(state?.isCapture != true && state?.canActOnNote != true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { send("undo") }.keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find in Note…") { NoteEditorCommands.requestShowFind() }.keyboardShortcut("f")
        }
        CommandGroup(after: .toolbar) {
            Toggle("Show Sidebar", isOn: state?.sidebar ?? .constant(false)).keyboardShortcut("s", modifiers: [.command, .control])
            Toggle("Show Note List", isOn: state?.list ?? .constant(true)).keyboardShortcut("l", modifiers: [.command, .option])
            Toggle("Show Inspector", isOn: state?.inspector ?? .constant(false)).keyboardShortcut("i", modifiers: [.command, .option]).disabled(state?.isCapture == true)
            Menu("Sort By") { Picker("Sort By", selection: state?.sortOrder ?? .constant(.newest)) { ForEach(VaultLibrarySortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden() }
            Toggle("Include Subfolders", isOn: state?.includeSubfolders ?? .constant(false))
            Toggle("Focus Mode", isOn: state?.focus ?? .constant(false)).keyboardShortcut("f", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Capture") { send("capture") }.keyboardShortcut("1")
            Button("Daily Notes") { send("daily") }.keyboardShortcut("2")
            Button("Inbox") { send("inbox") }.keyboardShortcut("3")
            Button("All Notes") { send("all") }.keyboardShortcut("4")
            Divider()
            Button("Today") { send("daily") }.keyboardShortcut("t")
            Button("Previous Day") { send("previousDay") }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Next Day") { send("nextDay") }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Divider()
            Button("Back") { send("back") }.keyboardShortcut("[")
            Button("Forward") { send("forward") }.keyboardShortcut("]")
        }
        CommandMenu("Format") {
            Button("Bold") { NoteEditorCommands.requestToggleBold() }.keyboardShortcut("b")
            Button("Italic") { NoteEditorCommands.requestToggleItalic() }.keyboardShortcut("i")
            Button("Strikethrough") { NoteEditorCommands.requestToggleStrikethrough() }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Link…") { NoteEditorCommands.requestToggleHyperlink() }.keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
#endif
