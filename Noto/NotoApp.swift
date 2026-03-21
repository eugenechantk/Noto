import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

@MainActor
private let sharedStore: MarkdownNoteStore = {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let vaultURL = documentsURL.appendingPathComponent("Noto")
    return MarkdownNoteStore(vaultURL: vaultURL)
}()

@main
struct NotoApp: App {
    var body: some Scene {
        WindowGroup {
            NoteListView(store: sharedStore)
        }
    }
}
