#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownTextStorage")

/// Custom NSTextStorage that applies rich formatting for markdown syntax.
/// Supports: # headings, **bold**, *italic*, - / * / 1. lists, [x] checkmarks, `code`.
///
/// Performance: formatting is applied to the full document on load, but only to the
/// edited paragraph (and its neighbors) on incremental edits. Cached state avoids
/// re-scanning the entire document on every keystroke.
final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    private var isFormatting = false

    /// The NSRange of the line the cursor is currently on. Updated by the editor.
    var activeLine: NSRange?

    // MARK: - Cached state (avoids O(n) scans per keystroke)

    /// Cached frontmatter end offset. Invalidated on edits near the frontmatter.
    private var cachedFrontmatterEnd: Int?

    /// Cached location of the first heading line. Invalidated on edits before it.
    private var cachedFirstHeadingLocation: Int?

    /// Updates the active line and re-applies heading prefix visibility
    /// only on the affected lines, not the entire document.
    func setActiveLine(_ range: NSRange?) {
        guard activeLine != range else { return }
        // Don't re-enter if we're already formatting (e.g., called from textViewDidChangeSelection
        // during processEditing)
        guard !isFormatting else {
            activeLine = range
            return
        }
        let oldLine = activeLine
        activeLine = range
        guard backing.length > 0 else { return }

        let nsText = backing.mutableString
        let contentStart = frontmatterEnd()

        // Only re-format heading lines that changed active state
        isFormatting = true
        beginEditing()

        if let old = oldLine, old.location < backing.length, NSMaxRange(old) <= backing.length {
            let line = nsText.substring(with: old)
            if line.hasPrefix("#") {
                formatLine(line, range: old, isTitle: old.location == firstHeadingLocation(contentStart: contentStart))
            }
        }
        if let new = range, new.location < backing.length, NSMaxRange(new) <= backing.length {
            let line = nsText.substring(with: new)
            if line.hasPrefix("#") {
                formatLine(line, range: new, isTitle: new.location == firstHeadingLocation(contentStart: contentStart))
            }
        }

        edited(.editedAttributes, range: NSRange(location: 0, length: backing.length), changeInLength: 0)
        endEditing()
        isFormatting = false
    }

    // MARK: - NSTextStorage required overrides

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        // Invalidate caches if edit is near frontmatter or before first heading
        invalidateCaches(for: range)

        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        if !isFormatting {
            isFormatting = true
            applyFormattingToRegion(around: editedRange)
            isFormatting = false
        }
        super.processEditing()
    }

    // MARK: - Platform-specific font sizes

    #if os(iOS)
    private static let bodySize: CGFloat = 17
    private static let heading1Size: CGFloat = 28
    private static let heading2Size: CGFloat = 22
    private static let heading3Size: CGFloat = 18
    #elseif os(macOS)
    private static let bodySize: CGFloat = 14
    private static let heading1Size: CGFloat = 24
    private static let heading2Size: CGFloat = 18
    private static let heading3Size: CGFloat = 15
    #endif

    // MARK: - Body style (all static, allocated once)

    static let bodyFont = PlatformFont.systemFont(ofSize: bodySize, weight: .regular)
    static let bodyColor = PlatformColor.label

    private static let cachedBodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 6
        return style
    }()

    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: bodyColor,
        .paragraphStyle: cachedBodyParagraphStyle
    ]

    // MARK: - Pre-compiled regexes

    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    // MARK: - Cached measurements (avoid re-measuring on every bullet line)

    private static let bulletTextWidth: CGFloat = {
        ("- " as NSString).size(withAttributes: [.font: bodyFont]).width
    }()

    // MARK: - Cache management

    private func invalidateCaches(for editRange: NSRange) {
        // Invalidate frontmatter cache if edit is in the first ~200 chars (where frontmatter lives)
        if let fmEnd = cachedFrontmatterEnd {
            if editRange.location <= fmEnd + 10 {
                cachedFrontmatterEnd = nil
            }
        } else {
            cachedFrontmatterEnd = nil
        }

        // Invalidate first heading cache if edit is before or at the cached location
        if let headingLoc = cachedFirstHeadingLocation {
            if editRange.location <= headingLoc {
                cachedFirstHeadingLocation = nil
            }
        } else {
            cachedFirstHeadingLocation = nil
        }
    }

    /// Returns the cached frontmatter end offset, computing it if needed.
    private func frontmatterEnd() -> Int {
        if let cached = cachedFrontmatterEnd { return cached }
        let nsText = backing.mutableString
        guard nsText.length >= 3 else {
            cachedFrontmatterEnd = 0
            return 0
        }
        guard nsText.substring(with: NSRange(location: 0, length: 3)) == "---" else {
            cachedFrontmatterEnd = 0
            return 0
        }
        let searchRange = NSRange(location: 3, length: nsText.length - 3)
        let closeRange = nsText.range(of: "\n---", range: searchRange)
        guard closeRange.location != NSNotFound else {
            cachedFrontmatterEnd = 0
            return 0
        }
        let end = NSMaxRange(closeRange)
        cachedFrontmatterEnd = end
        return end
    }

    /// Returns the cached first heading location, computing it if needed.
    private func firstHeadingLocation(contentStart: Int) -> Int {
        if let cached = cachedFirstHeadingLocation { return cached }
        let nsText = backing.mutableString
        let length = nsText.length
        guard contentStart < length else {
            cachedFirstHeadingLocation = -1
            return -1
        }
        // Scan lines from contentStart to find first heading
        var pos = contentStart
        while pos < length {
            let lineRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
            if nsText.substring(with: NSRange(location: lineRange.location, length: min(2, lineRange.length))).hasPrefix("#") {
                cachedFirstHeadingLocation = lineRange.location
                return lineRange.location
            }
            pos = NSMaxRange(lineRange)
            if pos == lineRange.location { break } // safety: avoid infinite loop
        }
        cachedFirstHeadingLocation = -1
        return -1
    }

    // MARK: - Incremental formatting

    private func applyFormattingToRegion(around editedRange: NSRange) {
        let fullLength = backing.length
        guard fullLength > 0 else { return }

        // Clamp editedRange to valid bounds
        let safeLocation = min(editedRange.location, fullLength)
        let safeLength = min(editedRange.length, fullLength - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)

        let nsText = backing.mutableString

        // Expand to cover complete paragraphs around the edit
        let paragraphRange = nsText.paragraphRange(for: safeRange)

        // Also include one paragraph before and after for context
        let expandedStart = paragraphRange.location > 0
            ? nsText.paragraphRange(for: NSRange(location: paragraphRange.location - 1, length: 0)).location
            : paragraphRange.location
        let expandedEnd = NSMaxRange(paragraphRange) < fullLength
            ? NSMaxRange(nsText.paragraphRange(for: NSRange(location: NSMaxRange(paragraphRange), length: 0)))
            : NSMaxRange(paragraphRange)
        let region = NSRange(location: expandedStart, length: expandedEnd - expandedStart)

        // Reset this region to body style
        backing.setAttributes(Self.bodyAttributes, range: region)

        // Handle frontmatter if region overlaps it
        let contentStart = frontmatterEnd()
        if contentStart > 0 && region.location < contentStart {
            applyFrontmatterHiding(range: NSRange(location: 0, length: min(contentStart, fullLength)))
        }

        // Format lines within the region
        let lineStart = max(region.location, contentStart)
        guard lineStart < NSMaxRange(region) else { return }
        let lineRegion = NSRange(location: lineStart, length: NSMaxRange(region) - lineStart)

        let firstHeadLoc = firstHeadingLocation(contentStart: contentStart)

        // Collect lines first, then process — modifying backing during enumeration crashes
        var lines: [(String, NSRange)] = []
        nsText.enumerateSubstrings(in: lineRegion, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            lines.append((nsText.substring(with: substringRange), substringRange))
        }
        for (line, range) in lines {
            let isTitle = range.location == firstHeadLoc
            formatLine(line, range: range, isTitle: isTitle)
        }

        // Inline formatting within the region
        if lineRegion.length > 0 {
            applyInlineFormatting(in: lineRegion, nsText: nsText)
        }
    }

    // MARK: - Full formatting (used on load)

    private func applyMarkdownFormatting() {
        let fullRange = NSRange(location: 0, length: backing.length)
        guard fullRange.length > 0 else { return }

        backing.setAttributes(Self.bodyAttributes, range: fullRange)

        let nsText = backing.mutableString

        // Invalidate caches for full reformat
        cachedFrontmatterEnd = nil
        cachedFirstHeadingLocation = nil

        let contentStart = frontmatterEnd()
        if contentStart > 0 {
            applyFrontmatterHiding(range: NSRange(location: 0, length: contentStart))
        }

        guard contentStart < nsText.length else { return }
        let bodyRange = NSRange(location: contentStart, length: nsText.length - contentStart)

        // Collect lines first, then process — modifying backing during enumeration crashes
        var lines: [(String, NSRange)] = []
        nsText.enumerateSubstrings(in: bodyRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            lines.append((nsText.substring(with: substringRange), substringRange))
        }
        var foundFirstHeading = false
        let currentLength = backing.length
        for (line, range) in lines {
            // Safety: skip lines whose ranges are now out of bounds
            guard range.location >= 0, NSMaxRange(range) <= currentLength else { continue }
            let isTitle = !foundFirstHeading && line.hasPrefix("# ")
            formatLine(line, range: range, isTitle: isTitle)
            if line.hasPrefix("#") { foundFirstHeading = true }
        }

        applyInlineFormatting(in: bodyRange, nsText: nsText)
    }

    // MARK: - Frontmatter

    private func applyFrontmatterHiding(range: NSRange) {
        let fmStyle = NSMutableParagraphStyle()
        fmStyle.lineSpacing = 0
        fmStyle.paragraphSpacing = 0
        fmStyle.minimumLineHeight = 0.1
        fmStyle.maximumLineHeight = 0.1
        backing.addAttributes([
            .font: PlatformFont.systemFont(ofSize: 0.1),
            .foregroundColor: PlatformColor.clear,
            .paragraphStyle: fmStyle
        ], range: range)
    }

    // MARK: - Line formatting

    private func formatLine(_ line: String, range: NSRange, isTitle: Bool = false) {
        if line.hasPrefix("# ") {
            applyHeading(level: 1, range: range, isTitle: isTitle)
        } else if line.hasPrefix("## ") {
            applyHeading(level: 2, range: range)
        } else if line.hasPrefix("### ") {
            applyHeading(level: 3, range: range)
        }
        // Todo items: - [ ] or - [x]
        else if let match = line.range(of: #"^(\s*)[*\-•] \[([ x])\] "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            let isChecked = line.contains("[x]")
            applyTodo(range: range, prefixLength: prefixLength, level: level, isChecked: isChecked)
        } else if let match = line.range(of: #"^(\s*)[*\-•] "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            applyBulletList(range: range, prefixLength: prefixLength, level: level)
        } else if let match = line.range(of: #"^(\s*)\d+\. "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            applyOrderedList(range: range, prefixLength: prefixLength, level: level)
        }
    }

    // MARK: - Heading styles (cached per level)

    private static let headingFonts: [Int: PlatformFont] = [
        1: PlatformFont.systemFont(ofSize: heading1Size, weight: .bold),
        2: PlatformFont.systemFont(ofSize: heading2Size, weight: .bold),
        3: PlatformFont.systemFont(ofSize: heading3Size, weight: .semibold)
    ]

    private func applyHeading(level: Int, range: NSRange, isTitle: Bool = false) {
        let font = Self.headingFonts[level] ?? Self.bodyFont

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        if !isTitle {
            let spacingBefore: [Int: CGFloat] = [1: 24, 2: 20, 3: 16]
            style.paragraphSpacingBefore = spacingBefore[level] ?? 16
        }
        let spacingAfter: [Int: CGFloat] = [1: 12, 2: 8, 3: 6]
        style.paragraphSpacing = spacingAfter[level] ?? 6

        backing.addAttributes([
            .font: font,
            .paragraphStyle: style
        ], range: range)

        // Show/hide the markdown prefix based on cursor position
        let prefixLen = level + 1
        if range.length > prefixLen {
            let prefixRange = NSRange(location: range.location, length: prefixLen)
            let isActive = activeLine.map { $0.location == range.location } ?? false
            if isActive {
                backing.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: prefixRange)
            } else {
                backing.addAttributes([
                    .font: PlatformFont.systemFont(ofSize: 0.1),
                    .foregroundColor: PlatformColor.clear
                ], range: prefixRange)
            }
        }
    }

    private static let indentPerLevel: CGFloat = 12

    // MARK: - Todo checkboxes

    private static let todoGoldColor = UIColor(red: 0.92, green: 0.75, blue: 0.20, alpha: 1.0)

    private func applyTodo(range: NSRange, prefixLength: Int, level: Int, isChecked: Bool) {
        let levelIndent = Self.indentPerLevel * CGFloat(level)
        guard prefixLength <= range.length else { return }
        guard NSMaxRange(range) <= backing.length else { return }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + Self.bulletTextWidth
        backing.addAttribute(.paragraphStyle, value: style, range: range)

        // Color the entire prefix "- [ ] " or "- [x] " as the indicator
        let prefixRange = NSRange(location: range.location, length: min(prefixLength, range.length))
        let prefixColor = isChecked ? Self.todoGoldColor : UIColor.systemGray3
        backing.addAttribute(.foregroundColor, value: prefixColor, range: prefixRange)

        // If checked, dim the text content
        if isChecked {
            let contentStart = range.location + prefixLength
            let contentLength = range.length - prefixLength
            if contentLength > 0 && contentStart + contentLength <= backing.length {
                backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSRange(location: contentStart, length: contentLength))
            }
        }
    }

    private func applyBulletList(range: NSRange, prefixLength: Int, level: Int) {
        let levelIndent = Self.indentPerLevel * CGFloat(level)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + Self.bulletTextWidth
        backing.addAttribute(.paragraphStyle, value: style, range: range)

        // Hide leading whitespace (for nested bullets)
        let nsText = backing.mutableString
        let prefixStr = nsText.substring(with: NSRange(location: range.location, length: prefixLength))
        let leadingSpaceCount = prefixStr.prefix(while: { $0 == " " || $0 == "\t" }).count
        if leadingSpaceCount > 0 {
            backing.addAttribute(.foregroundColor, value: PlatformColor.clear, range: NSRange(location: range.location, length: leadingSpaceCount))
        }

        // Dim the bullet marker character (- or *) instead of replacing it.
        // Text mutations during processEditing crash the layout manager.
        let markerRange = NSRange(location: range.location + leadingSpaceCount, length: 1)
        backing.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: markerRange)
    }

    private func applyOrderedList(range: NSRange, prefixLength: Int, level: Int) {
        let levelIndent = Self.indentPerLevel * CGFloat(level)

        let nsText = backing.mutableString
        let prefixStr = nsText.substring(with: NSRange(location: range.location, length: prefixLength))
        let visiblePrefix = String(prefixStr.drop(while: { $0 == " " || $0 == "\t" }))
        let prefixWidth = (visiblePrefix as NSString).size(withAttributes: [.font: Self.bodyFont]).width

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + prefixWidth
        backing.addAttribute(.paragraphStyle, value: style, range: range)
    }

    // MARK: - Inline formatting

    private func applyInlineFormatting(in range: NSRange, nsText: NSMutableString) {
        let str = nsText as String

        Self.boldRegex.enumerateMatches(in: str, range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            let currentFont = self.backing.attribute(.font, at: matchRange.location, effectiveRange: nil) as? PlatformFont ?? Self.bodyFont
            let boldFont = PlatformFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
            self.backing.addAttribute(.font, value: boldFont, range: matchRange)
            self.dimDelimiters(matchRange: matchRange, delimiterLength: 2)
        }

        Self.italicRegex.enumerateMatches(in: str, range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            let currentFont = self.backing.attribute(.font, at: matchRange.location, effectiveRange: nil) as? PlatformFont ?? Self.bodyFont
            #if os(iOS)
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? currentFont.fontDescriptor
            let italicFont = PlatformFont(descriptor: descriptor, size: currentFont.pointSize)
            #elseif os(macOS)
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.italic)
            let italicFont = PlatformFont(descriptor: descriptor, size: currentFont.pointSize) ?? currentFont
            #endif
            self.backing.addAttribute(.font, value: italicFont, range: matchRange)
            self.dimDelimiters(matchRange: matchRange, delimiterLength: 1)
        }

        Self.codeRegex.enumerateMatches(in: str, range: range) { match, _, _ in
            guard let match else { return }
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: Self.bodySize - 1, weight: .regular)
            self.backing.addAttributes([
                .font: monoFont,
                .foregroundColor: PlatformColor.secondaryLabel,
                .backgroundColor: PlatformColor.secondarySystemFill
            ], range: match.range)
        }
    }

    private func dimDelimiters(matchRange: NSRange, delimiterLength: Int) {
        let startDelim = NSRange(location: matchRange.location, length: delimiterLength)
        let endDelim = NSRange(location: matchRange.location + matchRange.length - delimiterLength, length: delimiterLength)
        backing.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: startDelim)
        backing.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: endDelim)
    }

    // MARK: - Load / Export

    func load(markdown: String) {
        cachedFrontmatterEnd = nil
        cachedFirstHeadingLocation = nil

        // Replace content. processEditing will apply incremental formatting
        // to the edited region. Then we do a full format pass afterward.
        let fullRange = NSRange(location: 0, length: backing.length)
        replaceCharacters(in: fullRange, with: markdown)

        // Full format pass for the complete document (incremental only
        // covered the edited region around the replacement point).
        guard backing.length > 0 else { return }
        isFormatting = true
        beginEditing()
        applyMarkdownFormatting()
        edited(.editedAttributes, range: NSRange(location: 0, length: backing.length), changeInLength: 0)
        endEditing()
        isFormatting = false
    }

    func markdownContent() -> String {
        backing.string
    }
}
