import Foundation

public struct MarkdownSearchEngine {
    private let store: SearchIndexStore
    private let vaultURL: URL

    public init(store: SearchIndexStore, vaultURL: URL) {
        self.store = store
        self.vaultURL = vaultURL.standardizedFileURL
    }

    public func search(_ query: String, scope: SearchScope = .titleAndContent, limit: Int = 50) throws -> [SearchResult] {
        try store.search(query: query, scope: scope, vaultURL: vaultURL, limit: limit)
    }

    public static func ftsQuery(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let quoteCount = trimmed.filter { $0 == "\"" }.count
        guard quoteCount.isMultiple(of: 2) else {
            return tokenQuery(trimmed.replacingOccurrences(of: "\"", with: ""))
        }

        var phrases: [String] = []
        var remainder = ""
        var current = ""
        var insideQuote = false

        for character in trimmed {
            if character == "\"" {
                if insideQuote {
                    let phrase = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !phrase.isEmpty {
                        phrases.append(#""\#(phrase.replacingOccurrences(of: "\"", with: "\"\""))""#)
                    }
                    current = ""
                } else {
                    remainder.append(" ")
                }
                insideQuote.toggle()
                continue
            }

            if insideQuote {
                current.append(character)
            } else {
                remainder.append(character)
            }
        }

        let unquoted = tokenQuery(remainder)
        return (phrases + (unquoted.isEmpty ? [] : [unquoted])).joined(separator: " ")
    }

    public static func boostTerms(for query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func titleOnlyFTSQuery(for query: String) -> String {
        let ftsQuery = ftsQuery(for: query)
        guard !ftsQuery.isEmpty else { return "" }
        return "{title} : (\(ftsQuery))"
    }

    private static func tokenQuery(_ query: String) -> String {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumericsAndUnderscore.inverted)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens
            .map { token in
                token.count >= 2 ? "\(token)*" : token
            }
            .joined(separator: " ")
    }
}

private extension CharacterSet {
    static let alphanumericsAndUnderscore: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_")
        return set
    }()
}
