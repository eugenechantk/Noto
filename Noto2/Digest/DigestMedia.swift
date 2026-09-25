import SwiftUI
import UIKit

/// Splits a Digest card's text into prose and the media lines Hermes (or
/// anyone) wrote as `![](.attachments/…)`, so the card can show thumbnails
/// instead of raw markdown. Uses the editor's own image-link parser, so the
/// card and the editor agree on what counts as media.
struct DigestMediaSplit: Equatable {
    struct Item: Equatable, Identifiable {
        let url: URL
        let isVideo: Bool
        var id: URL { url }
    }

    /// The text without media lines, blank-line runs collapsed; nil if nothing is left.
    let text: String?
    let media: [Item]

    static func split(_ text: String, vaultURL: URL?) -> DigestMediaSplit {
        var kept: [String] = []
        var media: [Item] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let candidate = String(line)
            let unwrapped = MarkdownBlockMarker.stripping(from: candidate.trimmingCharacters(in: .whitespaces))
                ?? candidate.trimmingCharacters(in: .whitespaces)
            if let link = MarkdownImageLinkParser.parse(from: unwrapped)?.resolving(relativeTo: vaultURL),
               let url = link.url, url.isFileURL {
                media.append(Item(url: url, isVideo: VideoPosterRenderer.isVideo(url)))
            } else {
                kept.append(candidate)
            }
        }
        let prose = kept.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DigestMediaSplit(text: prose.isEmpty ? nil : prose, media: media)
    }
}

/// Up to three thumbnails in a fixed row — not a horizontal scroller, which
/// would steal the card's left/right swipes. The third shows "+N" when there
/// are more. Tapping a video asks the screen to play it.
struct DigestMediaStrip: View {
    static let maxVisible = 3
    static let height: CGFloat = 120

    let items: [DigestMediaSplit.Item]
    var onPlay: (URL) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.prefix(Self.maxVisible).enumerated()), id: \.element.id) { index, item in
                let hidden = index == Self.maxVisible - 1 ? items.count - Self.maxVisible : 0
                DigestMediaThumbnail(item: item, hiddenCount: hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if item.isVideo { onPlay(item.url) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.isVideo ? "Play video" : "Image")
                    .accessibilityAddTraits(item.isVideo ? [.isButton, .startsMediaSession] : .isImage)
                    .accessibilityIdentifier(item.isVideo ? "digestVideoThumbnail_\(index)" : "digestImageThumbnail_\(index)")
            }
        }
        .frame(height: Self.height)
        // `.contain` keeps each thumbnail's own identifier; without it the
        // row's identifier replaces them.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("digestMediaStrip")
    }
}

private struct DigestMediaThumbnail: View {
    let item: DigestMediaSplit.Item
    let hiddenCount: Int
    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // The tile's size comes from the row (equal widths, fixed height); the
        // image fills it as an overlay and is clipped, so a portrait or
        // landscape picture can never grow the tile past the row.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: DigestMediaStrip.height)
            .background(NotoTheme.background.opacity(0.6))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .overlay {
                if hiddenCount > 0 {
                    ZStack {
                        Color.black.opacity(0.5)
                        Text("+\(hiddenCount)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .task(id: item.url) { image = await DigestThumbnailLoader.image(for: item) }
    }
}

/// Small, cached thumbnails: a downscaled image, or a video's first frame
/// with the play badge (the same poster the editor draws).
enum DigestThumbnailLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for item: DigestMediaSplit.Item) async -> UIImage? {
        if let cached = cache.object(forKey: item.url as NSURL) { return cached }
        guard CoordinatedFileManager.isDownloaded(at: item.url) else {
            CoordinatedFileManager.startDownloading(at: item.url)
            return nil
        }
        let image: UIImage?
        if item.isVideo {
            image = await withCheckedContinuation { continuation in
                VideoPosterRenderer.poster(for: item.url) { frame in
                    continuation.resume(returning: frame.map { UIImage(cgImage: $0) })
                }
            }
        } else {
            image = await Task.detached(priority: .utility) {
                CoordinatedFileManager.readData(from: item.url)
                    .flatMap { UIImage(data: $0) }?
                    .preparingThumbnail(of: CGSize(width: 480, height: 480))
            }.value
        }
        if let image { cache.setObject(image, forKey: item.url as NSURL) }
        return image
    }
}

/// Card prose with inline markdown (bold, italics, code, links) rendered and
/// line breaks kept — Hermes writes `**@author**`, and a capture is markdown.
/// Falls back to the plain string if it does not parse.
enum DigestCardText {
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// `fullScreenCover(item:)` needs an Identifiable value.
struct PlayingVideo: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}
