import SwiftUI

/// A section heading for custom (non-`List`) Noto 2 screens: caption size,
/// uppercase, secondary colour — never a badge (Eugene, 2026-10-17). Inside a
/// `List`, use the system section header instead; it already looks like this.
struct Noto2SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
