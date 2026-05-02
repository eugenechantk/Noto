import SwiftUI
import NotoVault

#if os(iOS)
import UIKit
#endif

struct EditorContentView: View {
    @Bindable var session: NoteEditorSession
    @Binding var isFindVisible: Bool
    @Binding var findQuery: String
    @Binding var findNavigationRequest: EditorFindNavigationRequest?
    @Binding var findStatus: EditorFindStatus
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    var onOpenDocumentLinkInNewWindow: ((String) -> Void)?
    var onFindNavigate: (EditorFindNavigationDirection) -> Void
    var scrollRestorationID: String?
    var initialContentOffsetY: CGFloat?
    var onContentOffsetYChange: ((CGFloat) -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            } else if !session.hasLoaded {
                loadingView
            } else {
                editorBody
            }
        }
        .background(AppTheme.background)
        .onReceive(NotificationCenter.default.publisher(for: NoteEditorCommands.closeFind)) { _ in
            guard isFindVisible else { return }
            closeFind()
        }
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

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading note...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }

    private var editorBody: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    if session.pendingRemoteSnapshot != nil {
                        RemoteUpdateBanner(
                            onKeepMine: session.discardRemoteConflict,
                            onReload: session.reloadRemoteSnapshot
                        )
                    }
                    editorView
                }

                if isFindVisible {
                    EditorFindBar(
                        query: $findQuery,
                        status: findStatus,
                        onNavigate: onFindNavigate,
                        onClose: closeFind
                    )
                    .padding(.top, findBarTopPadding(safeAreaTop: geometry.safeAreaInsets.top))
                    .padding(.trailing, findBarTrailingPadding)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.18, anchor: .topTrailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing))
                    ))
                    .zIndex(1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(AppTheme.background)
        #if os(iOS)
        .ignoresSafeArea(edges: [.top, .bottom])
        #endif
    }

    @ViewBuilder
    private var editorView: some View {
        #if os(iOS)
        TextKit2EditorView(
            text: $session.content,
            autoFocus: session.isNew,
            onTextChange: session.handleEditorChange,
            vaultRootURL: session.store.vaultRootURL,
            onImportImageData: session.importImageAttachment(data:suggestedFilename:),
            pageMentionProvider: pageMentionProvider,
            onOpenDocumentLink: onOpenDocumentLink,
            isFindVisible: isFindVisible,
            findQuery: findQuery,
            findNavigationRequest: findNavigationRequest,
            onFindStatusChange: handleFindStatusChange,
            onCloseFind: closeFind,
            scrollRestorationID: scrollRestorationID,
            initialContentOffsetY: initialContentOffsetY,
            onContentOffsetYChange: onContentOffsetYChange
        )
        #elseif os(macOS)
        TextKit2EditorView(
            text: $session.content,
            autoFocus: session.isNew,
            onTextChange: session.handleEditorChange,
            vaultRootURL: session.store.vaultRootURL,
            onImportImageFile: session.importImageAttachment(fileURL:),
            pageMentionProvider: pageMentionProvider,
            onOpenDocumentLink: onOpenDocumentLink,
            onOpenDocumentLinkInNewWindow: onOpenDocumentLinkInNewWindow,
            isFindVisible: isFindVisible,
            findQuery: findQuery,
            findNavigationRequest: findNavigationRequest,
            onFindStatusChange: handleFindStatusChange,
            onCloseFind: closeFind
        )
        #endif
    }

    private func handleFindStatusChange(_ status: EditorFindStatus) {
        DispatchQueue.main.async {
            findStatus = status
        }
    }

    private var findBarTrailingPadding: CGFloat {
        #if os(iOS)
        horizontalSizeClass == .regular ? 10 : 16
        #else
        16
        #endif
    }

    private func findBarTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        #if os(iOS)
        let topSafeArea = max(safeAreaTop, activeWindowSafeAreaTop)
        let topBarHeight: CGFloat = horizontalSizeClass == .regular ? 54 : 44
        let gapBelowTopBar: CGFloat = horizontalSizeClass == .regular ? 4 : 9
        return topSafeArea + topBarHeight + gapBelowTopBar
        #else
        return 10
        #endif
    }

    #if os(iOS)
    private var activeWindowSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
    #endif

    private func closeFind() {
        withAnimation(.easeInOut(duration: 0.14)) {
            isFindVisible = false
            findQuery = ""
            findStatus = EditorFindStatus()
            findNavigationRequest = nil
        }
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
