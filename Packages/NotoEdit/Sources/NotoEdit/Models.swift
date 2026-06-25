import Foundation

// MARK: - What the model proposes

/// One of the three edit primitives the AI can author. Anchors are *text* (exact
/// quotes from the note), not character offsets — LLMs are unreliable with offsets.
public enum ProposedEdit: Sendable, Equatable {
    /// Insert `content` relative to an anchor.
    case addition(anchor: Anchor, content: String)
    /// Replace the (unique) `target` text with `replacement`.
    case edit(target: String, replacement: String)
    /// Remove the (unique) `target` text.
    case deletion(target: String)
}

/// Where an addition is inserted, relative to existing text.
public enum Anchor: Sendable, Equatable {
    case after(String)        // insert immediately after this exact text
    case before(String)       // insert immediately before this exact text
    case startOfDocument
    case endOfDocument
}

/// The kind of change a resolved operation makes (drives diff-row coloring).
public enum EditKind: Sendable, Equatable {
    case addition   // pure insertion (green +)
    case edit       // replace (red − then green +)
    case deletion   // removal (red −)
}

// MARK: - Resolution against a concrete document

/// Why a proposed edit could not be turned into an actionable operation.
public enum ResolutionStatus: Sendable, Equatable {
    case resolved
    case unresolved(Reason)

    public enum Reason: Sendable, Equatable {
        case notFound              // 0 matches for the anchor/target
        case ambiguous(count: Int) // >1 matches — the quote isn't unique
        case empty                 // empty anchor/target/content
    }
}

/// One operation resolved against a specific note body: a character range to
/// replace with `replacement` (zero-length range + non-empty replacement = a
/// pure insertion; non-empty range + empty replacement = a deletion).
public struct ResolvedOp: Sendable, Equatable {
    public let kind: EditKind
    public let range: NSRange        // range in the body to splice (against the resolved-against body)
    public let replacement: String   // text spliced in ("" for deletion)
    public let status: ResolutionStatus
    public let source: ProposedEdit  // the proposal this op came from (for re-resolution)

    public init(kind: EditKind, range: NSRange, replacement: String,
                status: ResolutionStatus, source: ProposedEdit) {
        self.kind = kind
        self.range = range
        self.replacement = replacement
        self.status = status
        self.source = source
    }

    public var isResolved: Bool { status == .resolved }
}

/// An EDIT BLOCK = one contiguous spot in the note = the user-facing review/accept
/// unit (a diff hunk). Holds one or more same-spot operations coalesced together,
/// the union range they cover, and a renderable diff preview.
public struct EditBlock: Sendable, Equatable {
    public let ops: [ResolvedOp]     // 1+ resolved ops at this spot
    public let span: NSRange         // union range covered, in the resolved-against body
    public let preview: DiffPreview  // context + −/+ rows to render
    public let locationHint: String? // nearest preceding heading, for a quiet label

    public init(ops: [ResolvedOp], span: NSRange, preview: DiffPreview, locationHint: String?) {
        self.ops = ops
        self.span = span
        self.preview = preview
        self.locationHint = locationHint
    }

    /// The proposals that formed this block — re-plan these alone to re-resolve
    /// the block independently against the note's current body (accept/expand).
    public var sources: [ProposedEdit] { ops.map(\.source) }
}

// MARK: - Renderable diff

/// A renderable hunk: context + changed lines in display order, with flags for
/// whether more context exists above/below (drives the expand-up/down chevrons).
/// No line numbers — the context lines themselves orient the user.
public struct DiffPreview: Sendable, Equatable {
    public let lines: [DiffLine]
    public let canExpandUp: Bool
    public let canExpandDown: Bool

    public init(lines: [DiffLine], canExpandUp: Bool, canExpandDown: Bool) {
        self.lines = lines
        self.canExpandUp = canExpandUp
        self.canExpandDown = canExpandDown
    }
}

public struct DiffLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case context   // unchanged, dimmed
        case removed   // − red
        case added     // + green
    }
    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

// MARK: - Errors

public enum EditApplyError: Error, Sendable, Equatable {
    case overlappingEdits     // two ops cover overlapping ranges
    case rangeOutOfBounds     // a range no longer fits the body (stale)
    case noResolvedOps        // nothing to apply
}
