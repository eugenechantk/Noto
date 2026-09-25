import AVFoundation
import ImageIO
import NotoVault
import PDFKit
import SwiftUI
import UIKit

struct MediaBoardTile: View {
    let item: VaultMediaItem
    let width: CGFloat
    let revision: Int
    @State private var image: UIImage?
    @State private var isLoading = true

    private var height: CGFloat {
        guard let image, image.size.width > 0 else {
            return width * (item.kind == .audio ? 0.85 : 1.2)
        }
        return width * min(2, max(0.65, image.size.height / image.size.width))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 18)
                .fill(NotoTheme.head.opacity(0.07))
                .frame(width: width, height: height)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: item.kind.symbol)
                                .font(.system(size: 30, weight: .light))
                            if isLoading && item.kind != .audio {
                                ProgressView()
                            } else {
                                Text(item.kind == .audio ? item.mediaURL.deletingPathExtension().lastPathComponent : "Preview unavailable")
                                    .font(.caption)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .foregroundStyle(NotoTheme.muted)
                        .padding(16)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    if item.kind != .image {
                        Label(item.kind.title, systemImage: item.kind.symbol)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(9)
                    }
                }
            Text(item.noteTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NotoTheme.head)
                .lineLimit(2)
            Label(item.noteRelativePath.contains("/") ? item.noteURL.deletingLastPathComponent().lastPathComponent : "Notes", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(NotoTheme.muted)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .task(id: "\(item.id)|\(item.modifiedAt)|\(revision)") {
            isLoading = true
            let loaded = await MediaBoardThumbnail.image(for: item)
            guard !Task.isCancelled else { return }
            image = loaded
            isLoading = false
        }
    }
}

/// Bounded decoded-image cache; only visible lazy tiles ask for thumbnails.
/// ImageIO downsamples before decoding, and all file/decoder work runs off main.
@MainActor
enum MediaBoardThumbnail {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 150
        return cache
    }()

    static func image(for item: VaultMediaItem) async -> UIImage? {
        guard item.kind != .audio else { return nil }
        let key = "\(item.mediaURL.absoluteString)|\(item.modifiedAt.timeIntervalSince1970)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let work = Task.detached(priority: .utility) { await render(item) }
        let image = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return nil }
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    nonisolated private static func render(_ item: VaultMediaItem) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if item.kind == .video {
            // Remote videos remain lightweight placeholders until opened in their note.
            guard item.mediaURL.isFileURL else { return nil }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.mediaURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            if let frame = try? await generator.image(at: .zero).image {
                return UIImage(cgImage: frame)
            }
            requestDownloadIfNeeded(item.mediaURL)
            return nil
        }

        if item.mediaURL.isFileURL {
            var image: UIImage?
            NSFileCoordinator().coordinate(readingItemAt: item.mediaURL, options: [], error: nil) { url in
                guard !Task.isCancelled else { return }
                if item.kind == .pdf {
                    image = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 480, height: 640), for: .mediaBox)
                } else {
                    image = thumbnail(url: url)
                }
            }
            if image == nil { requestDownloadIfNeeded(item.mediaURL) }
            return image
        } else if item.kind == .image {
            var request = URLRequest(url: item.mediaURL)
            request.timeoutInterval = 20
            // Download to disk to keep large remote responses out of memory.
            if let (temporaryURL, response) = try? await URLSession.shared.download(for: request) {
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                      let size = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= 30 * 1024 * 1024 else { return nil }
                return thumbnail(url: temporaryURL)
            }
            return nil
        } else { return nil }
    }

    nonisolated private static func thumbnail(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source: source)
    }

    nonisolated private static func thumbnail(source: CGImageSource) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }

    nonisolated private static func requestDownloadIfNeeded(_ url: URL) {
        CoordinatedFileManager.startDownloading(at: url)
    }
}
