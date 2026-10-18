import Foundation

/// Pin state lives in the Markdown file, so it follows moves and syncs across devices.
/// The transform preserves all bytes outside the top-level `pinned` field.
public struct NotePinning: Sendable {
    public enum PinError: Error, Equatable { case invalidNote, unreadable, malformedFrontmatter, writeFailed }
    public let vaultRootURL: URL
    private let fileSystem: any VaultFileSystem

    public init(vaultRootURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
        self.fileSystem = fileSystem
    }

    public static func isPinned(in markdown: String) -> Bool {
        let lines = markdown.components(separatedBy: "\n")
        guard let close = frontmatterEnd(lines) else { return false }
        return lines[1..<close].contains { line in
            guard let value = pinValue(in: line) else { return false }
            return value.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }
    }

    public static func settingPinned(_ pinned: Bool, in markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        let newline = markdown.contains("\r\n") ? "\r\n" : "\n"
        guard let close = frontmatterEnd(lines) else {
            guard pinned, lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) != "---" else { return markdown }
            return "---\(newline)pinned: true\(newline)---\(newline)" + markdown
        }
        let indexes = (1..<close).filter { pinValue(in: lines[$0]) != nil }
        if pinned {
            if let first = indexes.first {
                let line = lines[first]
                let comment = line.firstIndex(of: "#").map { index -> String in
                    let prefix = line[..<index]
                    let spaces = prefix.reversed().prefix { $0 == " " || $0 == "\t" }.reversed()
                    return String(spaces) + line[index...].trimmingCharacters(in: .newlines)
                } ?? ""
                lines[first] = "pinned: true" + comment + (line.hasSuffix("\r") ? "\r" : "")
                for index in indexes.dropFirst().reversed() { lines.remove(at: index) }
            } else {
                lines.insert("pinned: true" + (newline == "\r\n" ? "\r" : ""), at: close)
            }
        } else {
            for index in indexes.reversed() { lines.remove(at: index) }
        }
        return lines.joined(separator: "\n")
    }

    public func isPinned(at fileURL: URL) -> Bool {
        guard let markdown = fileSystem.readString(from: fileURL) else { return false }
        return Self.isPinned(in: markdown)
    }

    /// Does not stamp `modified`, rename the file, or serialize other YAML keys.
    @discardableResult
    public func setPinned(_ pinned: Bool, at fileURL: URL) throws -> String {
        guard VaultPathResolver(vaultRootURL: vaultRootURL).relativePath(for: fileURL) != nil,
              fileURL.pathExtension.lowercased() == "md" else { throw PinError.invalidNote }
        guard let markdown = fileSystem.readString(from: fileURL) else { throw PinError.unreadable }
        let updated = Self.settingPinned(pinned, in: markdown)
        if pinned, !Self.isPinned(in: updated) { throw PinError.malformedFrontmatter }
        guard updated == markdown || fileSystem.writeString(updated, to: fileURL) else { throw PinError.writeFailed }
        return updated
    }

    /// Natural title order, with the vault-relative path as the stable tie-breaker.
    /// Same visibility as Library: a capture in `inbox/` counts once it is pinned.
    public func pinnedNotes() -> [VaultNoteRecord] {
        (try? LibraryCatalog(vaultRootURL: vaultRootURL, fileSystem: fileSystem).load().pinned.map(\.note)) ?? []
    }

    private static func frontmatterEnd(_ lines: [String]) -> Int? {
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        return lines.dropFirst().firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }
    }

    private static func pinValue(in line: String) -> String? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":"),
              line[..<colon].trimmingCharacters(in: .whitespaces) == "pinned" else { return nil }
        return String(line[line.index(after: colon)...])
    }
}
