import Foundation

public struct VaultPathResolver: Sendable {
    public let vaultRootURL: URL

    public init(vaultRootURL: URL) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
    }

    public func relativePath(for fileURL: URL) -> String? {
        let rootPath = vaultRootURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }

    public func noteURL(forVaultRelativePath relativePath: String) -> URL? {
        let decodedPath = relativePath.removingPercentEncoding ?? relativePath
        let components = decodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        var fileURL = vaultRootURL
        for component in components {
            fileURL.appendPathComponent(component)
        }
        fileURL = fileURL.standardizedFileURL

        guard contains(fileURL),
              fileURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else {
            return nil
        }
        return fileURL
    }

    public func contains(_ fileURL: URL) -> Bool {
        let rootPath = vaultRootURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }
}
