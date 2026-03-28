import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "CoordinatedFileManager")

/// Wraps file operations in NSFileCoordinator for safe iCloud Drive sync.
/// All methods are synchronous and coordinate with file presenters (iCloud, other apps).
enum CoordinatedFileManager {

    // MARK: - Read

    /// Reads the full contents of a file using coordinated access.
    static func readString(from url: URL) -> String? {
        var result: String?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = try? String(contentsOf: coordinatedURL, encoding: .utf8)
        }

        if let error = coordinationError {
            logger.error("Coordinated read failed for \(url.lastPathComponent): \(error)")
        }
        return result
    }

    /// Reads up to `maxBytes` from the beginning of a file using coordinated access.
    static func readPrefix(from url: URL, maxBytes: Int) -> Data? {
        var result: Data?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            guard let handle = try? FileHandle(forReadingFrom: coordinatedURL) else { return }
            result = handle.readData(ofLength: maxBytes)
            handle.closeFile()
        }

        if let error = coordinationError {
            logger.error("Coordinated prefix read failed for \(url.lastPathComponent): \(error)")
        }
        return result
    }

    // MARK: - Write

    /// Writes a string to a file using coordinated access.
    @discardableResult
    static func writeString(_ content: String, to url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                success = true
            } catch {
                logger.error("Write failed for \(url.lastPathComponent): \(error)")
            }
        }

        if let error = coordinationError {
            logger.error("Coordinated write failed for \(url.lastPathComponent): \(error)")
        }
        return success
    }

    // MARK: - Delete

    /// Deletes a file or directory using coordinated access.
    @discardableResult
    static func delete(at url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
                success = true
            } catch {
                logger.error("Delete failed for \(url.lastPathComponent): \(error)")
            }
        }

        if let error = coordinationError {
            logger.error("Coordinated delete failed for \(url.lastPathComponent): \(error)")
        }
        return success
    }

    // MARK: - Move

    /// Moves a file or directory using coordinated access on both source and destination.
    @discardableResult
    static func move(from sourceURL: URL, to destinationURL: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            writingItemAt: sourceURL, options: .forMoving,
            writingItemAt: destinationURL, options: .forReplacing,
            error: &coordinationError
        ) { coordSource, coordDest in
            do {
                try FileManager.default.moveItem(at: coordSource, to: coordDest)
                success = true
            } catch {
                logger.error("Move failed \(sourceURL.lastPathComponent) → \(destinationURL.lastPathComponent): \(error)")
            }
        }

        if let error = coordinationError {
            logger.error("Coordinated move failed: \(error)")
        }
        return success
    }

    // MARK: - Directory

    /// Creates a directory using coordinated access.
    @discardableResult
    static func createDirectory(at url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.createDirectory(at: coordinatedURL, withIntermediateDirectories: true)
                success = true
            } catch {
                logger.error("Create directory failed for \(url.lastPathComponent): \(error)")
            }
        }

        if let error = coordinationError {
            logger.error("Coordinated create directory failed: \(error)")
        }
        return success
    }

    // MARK: - iCloud Download Status

    /// Checks whether a file is fully downloaded (not evicted by iCloud).
    /// Returns `true` if the file is local or fully downloaded, `false` if it needs downloading.
    static func isDownloaded(at url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            guard let status = values.ubiquitousItemDownloadingStatus else {
                // Not an iCloud file — it's local
                return true
            }
            return status == .current
        } catch {
            // If we can't read the attribute, assume it's available
            return true
        }
    }

    /// Triggers download of an iCloud-evicted file. No-op if already downloaded.
    static func startDownloading(at url: URL) {
        guard !isDownloaded(at: url) else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            logger.info("Started downloading \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to start download for \(url.lastPathComponent): \(error)")
        }
    }
}
