#if os(iOS)
import AVKit
import UIKit
import os.log

private let inlineLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "InlineVideoPlayer")

/// Plays one video inline in the editor, in place of its thumbnail, using the
/// native `AVPlayerViewController` embedded as a child controller: the
/// standard inline controls (play/pause, scrubber, mute) and its own
/// full-screen button. At most one plays at a time.
///
/// The editor keeps it glued to its line (`follow(frame:)` on every overlay
/// refresh) and stops it when the line leaves the screen, another video
/// starts, or the note closes. While the player is full screen none of that
/// applies — the editor underneath is not what the user is looking at.
@MainActor
final class InlineVideoPlayer: NSObject, AVPlayerViewControllerDelegate {
    private(set) var url: URL?
    private(set) var controller: AVPlayerViewController?
    /// Set by the full-screen delegate callbacks; while true, `follow` and `stop` are no-ops.
    var isFullScreen = false

    var isActive: Bool { controller != nil }

    /// Starts `url` inline over `frame` (in `container`'s coordinates),
    /// replacing whatever was playing.
    func play(_ url: URL, frame: CGRect, in container: UIView, parent: UIViewController) {
        stop()
        guard VideoPlayback.prepare(url) else { return }

        let controller = VideoPlayback.makeController(for: url)
        controller.delegate = self
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        controller.view.layer.cornerRadius = MarkdownVisualSpec.imagePreviewCornerRadius
        controller.view.layer.masksToBounds = true
        controller.view.accessibilityIdentifier = "editor_inline_video_player"

        parent.addChild(controller)
        controller.view.frame = frame
        container.addSubview(controller.view)
        controller.didMove(toParent: parent)

        self.controller = controller
        self.url = url
        controller.player?.play()
        inlineLogger.info("inline playback \(url.lastPathComponent, privacy: .public)")
    }

    /// Keeps the player on its line as the note scrolls or reflows.
    func follow(frame: CGRect) {
        guard let view = controller?.view, !isFullScreen else { return }
        if view.frame != frame { view.frame = frame }
        view.superview?.bringSubviewToFront(view)
    }

    /// Pauses and removes the player; a no-op while it is full screen.
    func stop() {
        guard let controller, !isFullScreen else { return }
        controller.player?.pause()
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        self.controller = nil
        self.url = nil
    }

    // MARK: AVPlayerViewControllerDelegate

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        isFullScreen = true
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isFullScreen = false
        }
    }
}
#endif
