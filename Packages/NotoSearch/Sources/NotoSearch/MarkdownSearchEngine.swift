import Foundation

public struct MarkdownSearchEngine {
    private let store: SearchIndexStore
    private let vaultURL: URL

    public init(store: SearchIndexStore, vaultURL: URL) {
        self.store = store
        self.vaultURL = vaultURL.standardizedFileURL
    }

    public func search(_ query: String, limit: Int = 50) throws -> [SearchResult] {
        try store.search(query: query, vaultURL: vaultURL, limit: limit)
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

    private static func tokenQuery(_ query: String) -> String {
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map(cleanToken)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens.enumerated().map { index, token in
            index == tokens.count - 1 && token.count >= 2 ? "\(token)*" : token
        }.joined(separator: " ")
    }

    private static func cleanToken(_ token: String) -> String {
        token
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
