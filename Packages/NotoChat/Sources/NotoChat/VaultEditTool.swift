import Foundation
@_exported import NotoEdit
import NotoVault

// MARK: - Edit proposal carried to the UI

/// The result of a `propose_edits` call, surfaced to the UI as edit-suggestion
/// cards. Carries the raw proposals (for re-resolution at accept/expand time)
/// AND the pre-rendered blocks (for immediate display). Nothing is written.
public struct EditProposal: Sendable, Equatable {
    public var path: String              // vault-relative target note
    public var title: String             // note title for the card header
    public var breadcrumb: String?       // folder breadcrumb when nested
    public var proposals: [ProposedEdit] // raw, re-resolved against current body on accept/expand
    public var blocks: [EditBlock]        // pre-rendered hunks for display
    public var unresolvedCount: Int

    public init(path: String, title: String, breadcrumb: String?,
                proposals: [ProposedEdit], blocks: [EditBlock], unresolvedCount: Int) {
        self.path = path
        self.title = title
        self.breadcrumb = breadcrumb
        self.proposals = proposals
        self.blocks = blocks
        self.unresolvedCount = unresolvedCount
    }
}

// MARK: - Tool definition + dispatch

extension VaultTools {

    static let proposeEditsDefinition = ToolDefinition(function: .init(
        name: "propose_edits",
        description: "Propose edits to a note for the user to review and accept. Edits are NOT applied "
            + "automatically — the user accepts or dismisses each one. Anchor every edit on an EXACT, "
            + "UNIQUE quote copied verbatim from the note (the smallest unique snippet). If an edit "
            + "comes back not-found or ambiguous, re-quote with more surrounding text. Never claim an "
            + "edit was applied.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Vault-relative path of the note to edit. Defaults to the note "
                        + "currently in context if omitted.")
                ]),
                "summary": .object([
                    "type": .string("string"),
                    "description": .string("One short, user-facing line describing the change set.")
                ]),
                "edits": .object([
                    "type": .string("array"),
                    "description": .string("The edits to propose."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("addition"), .string("edit"), .string("deletion")]),
                                "description": .string("addition | edit | deletion")
                            ]),
                            "position": .object([
                                "type": .string("string"),
                                "enum": .array([.string("after"), .string("before"),
                                                .string("start_of_document"), .string("end_of_document")]),
                                "description": .string("addition only: where to insert.")
                            ]),
                            "anchor_text": .object([
                                "type": .string("string"),
                                "description": .string("addition with position after/before: the exact unique "
                                    + "existing text to insert next to.")
                            ]),
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("addition only: the text to insert. To add a NEW line or "
                                    + "list item, START content with a newline (\\n) — e.g. anchor after the "
                                    + "previous bullet with content \"\\n- Eggs\". Do NOT use an `edit` that "
                                    + "repeats the anchor text just to append after it.")
                            ]),
                            "target": .object([
                                "type": .string("string"),
                                "description": .string("edit/deletion: the exact unique existing text to replace "
                                    + "or remove.")
                            ]),
                            "replacement": .object([
                                "type": .string("string"),
                                "description": .string("edit only: the new text that replaces target.")
                            ])
                        ]),
                        "required": .array([.string("type")])
                    ])
                ])
            ]),
            "required": .array([.string("edits")])
        ])
    ))

    /// Run `propose_edits`: read the target note, resolve the proposals against
    /// its body, and return the rendered blocks (for the UI) plus a status
    /// summary (for the model). Does NOT write anything.
    public func proposeEdits(arguments json: String, defaultPath: String?) -> ToolRunResult {
        let args = Self.parseArguments(json)
        let rawPath = (args["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let path = rawPath ?? defaultPath, !path.isEmpty else {
            return .init(output: "Error: propose_edits requires a \"path\" (the note to edit).",
                         readPath: nil, summary: "propose_edits: missing path")
        }
        guard let body = rawBody(path: path) else {
            return .init(output: "Error: could not read \"\(path)\" to propose edits.",
                         readPath: nil, summary: "propose_edits: read failed")
        }
        let proposals = Self.parseProposedEdits(args["edits"])
        guard !proposals.isEmpty else {
            return .init(output: "Error: propose_edits needs at least one valid edit in \"edits\".",
                         readPath: nil, summary: "propose_edits: no edits")
        }

        let (blocks, unresolved) = EditApplier.plan(proposals, in: body)
        let title = NotoEditPath.title(path)
        let breadcrumb = NotoEditPath.breadcrumb(path)
        let proposal = EditProposal(
            path: path, title: title, breadcrumb: breadcrumb.isEmpty ? nil : breadcrumb,
            proposals: proposals, blocks: blocks, unresolvedCount: unresolved.count
        )

        var result = ToolRunResult(
            output: Self.proposeOutput(path: path, blocks: blocks, unresolved: unresolved),
            readPath: nil,
            summary: "proposed \(blocks.count) edit\(blocks.count == 1 ? "" : "s") to \(title)"
        )
        result.editProposal = proposal
        return result
    }

    /// Read a note's BODY (frontmatter stripped) for editing. Raw — no `// path` header.
    func rawBody(path: String) -> String? {
        guard let url = resolve(path) else { return nil }
        guard let content = readRaw(url) else { return nil }
        return Self.strippingFrontmatter(content)
    }

    func readRaw(_ url: URL) -> String? {
        if let s = fs.readString(from: url) { return s }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Arg parsing

    static func parseProposedEdits(_ any: Any?) -> [ProposedEdit] {
        guard let array = any as? [[String: Any]] else { return [] }
        var edits: [ProposedEdit] = []
        for item in array {
            guard let type = item["type"] as? String else { continue }
            func str(_ key: String) -> String { normalizeEscapes((item[key] as? String) ?? "") }
            switch type {
            case "addition":
                let content = str("content")
                let position = (item["position"] as? String) ?? "after"
                let anchorText = str("anchor_text")
                let anchor: Anchor
                switch position {
                case "before": anchor = .before(anchorText)
                case "start_of_document": anchor = .startOfDocument
                case "end_of_document": anchor = .endOfDocument
                default: anchor = .after(anchorText)
                }
                edits.append(.addition(anchor: anchor, content: content))
            case "edit":
                edits.append(.edit(target: str("target"), replacement: str("replacement")))
            case "deletion":
                edits.append(.deletion(target: str("target")))
            default:
                continue
            }
        }
        return edits
    }

    /// Models often emit literal escape sequences (`\n`, `\t`) in tool-call string
    /// values instead of real characters (double-escaped JSON), which would write
    /// a literal backslash-n into the note. Normalize the common ones to the real
    /// characters — note text virtually never wants a literal `\n`.
    static func normalizeEscapes(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        return s
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    // MARK: Output for the model

    static func proposeOutput(path: String, blocks: [EditBlock], unresolved: [ResolvedOp]) -> String {
        var lines: [String] = []
        lines.append("Proposed \(blocks.count) edit block\(blocks.count == 1 ? "" : "s") to \(path), "
            + "shown to the user to accept or dismiss (NOT yet applied).")
        if !unresolved.isEmpty {
            lines.append("\(unresolved.count) edit\(unresolved.count == 1 ? "" : "s") could not be placed:")
            for op in unresolved {
                switch op.status {
                case .unresolved(.notFound):
                    lines.append("- not found — the quoted text isn't in the note; re-quote it exactly.")
                case .unresolved(.ambiguous(let n)):
                    lines.append("- ambiguous (\(n) matches) — add more surrounding text so the quote is unique.")
                case .unresolved(.empty):
                    lines.append("- empty target/anchor — provide the exact text to anchor on.")
                case .resolved:
                    break
                }
            }
            lines.append("Re-call propose_edits for the unplaced ones with better quotes if you want them included.")
        }
        if blocks.isEmpty && unresolved.isEmpty {
            lines.append("No edits were produced.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Frontmatter

    /// Drop a leading YAML frontmatter block (`---\n…\n---\n`) and return the body.
    static func strippingFrontmatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return content }
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return content
        }
        return lines[(close + 1)...].joined(separator: "\n")
    }
}

// MARK: - Path helpers (mirror the app's NotoChatPath; kept in-package for the tool)

enum NotoEditPath {
    static func title(_ path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    }
    static func breadcrumb(_ path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: " › ")
    }
}
