import Foundation

public struct VaultFolderRecord: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let folderURL: URL
    public let name: String
    public let modifiedDate: Date
    public let folderCount: Int
    public let itemCount: Int

    public init(id: UUID, folderURL: URL, name: String, modifiedDate: Date, folderCount: Int, itemCount: Int) {
        self.id = id
        self.folderURL = folderURL
        self.name = name
        self.modifiedDate = modifiedDate
        self.folderCount = folderCount
        self.itemCount = itemCount
    }
}

public struct FolderRepository: Sendable {
    public let directoryURL: URL
    public let fileSystem: any VaultFileSystem

    public init(directoryURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.fileSystem = fileSystem
    }

    public func createFolder(named name: String) -> VaultFolderRecord {
        let folderURL = directoryURL.appendingPathComponent(name)
        _ = fileSystem.createDirectory(at: folderURL)
        return VaultFolderRecord(
            id: VaultDirectoryLoader.stableID(for: folderURL),
            folderURL: folderURL,
            name: name,
            modifiedDate: Date(),
            folderCount: 0,
            itemCount: 0
        )
    }

    @discardableResult
    public func deleteFolder(at folderURL: URL) -> Bool {
        fileSystem.delete(at: folderURL)
    }

    @discardableResult
    public func moveFolder(
        id: UUID,
        folderURL: URL,
        name: String,
        modifiedDate: Date,
        folderCount: Int,
        itemCount: Int,
        to destinationDirectory: URL
    ) -> VaultFolderRecord {
        let normalizedDestination = destinationDirectory.standardizedFileURL
        if folderURL.deletingLastPathComponent().standardizedFileURL == normalizedDestination {
            return VaultFolderRecord(
                id: id,
                folderURL: folderURL,
                name: name,
                modifiedDate: modifiedDate,
                folderCount: folderCount,
                itemCount: itemCount
            )
        }

        if !fileSystem.fileExists(at: normalizedDestination),
           !fileSystem.createDirectory(at: normalizedDestination) {
            return VaultFolderRecord(
                id: id,
                folderURL: folderURL,
                name: name,
                modifiedDate: modifiedDate,
                folderCount: folderCount,
                itemCount: itemCount
            )
        }

        let destinationURL = VaultMarkdown.resolveFolderConflict(
            named: name,
            in: normalizedDestination,
            fileSystem: fileSystem
        )
        guard fileSystem.move(from: folderURL, to: destinationURL) else {
            return VaultFolderRecord(
                id: id,
                folderURL: folderURL,
                name: name,
                modifiedDate: modifiedDate,
                folderCount: folderCount,
                itemCount: itemCount
            )
        }

        return VaultFolderRecord(
            id: id,
            folderURL: destinationURL,
            name: destinationURL.lastPathComponent,
            modifiedDate: modifiedDate,
            folderCount: folderCount,
            itemCount: itemCount
        )
    }
}
