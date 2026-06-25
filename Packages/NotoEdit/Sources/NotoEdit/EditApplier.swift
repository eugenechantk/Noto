import Foundation

/// Pure engine that resolves `ProposedEdit`s against a note body, coalesces them
/// into diff hunks (`EditBlock`s), and applies accepted blocks. No I/O, no UI.
public enum EditApplier {

    /// Default number of unchanged context lines shown above/below a hunk.
    public static let defaultContextRadius = 2

    // MARK: Plan

    /// Resolve `edits` against `body`, then coalesce contiguous resolved
    /// operations into edit blocks (one per spot). Unresolved operations are
    /// returned separately so the caller can report them back to the model.
    public static func plan(
        _ edits: [ProposedEdit],
        in body: String,
        contextRadius: Int = defaultContextRadius
    ) -> (blocks: [EditBlock], unresolved: [ResolvedOp]) {
        let ns = body as NSString
        let resolvedAll = edits.map { resolve($0, in: ns) }
        let unresolved = resolvedAll.filter { !$0.isResolved }
        let resolved = resolvedAll
            .filter { $0.isResolved }
            .sorted { lhs, rhs in
                lhs.range.location != rhs.range.location
                    ? lhs.range.location < rhs.range.location
                    : lhs.range.length < rhs.range.length
            }

        // Group into blocks: ops on the same line or directly adjacent lines
        // merge (a same-spot delete+add is one block); a gap of a blank line or
        // more starts a new block (so line 9 and line 12 are two blocks).
        var groups: [[ResolvedOp]] = []
        for op in resolved {
            let startLine = lineIndex(ofLocation: op.range.location, in: ns)
            if var last = groups.last,
               let prev = last.last,
               startLine <= lineIndex(ofLocation: NSMaxRange(prev.range), in: ns) + 1 {
                last.append(op)
                groups[groups.count - 1] = last
            } else {
                groups.append([op])
            }
        }

        let blocks = groups.map { makeBlock($0, in: ns, contextBefore: contextRadius, contextAfter: contextRadius) }
        return (blocks, unresolved)
    }

    // MARK: Apply

    /// Apply the (re-resolved) `blocks` to `body`, producing the new body.
    /// Applies operations right-to-left by range so earlier ranges stay valid.
    /// Throws on overlapping or out-of-bounds ranges (stale edits).
    public static func apply(_ blocks: [EditBlock], to body: String) throws -> String {
        let ops = blocks.flatMap { $0.ops }.filter { $0.isResolved }
        guard !ops.isEmpty else { throw EditApplyError.noResolvedOps }
        let ns = NSMutableString(string: body)
        let length = ns.length

        let sorted = ops.sorted { NSMaxRange($0.range) > NSMaxRange($1.range) }
        // Overlap check (ranges sorted by end, descending): each op must end at
        // or before the next one starts.
        for i in 0..<(sorted.count - 1) where !sorted.isEmpty {
            let higher = sorted[i].range       // later in the document
            let lower = sorted[i + 1].range    // earlier in the document
            if higher.location < NSMaxRange(lower) { throw EditApplyError.overlappingEdits }
        }
        for op in sorted {
            guard op.range.location >= 0, NSMaxRange(op.range) <= length else {
                throw EditApplyError.rangeOutOfBounds
            }
            ns.replaceCharacters(in: op.range, with: op.replacement)
        }
        return ns as String
    }

    // MARK: Re-render a single block's preview with a custom context radius (expand toggles)

    /// Rebuild one block's diff preview with more (or fewer) context lines —
    /// used when the user taps "expand up / expand down". `body` must be the
    /// body the block was resolved against.
    public static func preview(
        for block: EditBlock,
        in body: String,
        contextBefore: Int,
        contextAfter: Int
    ) -> DiffPreview {
        let ns = body as NSString
        return makeBlock(block.ops, in: ns, contextBefore: contextBefore, contextAfter: contextAfter).preview
    }

    // MARK: - Resolution

