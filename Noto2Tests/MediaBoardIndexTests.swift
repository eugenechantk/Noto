import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. pathsInsideTheAppHomeAreWrittenRelativeToIt — the index/thumbnail identity survives the data folder moving
/// 2. pathsOutsideTheHomeStayAbsolute — an iCloud Drive vault keeps its absolute path
/// 3. indexNameFollowsTheStablePath — same vault → same index file
struct MediaBoardIndexTests {
    private let home = URL(fileURLWithPath: NSHomeDirectory())

    @Test func pathsInsideTheAppHomeAreWrittenRelativeToIt() {
        let file = home.appendingPathComponent("Documents/Noto/.attachments/a.png")
        #expect(MediaBoardIndex.stablePath(file) == "~/Documents/Noto/.attachments/a.png")
    }

    @Test func pathsOutsideTheHomeStayAbsolute() {
        let iCloud = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/iCloud~com~eugenechan~Noto/Documents/Noto")
        #expect(MediaBoardIndex.stablePath(iCloud) == iCloud.path)
    }

    @Test func indexNameFollowsTheStablePath() {
        let vault = home.appendingPathComponent("Documents/Noto")
        #expect(MediaBoardIndex.url(for: vault) == MediaBoardIndex.url(for: vault.appendingPathComponent(".")))
        #expect(MediaBoardIndex.url(for: vault) != MediaBoardIndex.url(for: home.appendingPathComponent("Documents/Other")))
        #expect(MediaBoardIndex.url(for: vault).pathExtension == "json")
    }
}
