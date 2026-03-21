//
//  OutlineTextStorage.swift
//  Noto
//
//  Custom NSTextStorage for the outline editor. Handles:
//  - Tab-based depth ↔ visual bullets + paragraph indentation
//  - Inline bold (**text**) and italic (*text*) styling
//  - Load (tab-indented string → formatted display)
//  - Deformat (formatted display → tab-indented string for Block sync)
//
//  Follows the Simple-Notes architecture: TextStorage does all the heavy lifting.
//  The editing cycle is:
//    1. processEditing() captures editedRange (no formatting here — avoids reentrancy)
//    2. textViewDidChange → processRichFormatting() applies formatting safely
//

import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "OutlineTextStorage")

// MARK: - Custom Attribute Keys

extension NSAttributedString.Key {
    /// Int depth of the block (0 = root, 1 = child, 2 = grandchild, etc.)
    static let outlineDepth = NSAttributedString.Key("outlineDepth")
    /// Bool marker on characters that are part of the bullet prefix (stripped on deformat).
    static let bulletMarker = NSAttributedString.Key("bulletMarker")
}

// MARK: - Formatting Result

struct OutlineFormattedResult {
    /// Range where the caret should be repositioned after formatting.
    var caretRange: NSRange?
}

// MARK: - OutlineTextStorage

final class OutlineTextStorage: NSTextStorage {

    private let backingStore = NSMutableAttributedString()

    // MARK: - Font Configuration

    let bodyFont = UIFont.systemFont(ofSize: 17)
    let boldFont = UIFont.boldSystemFont(ofSize: 17)
    let italicFont = UIFont.italicSystemFont(ofSize: 17)

    private let bulletColor = UIColor.secondaryLabel
    private let indentStep: CGFloat = 24

    // MARK: - Bullet Strings Per Depth

    func bulletString(for depth: Int) -> String {
        switch depth {
        case 0: return ""
        case 1: return "•  "
        case 2: return "◦  "
        default: return "–  "
        }
    }

    // MARK: - Paragraph Styles Per Depth

    func paragraphStyle(for depth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if depth == 0 {
            style.firstLineHeadIndent = 0
            style.headIndent = 0
        } else {
            let bulletIndent = CGFloat(depth - 1) * indentStep
            let textIndent = bulletIndent + indentStep
            style.firstLineHeadIndent = bulletIndent
            style.headIndent = textIndent
        }
        style.paragraphSpacing = 6
        return style
    }

    // MARK: - Body Style

