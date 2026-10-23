import Foundation

/// A Markdown-body share item. File-backed items read the full note on demand,
/// keeping context menus free of synchronous file reads and stale previews.
public struct NoteMarkdownShare: Sendable {
    private let source: Source

    private enum Source: Sendable {
        case markdown(String)
        case body(String)
        case file(URL)
    }

    public init(markdown: String) { source = .markdown(markdown) }
    public init(body: String) { source = .body(body) }
    public init(fileURL: URL) { source = .file(fileURL) }

    public func loadText() async throws -> String {
        switch source {
        case .markdown(let text): return VaultMarkdown.stripFrontmatter(text)
        case .body(let text): return text
        case .file(let url):
            let result = await BoundedFileRead.run(timeout: 8) {
                CoordinatedVaultFileSystem().readString(from: url)
            }
            guard case .value(let text) = result else { throw CocoaError(.fileReadUnknown) }
            return VaultMarkdown.stripFrontmatter(text)
        }
    }
}
