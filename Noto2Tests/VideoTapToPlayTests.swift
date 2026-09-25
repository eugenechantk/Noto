import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. onlyLocalVideoFilesArePlayable — .mp4/.mov/.m4v file URLs (any case) play; images, remote URLs and nil do not (SC1)
/// 2. mediaLinesLeaveTheCardTextInOrder — Hermes' block: prose kept, media lifted out in order, videos flagged (SC4)
/// 3. quotedAndListedMediaLinesAreMediaToo — `> ![](…)` / `- ![](…)` lines count, like in the editor (SC4)
/// 4. remoteImagesAndInlineLinksStayText — only lines that resolve to a vault file become thumbnails (SC4)
/// 5. mediaOnlyTextLeavesNoProse — a block that is only media yields nil text (SC4)
/// 6. cardTextRendersInlineMarkdownAndKeepsLineBreaks — `**@author**` shows bold without asterisks; newlines survive (SC4)
struct VideoTapToPlayTests {
    private let vault = URL(fileURLWithPath: "/tmp/Vault", isDirectory: true)

    @Test func onlyLocalVideoFilesArePlayable() {
        for name in ["a.mp4", "b.MOV", "c.m4v"] {
            let url = vault.appendingPathComponent(".attachments/\(name)")
            #expect(VideoPosterRenderer.playableVideoURL(for: url) == url, "\(name)")
        }
        #expect(VideoPosterRenderer.playableVideoURL(for: vault.appendingPathComponent(".attachments/a.jpg")) == nil)
        #expect(VideoPosterRenderer.playableVideoURL(for: URL(string: "https://video.twimg.com/a.mp4")) == nil)
        #expect(VideoPosterRenderer.playableVideoURL(for: nil) == nil)
    }

    @Test func mediaLinesLeaveTheCardTextInOrder() {
        let text = """
        **@thaiscbranco_**
        congrats quiver team!

        ![](.attachments/x-1-1.jpg)
        ![](.attachments/x-1-2.mp4)

        Quoting **@QuiverAI**
        Introducing Arrow 2

        ![](.attachments/x-2-1.mp4)
        """
        let split = DigestMediaSplit.split(text, vaultURL: vault)
        #expect(split.text == "**@thaiscbranco_**\ncongrats quiver team!\n\nQuoting **@QuiverAI**\nIntroducing Arrow 2")
        #expect(split.media.map(\.url.lastPathComponent) == ["x-1-1.jpg", "x-1-2.mp4", "x-2-1.mp4"])
        #expect(split.media.map(\.isVideo) == [false, true, true])
        #expect(split.media.first?.url.path == "/tmp/Vault/.attachments/x-1-1.jpg")
    }

    @Test func quotedAndListedMediaLinesAreMediaToo() {
        let split = DigestMediaSplit.split("> ![](.attachments/q.mp4)\n- ![](.attachments/l.png)", vaultURL: vault)
        #expect(split.media.map(\.url.lastPathComponent) == ["q.mp4", "l.png"])
        #expect(split.text == nil)
    }

    @Test func remoteImagesAndInlineLinksStayText() {
        let text = "See ![](.attachments/inline.jpg) here\n![](https://pbs.twimg.com/media/A.jpg)\n[Post](https://x.com/a/status/1)"
        let split = DigestMediaSplit.split(text, vaultURL: vault)
        #expect(split.media.isEmpty)
        #expect(split.text == text)
    }

    @Test func mediaOnlyTextLeavesNoProse() {
        let split = DigestMediaSplit.split("\n![](.attachments/a.mp4)\n\n", vaultURL: vault)
        #expect(split.text == nil)
        #expect(split.media.count == 1)
    }

    @Test func cardTextRendersInlineMarkdownAndKeepsLineBreaks() {
        let attributed = DigestCardText.attributed("**@QuiverAI**\nIntroducing Arrow 2")
        #expect(String(attributed.characters) == "@QuiverAI\nIntroducing Arrow 2")
        let bold = attributed.runs.first { run in
            String(attributed[run.range].characters) == "@QuiverAI"
        }
        #expect(bold?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(String(DigestCardText.attributed("plain **unclosed").characters).contains("plain"))
    }
}
