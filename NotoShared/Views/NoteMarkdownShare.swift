import Foundation
import NotoVault
import Observation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension NoteEditorSession {
    var markdownShare: NoteMarkdownShare? {
        guard hasLoaded, !isDownloading, !downloadFailed, !isDeleting else { return nil }
        return NoteMarkdownShare(markdown: latestEditorText)
    }
}

/// Shared by editor toolbars and menus on both platforms.
struct NoteMarkdownShareLink: View {
    let item: NoteMarkdownShare?
    var title = "Share"
    @State private var isPreparing = false
    #if os(iOS)
    @Environment(NoteSharePresentation.self) private var presentation: NoteSharePresentation?
    #elseif os(macOS)
    @State private var shareFailed = false
    @State private var anchor: NSView?
    @State private var picker: NSSharingServicePicker?
    #endif

    var body: some View {
        Button(action: share) {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .disabled(item == nil || isPreparing)
        .accessibilityLabel("Share note")
        #if os(macOS)
        .background(NoteShareAnchor(view: $anchor))
        .alert("Could not share note", isPresented: $shareFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The note could not be read. Try again after it finishes downloading.")
        }
        #endif
    }

    private func share() {
        guard let item, !isPreparing else { return }
        isPreparing = true
        #if os(iOS)
        let presentation = presentation
        #endif
        Task { @MainActor in
            defer { isPreparing = false }
            do {
                let text = try await item.loadText()
                #if os(iOS)
                presentation?.sharedText = SharedNoteText(text: text)
                #elseif os(macOS)
                guard let view = anchor?.window != nil ? anchor : NSApp.keyWindow?.contentView else {
                    shareFailed = true
                    return
                }
                // NSString-compatible content keeps this a text share. A data
                // representation makes some destinations treat Markdown as a file.
                let sharingPicker = NSSharingServicePicker(items: [text])
                picker = sharingPicker
                sharingPicker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
                #endif
            } catch {
                #if os(iOS)
                presentation?.shareFailed = true
                #else
                shareFailed = true
                #endif
            }
        }
    }
}

#if os(iOS)
/// The editor root owns presentation so closing a More/context menu cannot
/// remove the share sheet's state or presenting view.
@MainActor @Observable
private final class NoteSharePresentation {
    var sharedText: SharedNoteText?
    var shareFailed = false
}

private struct NoteSharePresentationHost: ViewModifier {
    @State private var presentation = NoteSharePresentation()

    func body(content: Content) -> some View {
        @Bindable var presentation = presentation
        content
            .environment(presentation)
            .sheet(item: $presentation.sharedText) { payload in
                NoteTextActivitySheet(text: payload.text)
            }
            .alert("Could not share note", isPresented: $presentation.shareFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The note could not be read. Try again after it finishes downloading.")
            }
    }
}

private struct SharedNoteText: Identifiable {
    let id = UUID()
    let text: String
}

private struct NoteTextActivitySheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
private struct NoteShareAnchor: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView()
        DispatchQueue.main.async { view = anchor }
        return anchor
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
#endif

extension View {
    @ViewBuilder
    func noteSharing() -> some View {
        #if os(iOS)
        modifier(NoteSharePresentationHost())
        #else
        self
        #endif
    }
}
