import Foundation

/// Adapts ranked hits for a note list without changing their search identity,
/// matching section, score, or order. The caller supplies the vault's title rule.
public enum SearchResultDisplayTitles {
    public static func resolving(
        _ results: [SearchResult],
        titleForNote: (URL) -> String?
    ) -> [SearchResult] {
        var titles: [URL: String] = [:]
        var attempted = Set<URL>()
        return results.map { result in
            let url = result.fileURL.standardizedFileURL
            if attempted.insert(url).inserted,
               let title = titleForNote(url), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titles[url] = title
            }
            guard let title = titles[url] else { return result }
            return SearchResult(
                id: result.id, kind: result.kind, noteID: result.noteID, fileURL: result.fileURL,
                title: title, breadcrumb: result.breadcrumb, snippet: result.snippet,
                lineStart: result.lineStart, score: result.score, updatedAt: result.updatedAt,
                createdAt: result.createdAt
            )
        }
    }
}
