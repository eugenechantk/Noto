import Foundation
import Testing
@testable import Noto

@Suite("Noto deep links")
struct NotoDeepLinkTests {
    @Test("Builds encoded open URLs for vault-relative markdown paths")
    func buildsOpenURLForVaultRelativePath() throws {
        let url = try #require(NotoDeepLink.openURL(vaultRelativePath: "Captures/SpaceX & the Sentient Sun.md"))

        #expect(url.absoluteString == "noto://open?path=Captures%2FSpaceX%20%26%20the%20Sentient%20Sun.md")
        #expect(NotoDeepLink.vaultRelativePath(from: url) == "Captures/SpaceX & the Sentient Sun.md")
    }

    @Test("Parses open URLs with encoded path query")
    func parsesOpenURLWithEncodedPathQuery() throws {
        let url = try #require(URL(string: "noto://open?path=Captures%2FNested%20Note.md"))

        #expect(NotoDeepLink.vaultRelativePath(from: url) == "Captures/Nested Note.md")
    }

    @Test("Rejects unsafe and unsupported URLs")
    func rejectsUnsafeAndUnsupportedURLs() throws {
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

        #expect(NotoDeepLink.openURL(vaultRelativePath: "../Secrets.md") == nil)
        #expect(NotoDeepLink.openURL(vaultRelativePath: "Captures//Secrets.md") == nil)
        #expect(NotoDeepLink.openURL(vaultRelativePath: "Captures/Image.png") == nil)
    }

    @MainActor
    @Test("Router stores valid pending document links and ignores invalid URLs")
    func routerStoresValidPendingDocumentLinksAndIgnoresInvalidURLs() throws {
        let router = NotoDeepLinkRouter()
        let validURL = try #require(URL(string: "noto://open?path=Captures%2FArticle.md"))
        let invalidURL = try #require(URL(string: "noto://open?path=..%2FSecrets.md"))

        #expect(router.open(validURL))
        #expect(router.pendingDocumentPath == "Captures/Article.md")
        #expect(!router.open(invalidURL))
        #expect(router.pendingDocumentPath == "Captures/Article.md")
        #expect(router.consumePendingDocumentPath() == "Captures/Article.md")
        #expect(router.pendingDocumentPath == nil)
    }

    @Test("App Info plist registers the noto URL scheme")
    func appInfoPlistRegistersNotoURLScheme() throws {
        let urlTypes = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }

        #expect(schemes.contains("noto"))
    }
}
