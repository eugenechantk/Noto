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
    /// False when the file is an iCloud placeholder: the download is started
    /// instead, and the caller should not show a player that cannot play.
    static func prepare(_ url: URL) -> Bool {
        guard CoordinatedFileManager.isDownloaded(at: url) else {
            CoordinatedFileManager.startDownloading(at: url)
            playbackLogger.info("video not downloaded yet; started download \(url.lastPathComponent, privacy: .public)")
            return false
        }
        // Play with sound even when the ring/silent switch is on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return true
    }

    static func makeController(for url: URL) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.view.accessibilityIdentifier = "videoPlayer"
        return controller
    }

    /// Presents the player over `presenter` and starts playback.
    static func present(_ url: URL, from presenter: UIViewController) {
        guard prepare(url) else { return }
        let controller = makeController(for: url)
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: true) {
            controller.player?.play()
        }
        playbackLogger.info("playing \(url.lastPathComponent, privacy: .public)")
    }
}

/// SwiftUI entry point (for `.fullScreenCover`): the same player, playing on appear.
struct VideoPlayerScreen: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = VideoPlayback.makeController(for: url)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}
#endif
