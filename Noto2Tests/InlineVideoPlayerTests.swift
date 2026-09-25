import Foundation
import Testing
import UIKit
@testable import Noto2

/// Test case index
/// 1. playEmbedsNativePlayerOverTheThumbnail — the AVPlayerViewController becomes a child, sits in the container at the thumbnail frame, with native controls (SC-inline)
/// 2. followMovesThePlayerAndStopRemovesIt — frame follows the line; stop pauses and detaches everything (SC-inline)
/// 3. startingAnotherVideoReplacesTheFirst — only one inline player at a time (SC-inline)
/// 4. fullScreenPlayerIsNeitherMovedNorStopped — while full screen, follow/stop are ignored; stop works again after (SC-fullscreen)
@MainActor
struct InlineVideoPlayerTests {
    private func videoFile(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).mp4")
        try Data().write(to: url)
        return url
    }

    @Test func playEmbedsNativePlayerOverTheThumbnail() throws {
        let parent = UIViewController(), container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        let player = InlineVideoPlayer()
        let url = try videoFile("a")
        let frame = CGRect(x: 21, y: 539, width: 360, height: 203)

        player.play(url, frame: frame, in: container, parent: parent)

        let controller = try #require(player.controller)
        #expect(player.isActive)
        #expect(player.url == url)
        #expect(controller.parent === parent)
        #expect(controller.view.superview === container)
        #expect(controller.view.frame == frame)
        #expect(controller.showsPlaybackControls)
        #expect(controller.view.accessibilityIdentifier == "editor_inline_video_player")
    }

    @Test func followMovesThePlayerAndStopRemovesIt() throws {
        let parent = UIViewController(), container = UIView()
        let player = InlineVideoPlayer()
        player.play(try videoFile("a"), frame: CGRect(x: 0, y: 100, width: 300, height: 200), in: container, parent: parent)
        let controller = try #require(player.controller)

        player.follow(frame: CGRect(x: 0, y: 40, width: 300, height: 200))
        #expect(controller.view.frame.minY == 40)

        player.stop()
        #expect(!player.isActive)
        #expect(player.url == nil)
        #expect(controller.view.superview == nil)
        #expect(controller.parent == nil)
        #expect(parent.children.isEmpty)
    }

    @Test func startingAnotherVideoReplacesTheFirst() throws {
        let parent = UIViewController(), container = UIView()
        let player = InlineVideoPlayer()
        player.play(try videoFile("a"), frame: .init(x: 0, y: 0, width: 100, height: 100), in: container, parent: parent)
        let first = try #require(player.controller)
        let second = try videoFile("b")
        player.play(second, frame: .init(x: 0, y: 300, width: 100, height: 100), in: container, parent: parent)

        #expect(first.view.superview == nil)
        #expect(player.url == second)
        #expect(parent.children.count == 1)
        #expect(container.subviews.count == 1)
    }

    @Test func fullScreenPlayerIsNeitherMovedNorStopped() throws {
        let parent = UIViewController(), container = UIView()
        let player = InlineVideoPlayer()
        player.play(try videoFile("a"), frame: .init(x: 0, y: 100, width: 300, height: 200), in: container, parent: parent)
        let controller = try #require(player.controller)

        player.isFullScreen = true
        player.follow(frame: .init(x: 0, y: 999, width: 1, height: 1))
        player.stop()
        #expect(player.isActive)
        #expect(controller.view.frame.minY == 100)

        player.isFullScreen = false
        player.stop()
        #expect(!player.isActive)
    }
}