    static func resolve(_ edit: ProposedEdit, in body: NSString) -> ResolvedOp {
        switch edit {
        case .addition(let anchor, let content):
            return resolveAddition(anchor: anchor, content: content, in: body, source: edit)
        case .edit(let target, let replacement):
            guard !target.isEmpty else {
                return op(.edit, NSRange(location: 0, length: 0), replacement, .unresolved(.empty), edit)
            }
            return locate(target, in: body, kind: .edit, replacement: replacement, source: edit)
        case .deletion(let target):
            guard !target.isEmpty else {
                return op(.deletion, NSRange(location: 0, length: 0), "", .unresolved(.empty), edit)
            }
            let located = locate(target, in: body, kind: .deletion, replacement: "", source: edit)
            guard located.isResolved else { return located }
            // If deleting leaves an empty line, also consume one trailing newline
            // so the line disappears rather than leaving a blank gap.
            let range = expandedDeletionRange(located.range, in: body)
            return op(.deletion, range, "", .resolved, edit)
        }
    }

    private static func op(_ kind: EditKind, _ range: NSRange, _ replacement: String,
                           _ status: ResolutionStatus, _ source: ProposedEdit) -> ResolvedOp {
        ResolvedOp(kind: kind, range: range, replacement: replacement, status: status, source: source)
    }

    private static func resolveAddition(anchor: Anchor, content: String, in body: NSString,
                                        source: ProposedEdit) -> ResolvedOp {
        let zero = NSRange(location: 0, length: 0)
        guard !content.isEmpty else { return op(.addition, zero, content, .unresolved(.empty), source) }
        switch anchor {
        case .startOfDocument:
            return op(.addition, zero, content, .resolved, source)
        case .endOfDocument:
            return op(.addition, NSRange(location: body.length, length: 0), content, .resolved, source)
        case .after(let text):
            guard !text.isEmpty else { return op(.addition, zero, content, .unresolved(.empty), source) }
            let ranges = allRanges(of: text, in: body)
            guard let one = uniqueRange(ranges) else { return op(.addition, zero, content, status(for: ranges), source) }
            return op(.addition, NSRange(location: NSMaxRange(one), length: 0), content, .resolved, source)
        case .before(let text):
            guard !text.isEmpty else { return op(.addition, zero, content, .unresolved(.empty), source) }
            let ranges = allRanges(of: text, in: body)
            guard let one = uniqueRange(ranges) else { return op(.addition, zero, content, status(for: ranges), source) }
            return op(.addition, NSRange(location: one.location, length: 0), content, .resolved, source)
        }
    }

    private static func locate(_ target: String, in body: NSString, kind: EditKind,
                               replacement: String, source: ProposedEdit) -> ResolvedOp {
        let ranges = allRanges(of: target, in: body)
        guard let one = uniqueRange(ranges) else {
            return op(kind, NSRange(location: 0, length: 0), replacement, status(for: ranges), source)
        }
        return op(kind, one, replacement, .resolved, source)
    }

    private static func uniqueRange(_ ranges: [NSRange]) -> NSRange? {
        ranges.count == 1 ? ranges[0] : nil
    }

    private static func status(for ranges: [NSRange]) -> ResolutionStatus {
        ranges.isEmpty ? .unresolved(.notFound) : .unresolved(.ambiguous(count: ranges.count))
    }

