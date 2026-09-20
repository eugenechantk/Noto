import Foundation
import ImageIO
import LinkPresentation
import UniformTypeIdentifiers

/// Boundary between the service and the network. The app injects
/// `LinkPresentationFetcher`; tests inject a fake.
public protocol LinkPreviewFetching: Sendable {
    func fetch(_ url: URL) async throws -> LinkPreviewMetadata
}

public enum LinkPreviewFetchError: Error, Equatable {
    case noMetadata
    case cancelled
}

/// Fetches page metadata through Apple's `LPMetadataProvider` and resolves the
/// image / icon item providers into bytes small enough to cache.
public struct LinkPresentationFetcher: LinkPreviewFetching {
    public var timeout: TimeInterval
    public var maxImagePixelSize: Int

    public init(timeout: TimeInterval = 15, maxImagePixelSize: Int = 640) {
        self.timeout = timeout
        self.maxImagePixelSize = maxImagePixelSize
    }

    public func fetch(_ url: URL) async throws -> LinkPreviewMetadata {
        let metadata = try await startFetching(url)
        let imageData = await Self.imageData(from: metadata.imageProvider, maxPixelSize: maxImagePixelSize)
        let iconData = await Self.imageData(from: metadata.iconProvider, maxPixelSize: 128)

        return LinkPreviewMetadata(
            url: url,
            title: Self.cleaned(metadata.title),
            summary: Self.cleaned(metadata.value(forKey: "summary") as? String),
            host: LinkPreviewMetadata.displayHost(for: metadata.originalURL ?? url),
            imageData: imageData,
            iconData: iconData,
            fetchedAt: Date()
        )
    }

    @MainActor
    private func startFetching(_ url: URL) async throws -> LPLinkMetadata {
        let provider = LPMetadataProvider()
        provider.timeout = timeout
        provider.shouldFetchSubresources = true

        return try await withCheckedThrowingContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: LinkPreviewFetchError.noMetadata)
                }
            }
        }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func imageData(from provider: NSItemProvider?, maxPixelSize: Int) async -> Data? {
        guard let provider,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        let raw: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let raw else { return nil }
        return LinkPreviewImageDownsampler.downsample(raw, maxPixelSize: maxPixelSize) ?? raw
    }
}

/// Shrinks an arbitrary image blob to a bounded JPEG so a 4 MB hero image does not
/// end up in the cache (and in memory) for every card that shows it.
public enum LinkPreviewImageDownsampler {
    public static func downsample(_ data: Data, maxPixelSize: Int, compressionQuality: CGFloat = 0.82) -> Data? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Pixel size of an encoded image without decoding it.
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
}
