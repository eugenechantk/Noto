import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct VaultImageAttachment: Sendable, Equatable {
    public let fileURL: URL
    public let relativePath: String
    public let markdownPath: String
    public let altText: String

    public init(fileURL: URL, relativePath: String, markdownPath: String, altText: String) {
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.markdownPath = markdownPath
        self.altText = altText
    }

    public var markdown: String {
        "![\(altText)](\(markdownPath))"
    }
}

public struct AttachmentStore: Sendable {
    public enum ImportError: Error, Equatable {
        case unsupportedImage
        case createAttachmentDirectoryFailed
        case writeFailed
    }

    public static let attachmentDirectoryName = ".attachments"

    public let vaultRootURL: URL
    public let fileSystem: any VaultFileSystem
    public var maxPixelSize: CGFloat
    public var jpegCompressionQuality: CGFloat

    public init(
        vaultRootURL: URL,
        fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem(),
        maxPixelSize: CGFloat = 2400,
        jpegCompressionQuality: CGFloat = 0.82
    ) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
        self.fileSystem = fileSystem
        self.maxPixelSize = maxPixelSize
        self.jpegCompressionQuality = jpegCompressionQuality
    }

    public func importImageFile(at sourceURL: URL) throws -> VaultImageAttachment {
        let data = try Data(contentsOf: sourceURL)
        return try importImageData(data, suggestedFilename: sourceURL.lastPathComponent)
    }

    public func importImageData(_ data: Data, suggestedFilename: String?) throws -> VaultImageAttachment {
        let encoded = try encodeImage(data)
        let attachmentsURL = vaultRootURL.appendingPathComponent(Self.attachmentDirectoryName, isDirectory: true)
        guard fileSystem.fileExists(at: attachmentsURL) || fileSystem.createDirectory(at: attachmentsURL) else {
            throw ImportError.createAttachmentDirectoryFailed
        }

        let stem = Self.sanitizedStem(from: suggestedFilename)
        let filename = "\(stem).\(encoded.fileExtension)"
        let destinationURL = VaultMarkdown.resolveFileConflict(for: filename, in: attachmentsURL, fileSystem: fileSystem)

        guard fileSystem.writeData(encoded.data, to: destinationURL) else {
            throw ImportError.writeFailed
        }

        let relativePath = "\(Self.attachmentDirectoryName)/\(destinationURL.lastPathComponent)"
        return VaultImageAttachment(
            fileURL: destinationURL,
            relativePath: relativePath,
            markdownPath: Self.markdownPath(for: relativePath),
            altText: destinationURL.deletingPathExtension().lastPathComponent
        )
    }

    private func encodeImage(_ data: Data) throws -> (data: Data, fileExtension: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImportError.unsupportedImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportError.unsupportedImage
        }

        let preservesAlpha = image.hasMeaningfulAlpha
        let outputType = preservesAlpha ? UTType.png : UTType.jpeg
        let outputExtension = preservesAlpha ? "png" : "jpg"
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            outputType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImportError.unsupportedImage
        }

        let properties: [CFString: Any]
        if preservesAlpha {
            properties = [:]
        } else {
            properties = [kCGImageDestinationLossyCompressionQuality: jpegCompressionQuality]
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.unsupportedImage
        }

        return (outputData as Data, outputExtension)
    }

    public static func sanitizedStem(from suggestedFilename: String?) -> String {
        let fallback = "Image"
        guard let suggestedFilename, !suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }

        let base = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
        let illegal = CharacterSet(charactersIn: "/\\:?\"<>|*")
        let sanitized = base
            .components(separatedBy: illegal)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return fallback }
        return String(sanitized.prefix(80))
    }

    public static func markdownPath(for relativePath: String) -> String {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }
}

private extension CGImage {
    var hasMeaningfulAlpha: Bool {
        switch alphaInfo {
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}
