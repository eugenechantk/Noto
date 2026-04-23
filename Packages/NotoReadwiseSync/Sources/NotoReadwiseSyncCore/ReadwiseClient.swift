import Foundation

public enum ReadwiseClientError: Error, CustomStringConvertible {
    case invalidURL
    case badStatus(Int, String)

    public var description: String {
        switch self {
        case .invalidURL:
            "Could not construct Readwise export URL."
        case .badStatus(let status, let body):
            "Readwise request failed with HTTP \(status): \(body)"
        }
    }
}

public struct ReadwiseClient: Sendable {
    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func fetchExport(
        updatedAfter: String? = nil,
        includeDeleted: Bool = true,
        limit: Int? = nil
    ) async throws -> [ReadwiseBook] {
        var books: [ReadwiseBook] = []
        var nextPageCursor: String?

        repeat {
            let page = try await fetchExportPage(
                updatedAfter: updatedAfter,
                includeDeleted: includeDeleted,
                pageCursor: nextPageCursor
            )
            if let limit {
                books.append(contentsOf: page.results.prefix(max(0, limit - books.count)))
                if books.count >= limit {
                    break
                }
            } else {
                books.append(contentsOf: page.results)
            }
            nextPageCursor = page.nextPageCursor
        } while nextPageCursor != nil

        return books
    }

    public func fetchReaderDocuments(
        id: String? = nil,
        updatedAfter: String? = nil,
        location: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        limit: Int? = nil
    ) async throws -> [ReaderDocument] {
        var documents: [ReaderDocument] = []
        var nextPageCursor: String?

        repeat {
            let page = try await fetchReaderPage(
                id: id,
                updatedAfter: updatedAfter,
                location: location,
                category: category,
                tags: tags,
                limit: limit,
                pageCursor: nextPageCursor
            )
            if let limit {
                documents.append(contentsOf: page.results.prefix(max(0, limit - documents.count)))
                if documents.count >= limit {
                    break
                }
            } else {
                documents.append(contentsOf: page.results)
            }
            nextPageCursor = page.nextPageCursor
        } while nextPageCursor != nil && id == nil

        return documents
    }

    private func fetchExportPage(
        updatedAfter: String?,
        includeDeleted: Bool,
        pageCursor: String?
    ) async throws -> ReadwiseExportPage {
        var components = URLComponents(string: "https://readwise.io/api/v2/export/")
        var items: [URLQueryItem] = []
        if let updatedAfter {
            items.append(URLQueryItem(name: "updatedAfter", value: updatedAfter))
        }
        if includeDeleted {
            items.append(URLQueryItem(name: "includeDeleted", value: "true"))
        }
        if let pageCursor {
            items.append(URLQueryItem(name: "pageCursor", value: pageCursor))
        }
        components?.queryItems = items.isEmpty ? nil : items

        guard let url = components?.url else {
            throw ReadwiseClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReadwiseClientError.badStatus(-1, "Missing HTTP response")
        }

        if http.statusCode == 429,
           let retryAfter = http.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter) {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return try await fetchExportPage(
                updatedAfter: updatedAfter,
                includeDeleted: includeDeleted,
                pageCursor: pageCursor
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw ReadwiseClientError.badStatus(http.statusCode, body)
        }

        return try JSONDecoder.readwise.decode(ReadwiseExportPage.self, from: data)
    }

    private func fetchReaderPage(
        id: String?,
        updatedAfter: String?,
        location: String?,
        category: String?,
        tags: [String],
        limit: Int?,
        pageCursor: String?
    ) async throws -> ReaderListPage {
        var components = URLComponents(string: "https://readwise.io/api/v3/list/")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "withHtmlContent", value: "true"),
            URLQueryItem(name: "withRawSourceUrl", value: "true"),
        ]
        if let id {
            items.append(URLQueryItem(name: "id", value: id))
        }
        if let updatedAfter {
            items.append(URLQueryItem(name: "updatedAfter", value: updatedAfter))
        }
        if let location {
            items.append(URLQueryItem(name: "location", value: location))
        }
        if let category {
            items.append(URLQueryItem(name: "category", value: category))
        }
        for tag in tags {
            items.append(URLQueryItem(name: "tag", value: tag))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100))))
        }
        if let pageCursor {
            items.append(URLQueryItem(name: "pageCursor", value: pageCursor))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw ReadwiseClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReadwiseClientError.badStatus(-1, "Missing HTTP response")
        }

        if http.statusCode == 429,
           let retryAfter = http.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter) {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return try await fetchReaderPage(
                id: id,
                updatedAfter: updatedAfter,
                location: location,
                category: category,
                tags: tags,
                limit: limit,
                pageCursor: pageCursor
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw ReadwiseClientError.badStatus(http.statusCode, body)
        }

        return try JSONDecoder.readwise.decode(ReaderListPage.self, from: data)
    }
}
