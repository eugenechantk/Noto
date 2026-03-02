//
//  BlockBuilder.swift
//  NotoCore
//
//  Generic reusable service for programmatically creating block hierarchies.
//  Used by TodayNotesService and available for future features (AI editing, templates, etc.).
//

import Foundation
import SwiftData
import os.log
import NotoModels

private let logger = Logger(subsystem: "com.noto", category: "BlockBuilder")

// MARK: - MatchStrategy

/// Strategy for finding existing blocks when building a path.
public enum MatchStrategy {
    /// Exact string match on block content.
    case exactContent
    /// Parse content as a date/period, match semantically, and rename to canonical format if matched.
    case dateAware(DateMatchType)
    /// Match by metadata field (future use).
    case metadata(key: String, value: String)
}

/// The type of date component to match when using `.dateAware`.
public enum DateMatchType {
    case year       // Parse as year (e.g., "2026")
    case month      // Parse as month name (e.g., "March", "Mar")
    case week       // Parse as week number (e.g., "Week 1", "W1")
    case day        // Parse as calendar date (e.g., "Mar 1, 2026", "March 1")
}

// MARK: - BuildStep

/// A single step in a block hierarchy path to be built.
public struct BuildStep {
    public let content: String
    public let sortOrder: Double
    public let isDeletable: Bool
    public let isContentEditableByUser: Bool
    public let isReorderable: Bool
    public let isMovable: Bool
    public let matchStrategy: MatchStrategy
    public let extensionData: Data?

    public init(
        content: String,
        sortOrder: Double,
        isDeletable: Bool = false,
        isContentEditableByUser: Bool = false,
        isReorderable: Bool = false,
        isMovable: Bool = false,
        matchStrategy: MatchStrategy = .exactContent,
        extensionData: Data? = nil
    ) {
        self.content = content
        self.sortOrder = sortOrder
        self.isDeletable = isDeletable
        self.isContentEditableByUser = isContentEditableByUser
        self.isReorderable = isReorderable
        self.isMovable = isMovable
        self.matchStrategy = matchStrategy
        self.extensionData = extensionData
    }
}

// MARK: - BlockBuilder

/// Generic service for programmatically creating block hierarchies.
/// Creates missing blocks along a path, reuses existing ones, and returns the deepest block.
public struct BlockBuilder {

    /// Build a path of blocks starting from a root, creating any missing blocks along the way.
    /// Returns the deepest block in the path.
    @MainActor
    public static func buildPath(
        root: Block,
        path: [BuildStep],
        context: ModelContext
    ) -> Block {
        var currentParent = root

        for step in path {
            if let existing = findExistingChild(of: currentParent, for: step) {
                // Rename to canonical format if matched via fuzzy strategy
                if existing.content != step.content {
                    logger.debug("[buildPath] renaming '\(existing.content)' → '\(step.content)'")
                    existing.content = step.content
                    existing.updatedAt = Date()
                }
                currentParent = existing
            } else {
                let newBlock = Block(
                    content: step.content,
                    parent: currentParent,
                    sortOrder: step.sortOrder,
                    extensionData: step.extensionData,
                    isDeletable: step.isDeletable,
                    isContentEditableByUser: step.isContentEditableByUser,
                    isReorderable: step.isReorderable,
                    isMovable: step.isMovable
                )
                context.insert(newBlock)
                logger.debug("[buildPath] created '\(step.content)' under '\(currentParent.content)' (sortOrder: \(step.sortOrder))")
                currentParent = newBlock
            }
        }

        return currentParent
    }

    // MARK: - Private

    /// Find an existing non-archived child of `parent` that matches the given step.
    @MainActor
    private static func findExistingChild(of parent: Block, for step: BuildStep) -> Block? {
        let activeChildren = parent.children.filter { !$0.isArchived }

        switch step.matchStrategy {
        case .exactContent:
            return activeChildren.first { $0.content == step.content }

        case .dateAware(let dateType):
            return findDateAwareMatch(in: activeChildren, for: step.content, dateType: dateType)

        case .metadata:
            // Future: match by metadata field
            return nil
        }
    }

