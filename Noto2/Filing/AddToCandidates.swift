import Foundation
import NotoDigest
import NotoSearch
import NotoVault

/// A note the Add to sheet can offer (feature doc C7).
struct AddToCandidate: Identifiable, Hashable {
    let url: URL
    let title: String
    let relativePath: String
    /// The note's folders as breadcrumbs ("Projects › Noto"); empty at the root.
    let folderPath: String
    let modifiedAt: Date
    var snippet: String = ""

    var id: String { relativePath }
}

/// What the Add to sheet lists: **Similar** (meaning matches for the draft),
/// **Recent** (most recently edited), and title matches while typing. The
/// inbox is never a destination — a capture added to another capture is lost
/// from view.
enum AddToCandidates {
    /// One semantic-index hit, reduced to what the ranking needs.
    struct SimilarHit: Equatable {
        let relativePath: String
        let score: Float
    }

    /// Same floor and gap as Noto 2's Search (`SearchModel`): unrelated notes
    /// score ≈0.70–0.73 with the granite model, related ones ≈0.80–0.86.
    static let similarMinScore: Float = 0.76
    static let similarRelativeGap: Float = 0.12
    static let similarLimit = 3
    static let recentLimit = 30

    static func recent(from rows: [SidebarTreeNode], vaultURL: URL) -> [AddToCandidate] {
        let resolver = VaultPathResolver(vaultRootURL: vaultURL)
        return rows.compactMap { row -> AddToCandidate? in
            guard case .note = row.kind, let path = resolver.relativePath(for: row.url), !isInInbox(path) else { return nil }
            return AddToCandidate(
                url: row.url,
                title: row.name,
                relativePath: path,
                folderPath: breadcrumbs(forNoteAt: path),
                modifiedAt: row.modifiedAt
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Title matches for a typed query, titles that start with it first; each
    /// group keeps the candidates' (recency) order.
    static func matching(_ candidates: [AddToCandidate], query: String) -> [AddToCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        let hits = candidates.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
        let prefix = hits.filter { $0.title.lowercased().hasPrefix(trimmed.lowercased()) }
        return prefix + hits.filter { !$0.title.lowercased().hasPrefix(trimmed.lowercased()) }
    }

    /// Strong meaning matches, one per note, best first, only for notes that
    /// still exist in `candidates`.
    static func similar(from hits: [SimilarHit], candidates: [AddToCandidate]) -> [AddToCandidate] {
        let byPath = Dictionary(candidates.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = hits.filter { !isInInbox($0.relativePath) && byPath[$0.relativePath] != nil }
        guard let best = eligible.map(\.score).max() else { return [] }
        var seen = Set<String>()
        var result: [AddToCandidate] = []
        for hit in eligible.sorted(by: { $0.score > $1.score }) {
            guard hit.score >= similarMinScore, hit.score >= best - similarRelativeGap,
                  seen.insert(hit.relativePath).inserted, let candidate = byPath[hit.relativePath] else { continue }
            result.append(candidate)
            if result.count == similarLimit { break }
        }
        return result
    }

    /// Uses the content index while retaining title matches for notes whose
    /// most recent save has not reached the index yet.
    static func searchResults(_ results: [SearchResult], candidates: [AddToCandidate], vaultURL: URL, query: String) -> [AddToCandidate] {
        let resolver = VaultPathResolver(vaultRootURL: vaultURL)
        let byPath = Dictionary(candidates.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        var positions: [String: Int] = [:]
        var found: [AddToCandidate] = []
        for hit in results {
            guard let path = resolver.relativePath(for: hit.fileURL), !isInInbox(path),
                  var candidate = byPath[path] else { continue }
            candidate.snippet = DigestMarkdown.contentSnippet(hit.snippet, title: candidate.title)
            if let index = positions[path] {
                // A note-title hit may precede the useful section-content hit.
                if found[index].snippet.isEmpty { found[index].snippet = candidate.snippet }
                continue
            }
            positions[path] = found.count
            found.append(candidate)
        }
        for candidate in matching(candidates, query: query) where positions[candidate.id] == nil {
            positions[candidate.id] = found.count
            found.append(candidate)
        }
        return Array(found.prefix(40))
    }

    static func isInInbox(_ relativePath: String) -> Bool {
        relativePath.lowercased().hasPrefix(DigestInbox.folderName.lowercased() + "/")
    }

    static func breadcrumbs(forNoteAt relativePath: String) -> String {
        relativePath.split(separator: "/").dropLast().joined(separator: " › ")
    }
}

/// A folder the New note sheet can file into (feature doc C8).
struct NewNoteFolder: Identifiable, Hashable {
    let url: URL
    let name: String
    /// Breadcrumbs from the vault root ("Projects › Noto"); empty for the root.
    let path: String
    /// Notes directly inside this folder, matching the folder drill's contents.
    var noteCount: Int = 0

    var id: URL { url }
    var isRoot: Bool { path.isEmpty }

    static let rootName = "Vault root"

    /// The vault root first, then every folder in tree order, never `inbox/`.
    static func options(from rows: [SidebarTreeNode], vaultURL: URL) -> [NewNoteFolder] {
        let root = vaultURL.standardizedFileURL
        let resolver = VaultPathResolver(vaultRootURL: root)
        let noteRows = rows.filter { row in
            if case .note = row.kind { return true }
            return false
        }
        let noteCounts = Dictionary(grouping: noteRows) {
            $0.url.deletingLastPathComponent().standardizedFileURL.path
        }.mapValues(\.count)
        var folders = [NewNoteFolder(url: root, name: rootName, path: "", noteCount: noteCounts[root.path, default: 0])]
        for row in rows {
            guard case .folder = row.kind else { continue }
            guard row.url.lastPathComponent.lowercased() != DigestInbox.folderName.lowercased() else { continue }
            let relative = resolver.relativePath(for: row.url) ?? row.name
            guard !AddToCandidates.isInInbox(relative + "/") else { continue }
            folders.append(NewNoteFolder(
                url: row.url,
                name: row.name,
                path: relative.split(separator: "/").joined(separator: " › "),
                noteCount: noteCounts[row.url.standardizedFileURL.path, default: 0]
            ))
        }
        return folders
    }

    static func recent(_ folders: [NewNoteFolder], notes: [AddToCandidate]) -> [NewNoteFolder] {
        var seen = Set<String>()
        var result: [NewNoteFolder] = []
        // Directory URLs can carry a trailing slash while note parents always do.
        // Their standardized paths identify the same folder in either form.
        let byPath = Dictionary(folders.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        for note in notes.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
            let parent = note.url.deletingLastPathComponent().standardizedFileURL.path
            if let folder = byPath[parent], seen.insert(parent).inserted { result.append(folder) }
            if result.count == 3 { break }
        }
        if result.isEmpty { result = Array(folders.filter { !$0.isRoot }.prefix(3)) }
        return result.isEmpty ? Array(folders.prefix(1)) : result
    }

    static func children(of folder: NewNoteFolder, in folders: [NewNoteFolder]) -> [NewNoteFolder] {
        folders.filter { !$0.isRoot && $0.url.deletingLastPathComponent().standardizedFileURL.path == folder.url.standardizedFileURL.path }
    }

    static func matching(_ folders: [NewNoteFolder], query: String) -> [NewNoteFolder] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.filter {
            !$0.isRoot && ($0.name.localizedCaseInsensitiveContains(trimmed) || $0.path.localizedCaseInsensitiveContains(trimmed))
        }
    }
}
