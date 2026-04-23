import Foundation

public struct SidebarTreeNode: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case folder(isExpanded: Bool)
        case note
    }

    public let id: String
    public let kind: Kind
    public let depth: Int
    public let name: String
    public let url: URL
    public let modifiedAt: Date
    public let noteID: UUID?

    public init(kind: Kind, depth: Int, name: String, url: URL, modifiedAt: Date, noteID: UUID? = nil) {
        let normalizedURL = url.standardizedFileURL
        self.id = normalizedURL.path
        self.kind = kind
        self.depth = depth
        self.name = name
        self.url = normalizedURL
        self.modifiedAt = modifiedAt
        self.noteID = noteID
    }
}

public struct VaultTreeRow: Identifiable, Equatable, Hashable, Sendable {
    public let item: VaultListItem
    public let depth: Int
    public let isExpanded: Bool?

    public var id: UUID {
        item.id
    }

    public init(item: VaultListItem, depth: Int, isExpanded: Bool?) {
        self.item = item
        self.depth = depth
        self.isExpanded = isExpanded
    }
}

public struct SidebarTreeLoader {
    private let directoryLoader: VaultDirectoryLoader

    public init(directoryLoader: VaultDirectoryLoader = VaultDirectoryLoader()) {
        self.directoryLoader = directoryLoader
    }

    public func loadRows(
        rootURL: URL,
        expandedFolderURLs: Set<URL>? = nil
    ) throws -> [SidebarTreeNode] {
        try loadTreeRows(rootURL: rootURL, expandedFolderURLs: expandedFolderURLs)
            .map { SidebarTreeNode(row: $0) }
    }

    public func loadTreeRows(
        rootURL: URL,
        expandedFolderURLs: Set<URL>? = nil
    ) throws -> [VaultTreeRow] {
        let normalizedExpanded = expandedFolderURLs.map {
            Set($0.map { $0.standardizedFileURL })
        }
        return try loadChildren(
            in: rootURL.standardizedFileURL,
            depth: 0,
            expandedFolderURLs: normalizedExpanded
        )
    }

    public func filterRows(
        _ rows: [SidebarTreeNode],
        matching query: String
    ) -> [SidebarTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }

        var includedIndexes = Set<Int>()
        for (index, row) in rows.enumerated() where row.name.localizedCaseInsensitiveContains(trimmed) {
            includedIndexes.insert(index)
            includeAncestors(of: index, in: rows, includedIndexes: &includedIndexes)
        }

        return rows.indices
            .filter { includedIndexes.contains($0) }
            .map { rows[$0] }
    }

    public func searchRows(
        rootURL: URL,
        matching query: String
    ) throws -> [SidebarTreeNode] {
        let rows = try loadRows(rootURL: rootURL)
        return filterRows(rows, matching: query)
    }

    private func loadChildren(
        in directoryURL: URL,
        depth: Int,
        expandedFolderURLs: Set<URL>?
    ) throws -> [VaultTreeRow] {
        let items = try directoryLoader.loadItems(in: directoryURL)

        var rows: [VaultTreeRow] = []
        for item in items {
            switch item {
            case .folder(let folder):
                let isExpanded = expandedFolderURLs?.contains(folder.folderURL.standardizedFileURL) ?? true
                rows.append(VaultTreeRow(item: item, depth: depth, isExpanded: isExpanded))
                guard isExpanded else { continue }
                rows += try loadChildren(
                    in: folder.folderURL,
                    depth: depth + 1,
                    expandedFolderURLs: expandedFolderURLs
                )
            case .note:
                rows.append(VaultTreeRow(item: item, depth: depth, isExpanded: nil))
            }
        }
        return rows
    }

    private func includeAncestors(
        of index: Int,
        in rows: [SidebarTreeNode],
        includedIndexes: inout Set<Int>
    ) {
        var nextAncestorDepth = rows[index].depth - 1
        guard nextAncestorDepth >= 0 else { return }

        var cursor = index - 1
        while cursor >= 0, nextAncestorDepth >= 0 {
            let candidate = rows[cursor]
            if candidate.depth == nextAncestorDepth, case .folder = candidate.kind {
                includedIndexes.insert(cursor)
                nextAncestorDepth -= 1
            }
            cursor -= 1
        }
    }

}

private extension SidebarTreeNode {
    init(row: VaultTreeRow) {
        switch row.item {
        case .folder(let folder):
            self.init(
                kind: .folder(isExpanded: row.isExpanded ?? false),
                depth: row.depth,
                name: folder.name,
                url: folder.folderURL,
                modifiedAt: folder.modifiedDate
            )
        case .note(let note):
            self.init(
                kind: .note,
                depth: row.depth,
                name: note.title,
                url: note.fileURL,
                modifiedAt: note.modifiedDate,
                noteID: note.id
            )
        }
    }
}
