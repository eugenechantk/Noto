import Foundation
import NotoVault

public enum DigestFolderCreation {
    public enum CreationError: Error, LocalizedError, Equatable {
        case invalidName, outsideVault, exists, writeFailed
        public var errorDescription: String? {
            switch self {
            case .invalidName: "Use a folder name without slashes or leading dots."
            case .outsideVault: "Choose a folder inside this library."
            case .exists: "A folder with this name already exists."
            case .writeFailed: "The folder could not be created."
            }
        }
    }
    public static func create(named name: String, in parent: URL, vaultURL: URL,
                              fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) throws -> URL {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"), !name.contains("\\"),
              name.lowercased() != DigestInbox.folderName else { throw CreationError.invalidName }
        let root = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        let folder = parent.standardizedFileURL.resolvingSymlinksInPath()
        guard folder == root || folder.path.hasPrefix(root.path + "/") else { throw CreationError.outsideVault }
        let output = folder.appendingPathComponent(name, isDirectory: true)
        guard !fileSystem.fileExists(at: output) else { throw CreationError.exists }
        guard fileSystem.createDirectory(at: output) else { throw CreationError.writeFailed }
        return output
    }
}
