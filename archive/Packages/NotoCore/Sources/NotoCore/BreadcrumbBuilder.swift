//
//  BreadcrumbBuilder.swift
//  NotoCore
//
//  Walks a Block's parent chain and produces a breadcrumb display string.
//  Example: "Home / Projects / App Ideas"
//

import Foundation
import NotoModels

public struct BreadcrumbBuilder {

    private static let maxTitleLength = 30

    /// Build a breadcrumb string for a block by walking its ancestor chain.
    ///
    /// - The block itself is excluded from the breadcrumb.
    /// - The top-level root's content is replaced with "Home".
    /// - Titles longer than 30 characters are truncated with "...".
    /// - Only the first line of multiline content is used.
    /// - Ancestors are joined with " / " in root-first order.
    ///
    /// - Parameter block: The block to build a breadcrumb for.
    /// - Returns: A formatted breadcrumb string.
    public static func build(for block: Block) -> String {
        // Walk up parent chain (excluding the block itself)
        var ancestors: [Block] = []
        var current = block.parent
        while let ancestor = current {
            ancestors.append(ancestor)
            current = ancestor.parent
        }

        // If no ancestors, the block is at root level
        if ancestors.isEmpty {
            return "Home"
        }

        // Reverse to root-first order
        ancestors.reverse()

        // Build title strings
        var titles: [String] = []
        for (index, ancestor) in ancestors.enumerated() {
            if index == 0 {
                // Top-level root is always "Home"
                titles.append("Home")
            } else {
                titles.append(truncatedTitle(ancestor.content))
            }
        }

        return titles.joined(separator: " / ")
    }

    /// Extract first line and truncate to maxTitleLength characters.
    private static func truncatedTitle(_ content: String) -> String {
        // Take first line only
        let firstLine: String
        if let newlineIndex = content.firstIndex(of: "\n") {
            firstLine = String(content[content.startIndex..<newlineIndex])
        } else {
            firstLine = content
        }

        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)

        if trimmed.count > maxTitleLength {
            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxTitleLength)
            return String(trimmed[trimmed.startIndex..<endIndex]) + "..."
        }

        return trimmed
    }
}
