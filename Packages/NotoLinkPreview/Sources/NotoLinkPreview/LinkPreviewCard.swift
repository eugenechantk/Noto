import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Colours for `LinkPreviewCard`; each app passes its theme.
public struct LinkPreviewCardStyle {
    public var background: Color
    public var border: Color
    public var title: Color
    public var summary: Color
    public var host: Color
    /// Banner fill when the page has no image (or it has not loaded yet).
    public var placeholder: Color

    public init(background: Color, border: Color, title: Color, summary: Color, host: Color, placeholder: Color) {
        self.background = background
        self.border = border
        self.title = title
        self.summary = summary
        self.host = host
        self.placeholder = placeholder
    }
}

/// The one preview card every surface shows — editor (iOS and macOS, hosted),
/// Digest, and the share sheet. Laid out to `LinkPreviewCardLayout`: banner on
/// top, then title (≤2 lines), description (≤3 lines) and the site.
public struct LinkPreviewCard: View {
    public let content: LinkPreviewCardContent
    public let style: LinkPreviewCardStyle
    private let image: Image?
    private let icon: Image?

    public init(content: LinkPreviewCardContent, style: LinkPreviewCardStyle) {
        self.content = content
        self.style = style
        image = content.imageData.flatMap(Self.image(from:))
        icon = content.iconData.flatMap(Self.image(from:))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
                .frame(maxWidth: .infinity)
                .frame(height: LinkPreviewCardLayout.bannerHeight)
                .clipped()
            Rectangle()
                .fill(style.border)
                .frame(height: 1)
            textBlock
        }
        .frame(maxWidth: .infinity)
        .frame(height: LinkPreviewCardLayout.defaultHeight)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: LinkPreviewCardLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkPreviewCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(style.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.title)
        .accessibilityValue(content.host)
        .accessibilityAddTraits(.isLink)
    }

    @ViewBuilder
    private var banner: some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                style.placeholder
                VStack(spacing: 8) {
                    if let icon {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(style.summary.opacity(0.7))
                    }
                    Text(content.host)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.summary.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style.title)
                .lineLimit(LinkPreviewCardLayout.titleLineLimit)
                .layoutPriority(2)
            if let summary = content.subtitle {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(style.summary)
                    .lineLimit(LinkPreviewCardLayout.summaryLineLimit)
            }
            Spacer(minLength: 0)
            HStack(spacing: LinkPreviewCardLayout.iconTextGap) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: LinkPreviewCardLayout.iconSize, height: LinkPreviewCardLayout.iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Text(content.host)
                    .font(.system(size: 12))
                    .foregroundStyle(style.host)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
        }
        .padding(LinkPreviewCardLayout.defaultPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        nil
        #endif
    }
}
