import Foundation
import NotoShareCapture

/// Reads an X post through `cdn.syndication.twimg.com/tweet-result` — the
/// public endpoint X's own embed widgets use. No login, and the quoted post
/// (with its media) comes back in the same response.
public enum XPostResolver {
    /// The status id in `/<user>/status/<id>` or `/i/web/status/<id>`.
    public static func statusID(in url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "status"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return !id.isEmpty && id.allSatisfy(\.isNumber) ? id : nil
    }

    /// The widget's anti-scrape token: `((id / 1e15) * π)` in base 36, with
    /// zeros and the point removed.
    public static func token(for statusID: String) -> String {
        guard let id = Double(statusID) else { return "0" }
        return base36((id / 1e15) * Double.pi)
            .replacingOccurrences(of: "0", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    public static func requestURL(for statusID: String) -> URL {
        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [
            URLQueryItem(name: "id", value: statusID),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "token", value: token(for: statusID)),
        ]
        return components.url!
    }

    public static func parse(_ data: Data) throws -> SocialPost {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocialPostError.unreadable("not a JSON object")
        }
        guard let post = post(from: object) else {
            throw SocialPostError.unreadable("no id_str — deleted, private or age-restricted post")
        }
        return post
    }

    static func post(from object: [String: Any]) -> SocialPost? {
        guard let id = object["id_str"] as? String else { return nil }
        let user = object["user"] as? [String: Any]
        let media = (object["mediaDetails"] as? [[String: Any]] ?? []).compactMap(mediaItem(from:))
        let quoted = (object["quoted_tweet"] as? [String: Any]).flatMap(post(from:)).map { [$0] } ?? []
        return SocialPost(platform: .x, postID: id, author: user?["screen_name"] as? String,
                          text: displayText(from: object), media: media, quoted: quoted)
    }

    static func mediaItem(from object: [String: Any]) -> SocialMedia? {
        let type = object["type"] as? String
        if type == "video" || type == "animated_gif" {
            let variants = (object["video_info"] as? [String: Any])?["variants"] as? [[String: Any]] ?? []
            let best = variants
                .filter { ($0["content_type"] as? String) == "video/mp4" }
                .max { ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0) }
            guard let raw = best?["url"] as? String, let url = URL(string: raw) else { return nil }
            return SocialMedia(kind: .video, url: url)
        }
        guard let raw = object["media_url_https"] as? String, var components = URLComponents(string: raw) else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: "large")]
        return components.url.map { SocialMedia(kind: .image, url: $0) }
    }

    /// The post text without the trailing `pic.x.com` / quote `t.co` links
    /// (`display_text_range`, counted in Unicode scalars of the entity-decoded
    /// text, as X's indices are), with link `t.co`s expanded.
    static func displayText(from object: [String: Any]) -> String? {
        guard let raw = object["text"] as? String else { return nil }
        var text = raw.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        if let range = object["display_text_range"] as? [Int], range.count == 2 {
            let scalars = Array(text.unicodeScalars)
            let start = max(0, min(range[0], scalars.count)), end = max(start, min(range[1], scalars.count))
            text = String(String.UnicodeScalarView(scalars[start..<end]))
        }
        let urls = (object["entities"] as? [String: Any])?["urls"] as? [[String: Any]] ?? []
        for entry in urls {
            if let short = entry["url"] as? String, let expanded = entry["expanded_url"] as? String {
                text = text.replacingOccurrences(of: short, with: expanded)
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// JavaScript's `Number.prototype.toString(36)` for a positive finite
    /// double — a port of V8's `DoubleToRadixCString`, which emits the
    /// shortest fraction that round-trips (with round-half-even carry).
    static func base36(_ value: Double) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let radix = 36.0
        var integer = value.rounded(.down)
        var fraction = value - integer
        var delta = max(0.5 * (value.nextUp - value), Double.leastNonzeroMagnitude)
        var fractionDigits: [Character] = []
        if fraction >= delta {
            repeat {
                fraction *= radix
                delta *= radix
                let digit = Int(fraction)
                fractionDigits.append(chars[digit])
                fraction -= Double(digit)
                if fraction > 0.5 || (fraction == 0.5 && digit & 1 == 1), fraction + delta > 1 {
                    // Round up, carrying through already-written digits.
                    while true {
                        guard let last = fractionDigits.popLast() else {
                            integer += 1
                            break
                        }
                        let lastDigit = chars.firstIndex(of: last)!
                        if lastDigit + 1 < 36 {
                            fractionDigits.append(chars[lastDigit + 1])
                            break
                        }
                    }
                    break
                }
            } while fraction >= delta
        }
        var integerDigits: [Character] = []
        repeat {
            let digit = Int(integer.truncatingRemainder(dividingBy: radix))
            integerDigits.append(chars[digit])
            integer = ((integer - Double(digit)) / radix).rounded(.down)
        } while integer > 0
        let head = String(integerDigits.reversed())
        return fractionDigits.isEmpty ? head : head + "." + String(fractionDigits)
    }
}