    var bodyStyle: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle(for: 0)
        ]
    }

    private func style(for depth: Int) -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle(for: depth),
            .outlineDepth: depth
        ]
    }

    private func bulletStyle(for depth: Int) -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: bulletColor,
            .paragraphStyle: paragraphStyle(for: depth),
            .outlineDepth: depth,
            .bulletMarker: true
        ]
    }

    // MARK: - NSTextStorage Subclass Requirements

    override var string: String { backingStore.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Edit Tracking

    private var lastEditedRange: NSRange?
    private var lastEditedMask: EditActions?

    override func processEditing() {
        lastEditedRange = editedRange
        lastEditedMask = editedMask
        super.processEditing()
    }

    // MARK: - Rich Formatting (called from textViewDidChange)

    @discardableResult
    func processRichFormatting() -> OutlineFormattedResult? {
        guard let range = lastEditedRange, backingStore.length > 0 else { return nil }
        return performFormatting(editedAt: range)
    }

    private func performFormatting(editedAt range: NSRange) -> OutlineFormattedResult? {
        let safeLocation = min(range.location, backingStore.length - 1)
        guard safeLocation >= 0 else { return nil }

        let lineRange = outlineLineRange(for: safeLocation)
        guard lineRange.length > 0 else { return nil }

        // Scan depth from existing attributes on this line
        let depth = depthForLine(at: lineRange)

        // Re-apply paragraph style and depth attribute to the whole line
        beginEditing()
        backingStore.addAttribute(.paragraphStyle, value: paragraphStyle(for: depth), range: lineRange)
        backingStore.addAttribute(.outlineDepth, value: depth, range: lineRange)
        edited(.editedAttributes, range: lineRange, changeInLength: 0)
        endEditing()

        // Ensure bullet is correct for the depth
        ensureBullet(for: lineRange, depth: depth)

        return nil
    }

    // MARK: - Depth Reading

    /// Read the depth for a line. Scans for any .outlineDepth attribute on the line.
    func depthForLine(at lineRange: NSRange) -> Int {
        var depth = 0
        let scanRange = NSRange(location: lineRange.location, length: min(lineRange.length, backingStore.length - lineRange.location))
        guard scanRange.length > 0 else { return 0 }

        backingStore.enumerateAttribute(.outlineDepth, in: scanRange) { val, _, stop in
            if let d = val as? Int, d > 0 {
                depth = d
                stop.pointee = true
            }
        }
        return depth
    }

    // MARK: - Bullet Management

    /// Ensure the correct bullet prefix is at the start of the line.
    private func ensureBullet(for lineRange: NSRange, depth: Int) {
        let expectedBullet = bulletString(for: depth)
        let currentBulletRange = existingBulletRange(at: lineRange)

        if depth == 0 {
            // Remove bullet if present
            if let range = currentBulletRange, range.length > 0 {
                beginEditing()
                backingStore.deleteCharacters(in: range)
                edited(.editedCharacters, range: range, changeInLength: -range.length)
                endEditing()
            }
            return
        }

        if let range = currentBulletRange {
            let currentBullet = backingStore.attributedSubstring(from: range).string
            if currentBullet == expectedBullet { return }
            // Replace existing bullet with correct one
            let replacement = NSAttributedString(string: expectedBullet, attributes: bulletStyle(for: depth))
            beginEditing()
            backingStore.replaceCharacters(in: range, with: replacement)
            edited(.editedCharacters, range: range, changeInLength: expectedBullet.count - range.length)
            endEditing()
        } else {
            // Insert new bullet
            let bullet = NSAttributedString(string: expectedBullet, attributes: bulletStyle(for: depth))
            beginEditing()
            backingStore.insert(bullet, at: lineRange.location)
            edited(.editedCharacters, range: NSRange(location: lineRange.location, length: 0), changeInLength: expectedBullet.count)
            endEditing()
        }
    }

    /// Find the range of existing bullet marker characters at the start of a line.
    private func existingBulletRange(at lineRange: NSRange) -> NSRange? {
        guard lineRange.length > 0 else { return nil }
        var bulletEnd = lineRange.location

        let scanEnd = min(lineRange.location + lineRange.length, backingStore.length)
        for i in lineRange.location..<scanEnd {
            if let marker = backingStore.attribute(.bulletMarker, at: i, effectiveRange: nil) as? Bool, marker {
                bulletEnd = i + 1
            } else {
                break
            }
        }

        let length = bulletEnd - lineRange.location
        return length > 0 ? NSRange(location: lineRange.location, length: length) : nil
    }

    // MARK: - Load (tab-indented text → formatted display)

    func load(text: String) {
        let lines = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()

        for (i, line) in lines.enumerated() {
            // Count and strip leading tabs
            var depth = 0
            for ch in line {
                guard ch == "\t" else { break }
                depth += 1
            }
            let content = String(line.dropFirst(depth))
            let bullet = bulletString(for: depth)

            // Build attributed line: bullet + content
            if !bullet.isEmpty {
                let bulletAttr = NSAttributedString(string: bullet, attributes: bulletStyle(for: depth))
                result.append(bulletAttr)
            }

            let contentAttr = NSAttributedString(string: content, attributes: style(for: depth))
            result.append(contentAttr)

            // Add newline between lines (not after the last)
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: style(for: depth)))
            }
        }

        setAttributedString(result)
    }

    // MARK: - Deformat (formatted display → tab-indented text for Block sync)

    func deformatted() -> String {
        var lines: [String] = []
        let nsString = backingStore.string as NSString
        var lineStart = 0

        while lineStart <= nsString.length {
            let lineRange: NSRange
            if lineStart < nsString.length {
                lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            } else {
                break
            }

            // Read depth
            let depth = depthForLine(at: lineRange)

            // Get line text, stripping bullet markers and trailing newline
            var lineText = ""
            for i in lineRange.location..<(lineRange.location + lineRange.length) {
                if i >= nsString.length { break }
                let ch = nsString.character(at: i)
                // Skip bullet marker characters
                if let marker = backingStore.attribute(.bulletMarker, at: i, effectiveRange: nil) as? Bool, marker {
                    continue
                }
                // Skip trailing newline
                if ch == 0x0A { continue }
                lineText.append(Character(UnicodeScalar(ch)!))
            }

            // Prepend tabs for depth
            let tabs = String(repeating: "\t", count: depth)
            lines.append(tabs + lineText)

            // Advance to next line
            let nextStart = lineRange.location + lineRange.length
            if nextStart <= lineStart { break }
            lineStart = nextStart
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Indent / Outdent

    func indentLine(at index: Int) {
        let lineRange = outlineLineRange(for: index)
        guard lineRange.length > 0 else { return }

        let currentDepth = depthForLine(at: lineRange)
        let newDepth = currentDepth + 1

        applyDepth(newDepth, to: lineRange)
    }

    func outdentLine(at index: Int) {
        let lineRange = outlineLineRange(for: index)
        guard lineRange.length > 0 else { return }

        let currentDepth = depthForLine(at: lineRange)
        guard currentDepth > 0 else { return }
        let newDepth = currentDepth - 1

        applyDepth(newDepth, to: lineRange)
    }

    /// Apply a new depth to a line: update attribute, paragraph style, and bullet.
    private func applyDepth(_ depth: Int, to lineRange: NSRange) {
        beginEditing()
        backingStore.addAttribute(.outlineDepth, value: depth, range: lineRange)
        backingStore.addAttribute(.paragraphStyle, value: paragraphStyle(for: depth), range: lineRange)
        edited(.editedAttributes, range: lineRange, changeInLength: 0)
        endEditing()

        // Re-read lineRange since bullet changes may shift it
        let updatedLineRange = self.outlineLineRange(for: lineRange.location)
        ensureBullet(for: updatedLineRange, depth: depth)
    }

    // MARK: - Line Range Helper

    func outlineLineRange(for index: Int) -> NSRange {
        let clamped = max(0, min(index, backingStore.length))
        guard backingStore.length > 0 else { return NSRange(location: 0, length: 0) }
        let safeClamped = min(clamped, backingStore.length - 1)
        return (backingStore.string as NSString).lineRange(for: NSRange(location: safeClamped, length: 0))
    }
}
