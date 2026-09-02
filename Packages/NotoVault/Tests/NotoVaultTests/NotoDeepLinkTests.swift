import Foundation
import Testing
@testable import NotoVault

@Suite("Noto deep-link URL codec")
struct NotoDeepLinkTests {
    @Test("Builds and parses a canonical URL for a nested markdown note")
    func roundTripsNestedMarkdownPath() throws {
        let path = "Captures/SpaceX & the Sentient Sun.md"

        let url = try #require(NotoDeepLink.openURL(vaultRelativePath: path))

        #expect(url.absoluteString == "noto://open?path=Captures%2FSpaceX%20%26%20the%20Sentient%20Sun.md")
        #expect(NotoDeepLink.vaultRelativePath(from: url) == path)
    }

    @Test("Round-trips Unicode note paths")
    func roundTripsUnicodePath() throws {
        let path = "Ideas/產品構想.md"

        let url = try #require(NotoDeepLink.openURL(vaultRelativePath: path))

        #expect(NotoDeepLink.vaultRelativePath(from: url) == path)
        #expect(url.absoluteString.hasPrefix("noto://open?path="))
    }

    @Test("Rejects unsupported or unsafe URL inputs")
    func rejectsUnsafeURLs() throws {
        let invalidURLs = [
            "https://example.com/open?path=Captures%2FA.md",
            "noto://preview?path=Captures%2FA.md",
            "noto://open",
            "noto://open?path=",
            "noto://open?path=%2FUsers%2Feugenechan%2FSecrets.md",
            "noto://open?path=..%2FSecrets.md",
            "noto://open?path=Captures%2F..%2FSecrets.md",
            "noto://open?path=Captures%2F%2FSecrets.md",
            "noto://open?path=Captures%2F.%2FSecrets.md",
            "noto://open?path=Captures%2FImage.png",
            "noto://open?path=Captures%2FA.md&path=Captures%2FB.md",
        ]

        for rawURL in invalidURLs {
            let url = try #require(URL(string: rawURL))
            #expect(NotoDeepLink.vaultRelativePath(from: url) == nil, "Expected to reject \(rawURL)")
        }
    }

    @Test("Refuses to build URLs for invalid vault paths")
    func rejectsUnsafePaths() {
        let invalidPaths = [
            "",
            "/Captures/Secrets.md",
            "../Secrets.md",
            "Captures/../Secrets.md",
            "Captures//Secrets.md",
            "Captures/./Secrets.md",
            "Captures/Image.png",
        ]

        for path in invalidPaths {
            #expect(NotoDeepLink.openURL(vaultRelativePath: path) == nil, "Expected to reject \(path)")
        }
    }
}
