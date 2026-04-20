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

    public init(kind: Kind, depth: Int, name: String, url: URL, modifiedAt: Date) {
        let normalizedURL = url.standardizedFileURL
        self.id = normalizedURL.path
        self.kind = kind
        self.depth = depth
        self.name = name
        self.url = normalizedURL
        self.modifiedAt = modifiedAt
    }
}

public struct SidebarTreeLoader {
    public init() {}

    public func loadRows(
        rootURL: URL,
        expandedFolderURLs: Set<URL>? = nil
    ) throws -> [SidebarTreeNode] {
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

    private func loadChildren(
        in directoryURL: URL,
        depth: Int,
        expandedFolderURLs: Set<URL>?
    ) throws -> [SidebarTreeNode] {
        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var folders: [SidebarTreeNode] = []
        var notes: [SidebarTreeNode] = []

        for childURL in children {
            let values = try childURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if values.isDirectory == true {
                let normalizedURL = childURL.standardizedFileURL
                let isExpanded = expandedFolderURLs?.contains(normalizedURL) ?? true
                folders.append(SidebarTreeNode(
                    kind: .folder(isExpanded: isExpanded),
                    depth: depth,
                    name: normalizedURL.lastPathComponent,
                    url: normalizedURL,
                    modifiedAt: modifiedAt
                ))
            } else if childURL.pathExtension == "md" {
                let normalizedURL = childURL.standardizedFileURL
                notes.append(SidebarTreeNode(
                    kind: .note,
                    depth: depth,
                    name: normalizedURL.deletingPathExtension().lastPathComponent,
                    url: normalizedURL,
                    modifiedAt: modifiedAt
                ))
            }
        }

        folders.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        notes.sort { $0.modifiedAt > $1.modifiedAt }

        var rows: [SidebarTreeNode] = []
        for folder in folders {
            rows.append(folder)
            if case .folder(isExpanded: true) = folder.kind {
                rows += try loadChildren(
                    in: folder.url,
                    depth: depth + 1,
                    expandedFolderURLs: expandedFolderURLs
                )
            }
        }
        rows += notes
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