    /// All non-overlapping occurrences of `needle` in `haystack`.
    static func allRanges(of needle: String, in haystack: NSString) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        var result: [NSRange] = []
        var searchStart = 0
        let needleNS = needle as NSString
        while searchStart <= haystack.length {
            let searchRange = NSRange(location: searchStart, length: haystack.length - searchStart)
            let found = haystack.range(of: needle, options: [], range: searchRange)
            if found.location == NSNotFound { break }
            result.append(found)
            searchStart = found.location + max(needleNS.length, 1)
        }
        return result
    }

    /// Extend a deletion range to swallow one trailing newline when the deleted
    /// text is the entire content of its line (so the line is removed cleanly).
    private static func expandedDeletionRange(_ range: NSRange, in body: NSString) -> NSRange {
        let atLineStart = range.location == 0
            || body.character(at: range.location - 1) == unichar(("\n" as Character).asciiValue!)
        let end = NSMaxRange(range)
        let followedByNewline = end < body.length
            && body.character(at: end) == unichar(("\n" as Character).asciiValue!)
        if atLineStart && followedByNewline {
            return NSRange(location: range.location, length: range.length + 1)
        }
        return range
    }

    // MARK: - Block construction

    static func makeBlock(_ ops: [ResolvedOp], in body: NSString, contextBefore: Int, contextAfter: Int) -> EditBlock {
        let spanStart = ops.map { $0.range.location }.min() ?? 0
        let spanEnd = ops.map { NSMaxRange($0.range) }.max() ?? spanStart
        let span = NSRange(location: spanStart, length: spanEnd - spanStart)

        // Full lines covering the change ("before" region).
        let changedLineRange = body.lineRange(for: span)
        let beforeRegion = body.substring(with: changedLineRange)

        // Apply this block's ops, translated into the region's coordinates,
        // right-to-left, to produce the "after" region.
        let afterRegion = applyOps(ops, toRegion: beforeRegion, regionLocation: changedLineRange.location)

        let beforeLines = splitLines(beforeRegion)
        let afterLines = splitLines(afterRegion)
        let changedRows = LineDiff.diff(before: beforeLines, after: afterLines)

        // Context above/below the changed region.
        let beforeText = body.substring(to: changedLineRange.location)
        let allBefore = beforeText.isEmpty ? [] : splitLines(beforeText)
        let shownBefore = Array(allBefore.suffix(contextBefore))
        let canExpandUp = allBefore.count > shownBefore.count

        let afterText = body.substring(from: NSMaxRange(changedLineRange))
        let allAfter = afterText.isEmpty ? [] : splitLines(afterText)
        let shownAfter = Array(allAfter.prefix(contextAfter))
        let canExpandDown = allAfter.count > shownAfter.count

        var lines: [DiffLine] = shownBefore.map { DiffLine(kind: .context, text: $0) }
        lines += changedRows
        lines += shownAfter.map { DiffLine(kind: .context, text: $0) }

        let preview = DiffPreview(lines: lines, canExpandUp: canExpandUp, canExpandDown: canExpandDown)
        let hint = nearestHeading(before: spanStart, in: body)
        return EditBlock(ops: ops, span: span, preview: preview, locationHint: hint)
    }

    /// Apply ops (whose ranges are in whole-body coordinates) to a substring
    /// region that starts at `regionLocation`. Right-to-left to keep offsets valid.
    private static func applyOps(_ ops: [ResolvedOp], toRegion region: String, regionLocation: Int) -> String {
        let ns = NSMutableString(string: region)
        let sorted = ops.sorted { NSMaxRange($0.range) > NSMaxRange($1.range) }
        for op in sorted {
            let local = NSRange(location: op.range.location - regionLocation, length: op.range.length)
            guard local.location >= 0, NSMaxRange(local) <= ns.length else { continue }
            ns.replaceCharacters(in: local, with: op.replacement)
        }
        return ns as String
    }

    /// Split region text into lines, dropping the single empty element a trailing
    /// newline would otherwise produce (line ranges always end on a newline).
    static func splitLines(_ text: String) -> [String] {
        var parts = text.components(separatedBy: "\n")
        if text.hasSuffix("\n"), parts.last == "" { parts.removeLast() }
        return parts
    }

    /// 0-based line index of a character location.
    static func lineIndex(ofLocation location: Int, in body: NSString) -> Int {
        guard location > 0 else { return 0 }
        let prefixLen = min(location, body.length)
        let prefix = body.substring(with: NSRange(location: 0, length: prefixLen))
        return prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// Nearest markdown heading (`#…`) at or before `location`, stripped of markers.
    static func nearestHeading(before location: Int, in body: NSString) -> String? {
        let prefixLen = min(max(location, 0), body.length)
        let prefix = body.substring(with: NSRange(location: 0, length: prefixLen))
        for line in prefix.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let text = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
}
