#if os(iOS)
import UIKit

/// The editor's image overlay. For an ordinary image it is inert
/// (`isUserInteractionEnabled = false`, so taps fall through to the text view
/// and place the caret, as before). For a local video it becomes a control:
/// tap plays, long-press hands the line back to editing — the same split the
/// link preview card uses.
final class MediaOverlayImageView: UIImageView {
    private(set) var videoURL: URL?
    var onPlay: ((URL) -> Void)?
    var onEdit: (() -> Void)?

    private let tapRecognizer = UITapGestureRecognizer()
    private let longPressRecognizer = UILongPressGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tapRecognizer.addTarget(self, action: #selector(handleTap))
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.minimumPressDuration = 0.4
        tapRecognizer.require(toFail: longPressRecognizer)
        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Pass the playable URL (see `VideoPosterRenderer.playableVideoURL`) or nil for an image.
    func configureVideo(_ url: URL?, location: Int) {
        videoURL = url
        let isVideo = url != nil
        // A video fills the editor width; a portrait one sits centred on black,
        // matching the player that replaces it on tap.
        backgroundColor = isVideo ? .black : AppTheme.uiCodeBackground
        isUserInteractionEnabled = isVideo
        isAccessibilityElement = isVideo
        accessibilityTraits = isVideo ? [.button, .startsMediaSession] : .image
        accessibilityLabel = isVideo ? "Play video" : nil
        accessibilityIdentifier = isVideo ? "editor_video_\(location)" : nil
    }

    @objc private func handleTap() {
        guard let videoURL else { return }
        onPlay?(videoURL)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, videoURL != nil else { return }
        onEdit?()
    }
}
#endif
