import Foundation

/// The Open Graph / Twitter-card tags of an HTML page — the same tags every
/// chat app reads to build a link preview.
public struct OpenGraphTags: Equatable, Sendable {
    public var title: String?
    public var summary: String?
    public var imageURL: URL?

    public init(title: String? = nil, summary: String? = nil, imageURL: URL? = nil) {
        self.title = title
        self.summary = summary
        self.imageURL = imageURL
    }

    public var isEmpty: Bool { title == nil && summary == nil && imageURL == nil }
}

/// Reads `<meta>` tags without an HTML parser: attribute order varies
/// (`property` before or after `content`), quotes vary, and entities are escaped.
public enum OpenGraphParser {
    public static func parse(html: String, baseURL: URL) -> OpenGraphTags {
        var values: [String: String] = [:]
        let metaPattern = #"<meta\b[^>]*>"#
        guard let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive]) else {
            return OpenGraphTags()
        }
        let range = NSRange(html.startIndex..., in: html)
        for match in metaRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let key = attribute("property", in: tag) ?? attribute("name", in: tag),
                  let content = attribute("content", in: tag) else { continue }
            let normalizedKey = key.lowercased()
            if values[normalizedKey] == nil {
                values[normalizedKey] = decodeEntities(content)
            }
        }

        func first(_ keys: [String]) -> String? {
            keys.lazy.compactMap { values[$0].flatMap(nonEmpty) }.first
        }

        let htmlTitle = firstMatch(#"<title[^>]*>([^<]*)</title>"#, in: html).map(decodeEntities).flatMap(nonEmpty)
        let image = first(["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"])
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            .flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }

        return OpenGraphTags(
            title: first(["og:title", "twitter:title"]) ?? htmlTitle,
            summary: first(["og:description", "twitter:description", "description"]),
            imageURL: image
        )
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let nsText = result as NSString
            var output = ""
            var cursor = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: nsText.length)) {
                output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let isHex = nsText.substring(with: match.range(at: 1)) == "x"
                let digits = nsText.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                    output.unicodeScalars.append(scalar)
                } else {
                    output += nsText.substring(with: match.range)
                }
                cursor = match.range.location + match.range.length
            }
            output += nsText.substring(from: cursor)
            result = output
        }
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    private static func nonEmpty(_ text: String) -> String? {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

/// Fetches a page's HTML as a link-preview crawler would and builds metadata
/// from its Open Graph tags. Sites (Instagram among them) serve those tags to
/// crawler user agents even when `LinkPresentation` gets little or nothing.
public struct OpenGraphFetcher: LinkPreviewFetching {
    public typealias Load = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let crawlerUserAgent = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
    /// Pages are read up to this many bytes; the tags live in `<head>`.
    static let maxHTMLBytes = 1_500_000

    private let load: Load
    private let maxImagePixelSize: Int

    public init(maxImagePixelSize: Int = 640, load: Load? = nil) {
        self.maxImagePixelSize = maxImagePixelSize
        self.load = load ?? { request in try await URLSession.shared.data(for: request) }
    }

    public func fetch(_ url: URL) async throws -> LinkPreviewMetadata {
        let (data, response) = try await load(Self.request(url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinkPreviewFetchError.noMetadata
        }
        let html = String(decoding: data.prefix(Self.maxHTMLBytes), as: UTF8.self)
        let tags = OpenGraphParser.parse(html: html, baseURL: response.url ?? url)
        guard !tags.isEmpty else { throw LinkPreviewFetchError.noMetadata }

        var imageData: Data?
        if let imageURL = tags.imageURL, let image = try? await load(Self.request(imageURL)),
           (image.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true {
            imageData = LinkPreviewImageDownsampler.downsample(image.0, maxPixelSize: maxImagePixelSize)
        }
        return LinkPreviewMetadata(
            url: url,
            title: tags.title,
            summary: tags.summary,
            host: LinkPreviewMetadata.displayHost(for: response.url ?? url),
            imageData: imageData
        )
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(crawlerUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }
}

/// `LinkPresentation` first; the page's own Open Graph tags fill whatever it
/// missed. A primary result with both an image and a description is used as is.
/// When the primary result is *weak* (no image and no description — Instagram
/// gives just "Instagram"), the Open Graph title is preferred too.
public struct CompositeLinkPreviewFetcher: LinkPreviewFetching {
    private let primary: any LinkPreviewFetching
    private let secondary: any LinkPreviewFetching

    public init(primary: any LinkPreviewFetching, secondary: any LinkPreviewFetching) {
        self.primary = primary
        self.secondary = secondary
    }

    public func fetch(_ url: URL) async throws -> LinkPreviewMetadata {
        let first = try? await primary.fetch(url)
        if let first, first.imageData != nil, first.summary != nil {
            return first
        }
        let second = try? await secondary.fetch(url)
        guard let merged = Self.merge(primary: first, secondary: second) else {
            throw LinkPreviewFetchError.noMetadata
        }
        return merged
    }

    static func merge(primary: LinkPreviewMetadata?, secondary: LinkPreviewMetadata?) -> LinkPreviewMetadata? {
        guard let base = primary ?? secondary else { return nil }
        guard let primary, let secondary else { return base }
        let primaryIsWeak = primary.imageData == nil && primary.summary == nil
        var merged = primary
        merged.title = primaryIsWeak ? (secondary.title ?? primary.title) : (primary.title ?? secondary.title)
        merged.summary = primary.summary ?? secondary.summary
        merged.imageData = primary.imageData ?? secondary.imageData
        merged.iconData = primary.iconData ?? secondary.iconData
        return merged
    }
}
