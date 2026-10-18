import Foundation

/// The editable share-sheet draft. Preparing or changing it has no side effects;
/// only the extension's explicit Save action writes it to `PendingCaptureStore`.
public struct ShareCaptureDraft: Equatable, Sendable {
    public let url: URL
    public let title: String?
    public var thought: String

    public init(resolved: SharedLinkPayload.Resolved) {
        url = resolved.url
        title = resolved.title
        let text = SharedLinkCapture.sanitizedText(resolved.text) ?? ""
        let repeatedValues = [url.absoluteString, SharedLinkCapture.linkDestination(for: url),
                              SharedLinkCapture.sanitizedTitle(title)].compactMap { $0 }
        thought = repeatedValues.contains(text) ? "" : text
    }

    /// The thought precedes the link, matching what the person sees while composing.
    public var body: String {
        let link = SharedLinkCapture.body(url: url, title: title)
        guard let text = SharedLinkCapture.sanitizedText(thought) else { return link }
        return text + "\n\n" + link
    }
}
