#if os(iOS)
import AVKit
import SwiftUI
import UIKit
import os.log

private let playbackLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "VideoPlayback")

/// Full-screen playback for a video file in the vault — the standard
/// `AVPlayerViewController` (scrubber, AirPlay, picture-in-picture, Done), the
/// same thing Photos and Messages show. Used by the editor's video thumbnails
/// and by Digest cards.
enum VideoPlayback {
    /// What to play: the media mirror's stream first, the downloaded file as the
    /// fallback (see `MediaSource.videoSource`). Nil when there is no mirror and
    /// the file is still an iCloud placeholder — then there is nothing to show.
    static func prepare(_ url: URL) -> MediaSource.VideoSource? {
        guard let source = MediaSource.videoSource(for: url) else {
            playbackLogger.info("video not downloaded yet and no mirror; started download \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        if !source.primary.isFileURL {
            playbackLogger.info("streaming \(url.lastPathComponent, privacy: .public) from the media mirror")
        }
        // Play with sound even when the ring/silent switch is on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return source
    }

    static func makeController(for source: MediaSource.VideoSource) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = MirroredPlayer(source: source)
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.view.accessibilityIdentifier = "videoPlayer"
        return controller
    }

    /// Presents the player over `presenter` and starts playback.
    static func present(_ url: URL, from presenter: UIViewController) {
        guard let source = prepare(url) else { return }
        let controller = makeController(for: source)
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: true) {
            controller.player?.play()
        }
        playbackLogger.info("playing \(url.lastPathComponent, privacy: .public)")
    }
}

/// SwiftUI entry point (for `.fullScreenCover`): the same player, playing on appear.
struct VideoPlayerScreen: UIViewControllerRepresentable {
    let source: MediaSource.VideoSource

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = VideoPlayback.makeController(for: source)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}
/// Plays `source.primary` (the mirror's stream) and, if that item fails — not
/// uploaded yet, offline — switches to `source.fallback` (the vault file).
final class MirroredPlayer: AVPlayer {
    private var fallback: URL?
    private var statusObservation: NSKeyValueObservation?

    convenience init(source: MediaSource.VideoSource) {
        self.init(playerItem: AVPlayerItem(url: source.primary))
        fallback = source.fallback
        statusObservation = currentItem?.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.switchToFallback() }
        }
    }

    private func switchToFallback() {
        statusObservation = nil
        guard let fallback else {
            playbackLogger.error("mirror stream failed and the file is not on this device")
            return
        }
        self.fallback = nil
        playbackLogger.info("mirror stream failed; playing \(fallback.lastPathComponent, privacy: .public) from the device")
        replaceCurrentItem(with: AVPlayerItem(url: fallback))
        play()
    }
}
#endif
