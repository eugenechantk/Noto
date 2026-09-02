import Foundation

/// Canonical URL contract for opening a vault-relative Markdown note in Noto.
///
/// Two wire forms exist and both decode to the same vault-relative path:
///
/// - `noto://open?path=<encoded>` — the custom scheme. Works from anywhere the OS treats the
///   text as a link (Safari, Shortcuts, Terminal `open`), but most messengers refuse to
///   autolink a non-`http` scheme.
/// - `https://noto.eugenechantk.me/open#path=<encoded>` — the Universal Link. Autolinks
///   everywhere and opens the app directly. This is the form we hand out.
///
/// The web form carries its payload in the **fragment**, not the query, because fragments are
/// never transmitted to the origin server. Note titles therefore stay out of edge access logs
/// and out of the link-preview fetches that messengers make. The app still receives the whole
/// URL, fragment included.
public enum NotoDeepLink {
    private static let scheme = "noto"
    private static let openHost = "open"

    private static let webScheme = "https"
    private static let webPath = "/open"
    private static let pathParameterName = "path"

    /// Host serving the `apple-app-site-association` file that authorises Universal Links.
    /// Must stay in lockstep with the `applinks:` entry in `Noto/Noto.entitlements`.
    public static let webHost = "noto.eugenechantk.me"

    /// Characters left unescaped in the encoded path payload.
    ///
    /// Deliberately stricter than `urlQueryAllowed`: `&` and `=` would split the payload,
    /// `#` would truncate it, `/` must survive as `%2F` so a decoded path can never be
    /// mistaken for a URL path, and `+` is escaped so any intermediary that form-decodes the
    /// value cannot silently turn it into a space.
    private static let payloadAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?%")
        return allowed
    }()

    // MARK: - Building

    /// Custom-scheme URL: `noto://open?path=<encoded>`.
    public static func openURL(vaultRelativePath: String) -> URL? {
        guard let encodedPath = encodedPayload(for: vaultRelativePath) else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = openHost
        components.percentEncodedQuery = "\(pathParameterName)=\(encodedPath)"
        return components.url
    }

    /// Universal Link: `https://noto.eugenechantk.me/open#path=<encoded>`.
    ///
    /// This is the canonical link to hand to humans and to other systems.
    public static func webURL(vaultRelativePath: String) -> URL? {
        guard let encodedPath = encodedPayload(for: vaultRelativePath) else { return nil }

        var components = URLComponents()
        components.scheme = webScheme
        components.host = webHost
        components.path = webPath
        components.percentEncodedFragment = "\(pathParameterName)=\(encodedPath)"
        return components.url
    }

    private static func encodedPayload(for vaultRelativePath: String) -> String? {
        guard let path = validatedVaultRelativePath(vaultRelativePath) else { return nil }
        return path.addingPercentEncoding(withAllowedCharacters: payloadAllowedCharacters)
    }

    // MARK: - Parsing

    /// Decodes either wire form into a validated vault-relative path, or `nil` if the URL is
    /// not ours or the payload is unsafe.
    public static func vaultRelativePath(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case scheme:
            guard components.host?.lowercased() == openHost else { return nil }
            return validatedVaultRelativePath(payload(inEncoded: components.percentEncodedQuery))
        case webScheme:
            guard components.host?.lowercased() == webHost,
                  normalizedWebPath(components.path) == webPath else {
                return nil
            }
            // Fragment is the canonical carrier; the query form is accepted only so links
            // mangled by a client that strips fragments still resolve.
            let encodedPayload = components.percentEncodedFragment ?? components.percentEncodedQuery
            return validatedVaultRelativePath(payload(inEncoded: encodedPayload))
        default:
            return nil
        }
    }

    private static func normalizedWebPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    /// Pulls the single `path=` value out of an *encoded* `key=value&key=value` string.
    ///
    /// The string must still be percent-encoded when it is split: decoding first would let an
    /// encoded `&` or `=` inside a note title fracture the payload. More than one `path` key is
    /// ambiguous and is refused rather than guessed at.
    private static func payload(inEncoded encodedPairs: String?) -> String? {
        guard let encodedPairs, !encodedPairs.isEmpty else { return nil }

        let values = encodedPairs.split(separator: "&", omittingEmptySubsequences: false).compactMap { pair -> String? in
            guard let separatorIndex = pair.firstIndex(of: "="),
                  pair[pair.startIndex..<separatorIndex] == pathParameterName else {
                return nil
            }
            return String(pair[pair.index(after: separatorIndex)...])
        }

        guard values.count == 1 else { return nil }
        return values[0].removingPercentEncoding
    }

    // MARK: - Validation

    private static func validatedVaultRelativePath(_ path: String?) -> String? {
        guard let path, !path.isEmpty, !path.contains("\0") else { return nil }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        guard (path as NSString).pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else {
            return nil
        }

        return path
    }
}
