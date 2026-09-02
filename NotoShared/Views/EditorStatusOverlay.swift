import SwiftUI
import NotoVault

struct EditorStatusOverlay: View {
    let count: WordCounter.Count

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        HStack(spacing: 16) {
            Text("\(formatted(count.words)) words")
            Text("\(formatted(count.characters)) characters")
        }
        .font(.caption)
        .foregroundStyle(AppTheme.mutedText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(formatted(count.words)) words, \(formatted(count.characters)) characters")
        .accessibilityIdentifier("editor_status_overlay")
        .allowsHitTesting(false)
    }

    private func formatted(_ value: Int) -> String {
        Self.formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
