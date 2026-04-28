import Foundation

public protocol VaultFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isReadableFile(at url: URL) -> Bool
    func readString(from url: URL) -> String?
    func readData(from url: URL) -> Data?
    func readPrefix(from url: URL, maxBytes: Int) -> Data?
    @discardableResult func writeString(_ content: String, to url: URL) -> Bool
    @discardableResult func writeData(_ data: Data, to url: URL) -> Bool
    @discardableResult func delete(at url: URL) -> Bool
    @discardableResult func move(from sourceURL: URL, to destinationURL: URL) -> Bool
    @discardableResult func createDirectory(at url: URL) -> Bool
    func isDownloaded(at url: URL) -> Bool
    func startDownloading(at url: URL)
}

public struct CoordinatedVaultFileSystem: VaultFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isReadableFile(at url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }

    public func readString(from url: URL) -> String? {
        var result: String?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = try? String(contentsOf: coordinatedURL, encoding: .utf8)
        }
        return result
    }

    public func readData(from url: URL) -> Data? {
        var result: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = try? Data(contentsOf: coordinatedURL)
        }
        return result
    }

    public func readPrefix(from url: URL, maxBytes: Int) -> Data? {
        var result: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            guard let handle = try? FileHandle(forReadingFrom: coordinatedURL) else { return }
            result = handle.readData(ofLength: maxBytes)
            try? handle.close()
        }
        return result
    }

    @discardableResult
    public func writeString(_ content: String, to url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: false, encoding: .utf8)
                success = true
            } catch {
                success = false
            }
        }
        return success
    }

    @discardableResult
    public func writeData(_ data: Data, to url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: [])
                success = true
            } catch {
                success = false
            }
        }
        return success
    }

    @discardableResult
    public func delete(at url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
                success = true
            } catch {
                success = false
            }
        }
        return success
    }

    @discardableResult
    public func move(from sourceURL: URL, to destinationURL: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSourceURL, coordinatedDestinationURL in
            do {
                try FileManager.default.moveItem(at: coordinatedSourceURL, to: coordinatedDestinationURL)
                success = true
            } catch {
                success = false
            }
        }
        return success
    }

    @discardableResult
    public func createDirectory(at url: URL) -> Bool {
        var success = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.createDirectory(at: coordinatedURL, withIntermediateDirectories: true)
                success = true
            } catch {
                success = false
            }
        }
        return success
    }

    public func isDownloaded(at url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            guard let status = values.ubiquitousItemDownloadingStatus else { return true }
            return status == .current
        } catch {
            return true
        }
    }

    public func startDownloading(at url: URL) {
        guard !isDownloaded(at: url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
