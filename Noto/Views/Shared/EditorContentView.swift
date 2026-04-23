import SwiftUI
import NotoVault

struct EditorContentView: View {
    @Bindable var session: NoteEditorSession
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?

    var body: some View {
        Group {
            if session.downloadFailed {
                ContentUnavailableView(
                    "Download Failed",
                    systemImage: "exclamationmark.icloud",
                    description: Text("Could not download this note from iCloud. Check your connection and try again.")
                )
            } else if session.isDownloading {
                downloadingView
            } else {
                editorBody
            }
        }
        .background(AppTheme.background)
    }

    private var downloadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Downloading from iCloud...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            if session.pendingRemoteSnapshot != nil {
                RemoteUpdateBanner(
                    onKeepMine: session.discardRemoteConflict,
                    onReload: session.reloadRemoteSnapshot
                )
            }
            TextKit2EditorView(
                text: $session.content,
                autoFocus: session.isNew,
                onTextChange: session.handleEditorChange,
                pageMentionProvider: pageMentionProvider,
                onOpenDocumentLink: onOpenDocumentLink
            )
        }
        .background(AppTheme.background)
        #if os(iOS)
        .ignoresSafeArea(edges: [.top, .bottom])
        #endif
    }
}

private struct RemoteUpdateBanner: View {
    var onKeepMine: () -> Void
    var onReload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Updated in another window", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Keep Mine", action: onKeepMine)
            Button("Reload", action: onReload)
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 1)
        }
    }
}
