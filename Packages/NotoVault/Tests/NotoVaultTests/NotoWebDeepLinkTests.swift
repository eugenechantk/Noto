import Foundation
import Testing
@testable import NotoVault

/// Test case index — https (Universal Link) form of the Noto deep-link codec.
///
/// 1. `buildsFragmentEncodedWebURL` — SC1: web URLs carry the path in the fragment, encoded.
/// 2. `roundTripsNestedWebPath` — SC2: build → parse returns the original nested path.
/// 3. `roundTripsUnicodeAndReservedCharacters` — SC2: Unicode and `&`/`#`/`+` survive the round trip.
/// 4. `parsesQueryFormForRobustness` — SC2: a query-encoded web URL still parses (never generated).
/// 5. `parsesTrailingSlashAndUppercaseHost` — SC2: host case and `/open/` are tolerated.
/// 6. `stillParsesCustomSchemeURLs` — SC2: the existing `noto://` contract is unchanged.
/// 7. `rejectsUnsafeOrForeignWebURLs` — SC3: wrong host/path/scheme and unsafe paths are refused.
/// 8. `refusesToBuildWebURLsForUnsafePaths` — SC1: unsafe vault paths never produce a web URL.
/// 9. `webURLNeverLeaksPathIntoServerVisibleComponents` — SC7: path appears only after `#`.
@Suite("Noto web deep-link URL codec")
struct NotoWebDeepLinkTests {
    @Test("Builds an https URL that carries the encoded path in the fragment")
    func buildsFragmentEncodedWebURL() throws {
        let url = try #require(NotoDeepLink.webURL(vaultRelativePath: "Captures/Sentient Sun.md"))

        #expect(url.absoluteString == "https://noto.eugenechantk.me/open#path=Captures%2FSentient%20Sun.md")
    }

    @Test("Round-trips a nested markdown path through the web URL")
    func roundTripsNestedWebPath() throws {
        let path = "Projects/Alpha/Kickoff Notes.md"

        let url = try #require(NotoDeepLink.webURL(vaultRelativePath: path))

        #expect(NotoDeepLink.vaultRelativePath(from: url) == path)
    }

    @Test("Round-trips Unicode and URL-reserved characters")
    func roundTripsUnicodeAndReservedCharacters() throws {
        let paths = [
            "Ideas/產品構想.md",
            "Captures/SpaceX & the Sun.md",
            "Captures/Sharp #1 Take.md",
            "Captures/C++ Notes.md",
            "Captures/50% Done.md",
            "Captures/a?b=c.md",
        ]

        for path in paths {
            let url = try #require(NotoDeepLink.webURL(vaultRelativePath: path), "Expected to build \(path)")
            #expect(NotoDeepLink.vaultRelativePath(from: url) == path, "Expected to round-trip \(path)")
        }
    }

    @Test("Parses the query-encoded web form for robustness")
    func parsesQueryFormForRobustness() throws {
        let url = try #require(URL(string: "https://noto.eugenechantk.me/open?path=Captures%2FA%20Note.md"))

        #expect(NotoDeepLink.vaultRelativePath(from: url) == "Captures/A Note.md")
    }

    @Test("Tolerates a trailing slash and non-canonical host casing")
    func parsesTrailingSlashAndUppercaseHost() throws {
        let variants = [
            "https://noto.eugenechantk.me/open/#path=Notes%2FA.md",
            "https://NOTO.EugeneChanTK.me/open#path=Notes%2FA.md",
            "HTTPS://noto.eugenechantk.me/open#path=Notes%2FA.md",
        ]

        for raw in variants {
            let url = try #require(URL(string: raw))
            #expect(NotoDeepLink.vaultRelativePath(from: url) == "Notes/A.md", "Expected to accept \(raw)")
        }
    }

    @Test("Leaves the existing custom-scheme contract intact")
    func stillParsesCustomSchemeURLs() throws {
        let path = "Captures/Legacy Link.md"

        let url = try #require(NotoDeepLink.openURL(vaultRelativePath: path))

        #expect(url.scheme == "noto")
        #expect(NotoDeepLink.vaultRelativePath(from: url) == path)
    }

    @Test("Rejects foreign hosts, wrong paths, and unsafe decoded paths")
    func rejectsUnsafeOrForeignWebURLs() throws {
        let invalidURLs = [
            // Wrong host — an attacker-controlled look-alike must not route.
            "https://example.com/open#path=Captures%2FA.md",
            "https://eugenechantk.me/open#path=Captures%2FA.md",
            "https://noto.eugenechantk.me.evil.com/open#path=Captures%2FA.md",
            // Wrong path.
            "https://noto.eugenechantk.me/#path=Captures%2FA.md",
            "https://noto.eugenechantk.me/openx#path=Captures%2FA.md",
            "https://noto.eugenechantk.me/open/extra#path=Captures%2FA.md",
            // Insecure scheme must not be honoured.
            "http://noto.eugenechantk.me/open#path=Captures%2FA.md",
            // Missing or empty payload.
            "https://noto.eugenechantk.me/open",
            "https://noto.eugenechantk.me/open#",
            "https://noto.eugenechantk.me/open#path=",
            "https://noto.eugenechantk.me/open#note=Captures%2FA.md",
            // Unsafe paths.
            "https://noto.eugenechantk.me/open#path=%2FUsers%2Feugenechan%2FSecrets.md",
            "https://noto.eugenechantk.me/open#path=..%2FSecrets.md",
            "https://noto.eugenechantk.me/open#path=Captures%2F..%2FSecrets.md",
            "https://noto.eugenechantk.me/open#path=Captures%2F%2FSecrets.md",
            "https://noto.eugenechantk.me/open#path=Captures%2F.%2FSecrets.md",
            "https://noto.eugenechantk.me/open#path=Captures%2FImage.png",
            // Ambiguous duplicate payloads.
            "https://noto.eugenechantk.me/open#path=Captures%2FA.md&path=Captures%2FB.md",
        ]

        for raw in invalidURLs {
            let url = try #require(URL(string: raw), "Expected a parseable URL for \(raw)")
            #expect(NotoDeepLink.vaultRelativePath(from: url) == nil, "Expected to reject \(raw)")
        }
    }

    @Test("Refuses to build web URLs for unsafe vault paths")
    func refusesToBuildWebURLsForUnsafePaths() {
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
            #expect(NotoDeepLink.webURL(vaultRelativePath: path) == nil, "Expected to reject \(path)")
        }
    }

    @Test("Keeps the note path out of every server-visible URL component")
    func webURLNeverLeaksPathIntoServerVisibleComponents() throws {
        let url = try #require(NotoDeepLink.webURL(vaultRelativePath: "Private/Therapy Notes.md"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        // Only the fragment may carry the path; fragments are never sent to the origin.
        #expect(components.path == "/open")
        #expect(components.query == nil)
        #expect(url.absoluteString.split(separator: "#").first == "https://noto.eugenechantk.me/open")
        #expect(components.fragment?.contains("Therapy Notes.md") == true)
    }
}