    /// Find a child block that represents the same date/period as the canonical content.
    @MainActor
    private static func findDateAwareMatch(
        in children: [Block],
        for canonicalContent: String,
        dateType: DateMatchType
    ) -> Block? {
        // First try exact match (fastest path)
        if let exact = children.first(where: { $0.content == canonicalContent }) {
            return exact
        }

        // Then try fuzzy date parsing
        for child in children {
            if dateContentsMatch(child.content, canonicalContent, type: dateType) {
                return child
            }
        }

        return nil
    }

    /// Check if two content strings represent the same date/period.
    private static func dateContentsMatch(_ existing: String, _ canonical: String, type: DateMatchType) -> Bool {
        switch type {
        case .year:
            // Year strings are unambiguous — exact match only
            return existing.trimmingCharacters(in: .whitespaces) == canonical

        case .month:
            return parseMonthIndex(from: existing) == parseMonthIndex(from: canonical)

        case .week:
            return parseWeekNumber(from: existing) == parseWeekNumber(from: canonical)

        case .day:
            return parseDayDate(from: existing) == parseDayDate(from: canonical)
        }
    }

    // MARK: - Date Parsing Helpers

    /// Parse a string to a month index (1-12). Returns nil if unparseable.
    private static func parseMonthIndex(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()

        // Try full month name
        let fullMonths = ["january", "february", "march", "april", "may", "june",
                          "july", "august", "september", "october", "november", "december"]
        if let idx = fullMonths.firstIndex(of: trimmed) { return idx + 1 }

        // Try abbreviated month name
        let shortMonths = ["jan", "feb", "mar", "apr", "may", "jun",
                           "jul", "aug", "sep", "oct", "nov", "dec"]
        if let idx = shortMonths.firstIndex(of: trimmed) { return idx + 1 }

        // Try "Month YYYY" or "Mon YYYY" format (strip trailing year)
        let parts = trimmed.split(separator: " ")
        if parts.count == 2, let monthPart = parts.first {
            let monthStr = String(monthPart)
            if let idx = fullMonths.firstIndex(of: monthStr) { return idx + 1 }
            if let idx = shortMonths.firstIndex(of: monthStr) { return idx + 1 }
        }

        // Try numeric month (e.g., "03")
        if let num = Int(trimmed), num >= 1, num <= 12 { return num }

        return nil
    }

    /// Parse a string to a week number. Returns nil if unparseable.
    private static func parseWeekNumber(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()

        // "Week N (...)" or "Week N"
        if trimmed.hasPrefix("week ") {
            let afterWeek = trimmed.dropFirst(5)
            let numStr = afterWeek.prefix(while: { $0.isNumber })
            return Int(numStr)
        }

        // "WN" or "w1"
        if trimmed.hasPrefix("w") {
            let numStr = trimmed.dropFirst().prefix(while: { $0.isNumber })
            return Int(numStr)
        }

        return nil
    }

    /// Parse a string to a calendar date (day precision). Returns nil if unparseable.
    private static func parseDayDate(from text: String) -> DateComponents? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Try common date formats
        let formatters: [DateFormatter] = {
            let formats = [
                "MMM d, yyyy",   // "Mar 1, 2026"
                "MMMM d, yyyy",  // "March 1, 2026"
                "MMMM d",        // "March 1"
                "MMM d",         // "Mar 1"
                "d MMMM yyyy",   // "1 March 2026"
                "d MMMM",        // "1 March"
                "d MMM yyyy",    // "1 Mar 2026"
                "d MMM",         // "1 Mar"
                "d/M/yyyy",      // "1/3/2026"
                "d/M",           // "1/3"
                "MMMM d yyyy",   // "March 1 2026" (no comma)
                "MMM d yyyy",    // "Mar 1 2026" (no comma)
            ]
            return formats.map { fmt in
                let df = DateFormatter()
                df.dateFormat = fmt
                df.locale = Locale(identifier: "en_US_POSIX")
                return df
            }
        }()

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                let cal = Calendar(identifier: .gregorian)
                // Only compare month and day — year may be absent or default
                return cal.dateComponents([.month, .day], from: date)
            }
        }

        return nil
    }
}
