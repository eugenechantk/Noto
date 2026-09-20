import NotoLinkPreview
import SwiftUI
import UIKit

/// Splits a capture body into the link its first line carries (if the line is
/// nothing but a web link — bare or `[title](url)`) and whatever text follows,
/// so the Digest card can show the same preview card the editor shows.
struct DigestLinkCardSplit: Equatable {
    let url: URL
    /// Body text after the link line, trimmed; nil when the capture is only the link.
    let remainder: String?

    /// nil when the body does not start with a link-only line.
    static func split(body: String) -> DigestLinkCardSplit? {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first,
              let url = LinkPreviewDetector.url(inLine: String(first)) else {
            return nil
        }
        let rest = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DigestLinkCardSplit(url: url, remainder: rest.isEmpty ? nil : rest)
    }
}

/// The editor's `LinkPreviewCardView`, hosted in SwiftUI for the Digest card.
/// Loading → loaded → failed states come from the shared `LinkPreviewService`;
/// the view re-configures itself when the service announces a change for its URL.
struct DigestLinkCard: UIViewRepresentable {
    let url: URL
    var onOpen: (() -> Void)?

    func makeUIView(context: Context) -> LinkPreviewCardView {
        let view = LinkPreviewCardView(frame: .zero)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.accessibilityIdentifier = "digestLinkCard"
        context.coordinator.observe(view: view, url: url)
        return view
    }

    func updateUIView(_ view: LinkPreviewCardView, context: Context) {
        view.onOpen = onOpen ?? { UIApplication.shared.open(url) }
        context.coordinator.observe(view: view, url: url)
        context.coordinator.refresh()
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LinkPreviewCardView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? UIView.noIntrinsicMetric, height: LinkPreviewCardLayout.defaultHeight)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private weak var view: LinkPreviewCardView?
        private var url: URL?
        private var token: NSObjectProtocol?

        func observe(view: LinkPreviewCardView, url: URL) {
            self.view = view
            guard self.url != url else { return }
            self.url = url
            if token == nil {
                token = NotificationCenter.default.addObserver(
                    forName: LinkPreviewService.didChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let self,
                          let changed = notification.userInfo?[LinkPreviewService.urlUserInfoKey] as? URL,
                          changed == self.url else { return }
                    MainActor.assumeIsolated { self.refresh() }
                }
            }
            refresh()
        }

        func refresh() {
            guard let view, let url else { return }
            let state = LinkPreviewSupport.service.state(for: url)
            view.configure(content: LinkPreviewCardContent.make(url: url, state: state))
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
