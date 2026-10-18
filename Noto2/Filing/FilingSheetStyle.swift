import SwiftUI

/// A custom header avoids the larger title style applied to List sections on iOS 26.
struct FilingSectionCaption: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(0.72)
            .foregroundStyle(NotoTheme.muted)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Filing uses the canvas's soft match fill while inheriting the row's font.
struct FilingMatchText: View {
    let text: String
    let query: String
    var base: Color = NotoTheme.ink

    var body: some View { Text(attributedText) }

    private var attributedText: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = base
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let range = text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive], range: cursor..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].backgroundColor = NotoTheme.accentSoft
                result[lower..<upper].foregroundColor = NotoTheme.ink
            }
            cursor = range.upperBound
        }
        return result
    }
}
