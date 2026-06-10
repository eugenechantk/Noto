import CoreGraphics
import Foundation
import ImageIO
import Vision
import os.log

private let describerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto.NotoSearch",
    category: "VisionImageDescriber"
)

/// Errors thrown by `VisionImageDescriber`. Only undecodable input throws;
/// Vision pipeline failures degrade to empty results so indexing never stalls
/// on a single image.
public enum VisionImageDescriberError: Error, Equatable {
    case undecodableImageData
}

/// Default `ImageDescribing` implementation backed by Apple Vision.
///
/// Pipeline: decode + downsample via ImageIO (max ~2048px so OCR stays fast
/// and memory-bounded), then run text recognition and image classification on
/// the same `CGImage`. The two requests are performed independently so a
/// classification failure cannot wipe out OCR results (and vice versa).
///
/// Classification threshold: a fixed `confidence >= 0.3` floor (capped at 10
/// labels) instead of `hasMinimumRecall(_:forPrecision:)`. The recall/precision
/// curves Vision uses for that API vary between OS releases, which would make
/// the indexed labels drift without a `describerVersion` bump; a fixed floor
/// keeps output deterministic for a given OS while the max-10 cap bounds noise.
public struct VisionImageDescriber: ImageDescribing {
    /// Languages we ask OCR to prioritize, filtered through the OS's supported
    /// list at runtime so unsupported entries never make `perform` throw.
    private static let preferredRecognitionLanguages = [
        "en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR",
    ]

    /// 1280px keeps screenshot/receipt OCR reliable while roughly halving the
    /// decoded bitmap footprint vs the previous 2048px — the per-image memory
    /// spike was riding the 4 GB-device jetsam ceiling during bulk indexing
    /// (bug 018).
    private static let maxThumbnailPixelSize = 1280
    private static let minimumLabelConfidence: Float = 0.3
    private static let maxLabels = 10

    public let describerVersion = "vision-ocr-labels-v1"

    public init() {}

    public func describe(imageData: Data) throws -> ImageDescription {
        // Drain the decoded bitmap + Vision request internals per image.
        try autoreleasepool {
            let image = try Self.decodeDownsampledImage(imageData)
            let ocrText = Self.recognizedText(in: image)
            let labels = Self.classificationLabels(in: image)
            return ImageDescription(ocrText: ocrText, labels: labels)
        }
    }

    // MARK: - Decoding

    /// Decodes via ImageIO's thumbnail path, which downsamples while decoding —
    /// far cheaper than decoding a full-size image and scaling afterwards.
    private static func decodeDownsampledImage(_ data: Data) throws -> CGImage {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw VisionImageDescriberError.undecodableImageData
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw VisionImageDescriberError.undecodableImageData
        }
        return image
    }

    // MARK: - OCR

    private static func recognizedText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        if let supported = try? request.supportedRecognitionLanguages() {
            let languages = preferredRecognitionLanguages.filter(supported.contains)
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            describerLogger.error("OCR failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Classification

    private static func classificationLabels(in image: CGImage) -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            describerLogger.error("Classification failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let observations = request.results ?? []
        return observations
            .filter { $0.confidence >= minimumLabelConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxLabels)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
}
