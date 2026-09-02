import Foundation
import NotoVault

/// Compatibility wrapper while vault filesystem callers migrate to `NotoVault`.
enum CoordinatedFileManager {
    private static let fileSystem = CoordinatedVaultFileSystem()

    static func readString(from url: URL) -> String? {
        fileSystem.readString(from: url)
    }

    static func readPrefix(from url: URL, maxBytes: Int) -> Data? {
        fileSystem.readPrefix(from: url, maxBytes: maxBytes)
    }

    static func readData(from url: URL) -> Data? {
        fileSystem.readData(from: url)
    }

    @discardableResult
    static func writeString(_ content: String, to url: URL) -> Bool {
        let success = fileSystem.writeString(content, to: url)
        if !success {
            DebugTrace.record("coord write failed file=\(url.lastPathComponent)")
        }
        return success
    }

    @discardableResult
    static func writeData(_ data: Data, to url: URL) -> Bool {
        let success = fileSystem.writeData(data, to: url)
        if !success {
            DebugTrace.record("coord data write failed file=\(url.lastPathComponent)")
        }
        return success
    }

    @discardableResult
    static func delete(at url: URL) -> Bool {
        fileSystem.delete(at: url)
    }

    @discardableResult
    static func move(from sourceURL: URL, to destinationURL: URL) -> Bool {
        fileSystem.move(from: sourceURL, to: destinationURL)
    }

    @discardableResult
    static func createDirectory(at url: URL) -> Bool {
        fileSystem.createDirectory(at: url)
    }

    static func isDownloaded(at url: URL) -> Bool {
        fileSystem.isDownloaded(at: url)
    }

    static func startDownloading(at url: URL) {
        fileSystem.startDownloading(at: url)
    }
}
