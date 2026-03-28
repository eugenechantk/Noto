//
//  MarkdownTextView.swift
//  Noto
//
//  Renders markdown text with styled headings, bold, italic, code, bullets, and numbered lists.
//  Uses AttributedString for native SwiftUI rendering.
//

import SwiftUI

struct MarkdownTextView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    private var primaryColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color(red: 0.15, green: 0.15, blue: 0.15)
    }

    private var secondaryColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.5)
            : Color(red: 0.4, green: 0.4, blue: 0.4)
    }

    private var codeBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    // MARK: - Block Model

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case numbered(index: String, text: String)
        case codeBlock(lines: [String])
        case paragraph(text: String)
        case separator
    }

    // MARK: - Parser

    private func parseBlocks(_ input: String) -> [MarkdownBlock] {
        let lines = input.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var inCodeBlock = false
        var codeLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block fences
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(lines: codeLines))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            // Separator
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.separator)
                continue
            }

            // Headings
            if let match = trimmed.prefixMatch(of: /^(#{1,6})\s+(.+)/) {
                let level = match.1.count
                let content = String(match.2)
                blocks.append(.heading(level: level, text: content))
                continue
            }

            // Bullet lists
            if let match = trimmed.prefixMatch(of: /^[-*+]\s+(.+)/) {
                blocks.append(.bullet(text: String(match.1)))
                continue
            }

            // Numbered lists
            if let match = trimmed.prefixMatch(of: /^(\d+)[.)]\s+(.+)/) {
                blocks.append(.numbered(index: String(match.1), text: String(match.2)))
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                continue
            }

            // Paragraph
            blocks.append(.paragraph(text: trimmed))
        }

        // Close unclosed code block
        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(lines: codeLines))
        }

        return blocks
    }

    // MARK: - Render

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)
                .padding(.top, level <= 2 ? 8 : 4)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\u{2022}")
                    .font(.system(size: 20))
                    .foregroundStyle(secondaryColor)
                Text(styledText(text))
                    .font(.system(size: 20))
                    .tracking(-0.45)
                    .foregroundStyle(primaryColor)
                    .lineSpacing(3)
            }
        case .numbered(let index, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(index).")
                    .font(.system(size: 20))
                    .foregroundStyle(secondaryColor)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(styledText(text))
                    .font(.system(size: 20))
                    .tracking(-0.45)
                    .foregroundStyle(primaryColor)
                    .lineSpacing(3)
            }
        case .codeBlock(let lines):
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(primaryColor)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .paragraph(let text):
            Text(styledText(text))
                .font(.system(size: 20))
                .tracking(-0.45)
                .foregroundStyle(primaryColor)
                .lineSpacing(3)
        case .separator:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func renderHeading(level: Int, text: String) -> some View {
        let size: CGFloat = switch level {
        case 1: 28
        case 2: 24
        case 3: 20
        default: 17
        }
        return Text(styledText(text))
            .font(.system(size: size, weight: .bold))
            .tracking(-0.45)
            .foregroundStyle(primaryColor)
    }

    // MARK: - Inline Styling

    /// Parse inline markdown: **bold**, *italic*, `code`, ~~strikethrough~~
    private func styledText(_ input: String) -> AttributedString {
        // Try Apple's built-in Markdown parser first
        if let md = try? AttributedString(markdown: input, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return md
        }
        // Fallback to plain text
        return AttributedString(input)
    }
}
