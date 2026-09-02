import SwiftUI

/// HIG sheet-header button — a circular control sized for a sheet nav row.
/// Mirrors `SheetCircleBtn` in the v2 design (`noto-minimal-editor.jsx`):
///   • `.close`   → translucent Liquid Glass circle with a neutral ✕
///   • `.confirm` → filled accent circle with a white ✓
/// Paired ✕ (leading) / ✓ (trailing, accent) per `[[project_sheet_header_hig]]`.
struct SheetCircleButton: View {
    enum Kind { case close, confirm }

    let kind: Kind
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
        }
        .buttonStyle(.plain)
        // 44pt minimum touch target per HIG even though the glyph circle is smaller.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var icon: some View {
        let glyph = Image(systemName: kind == .confirm ? "checkmark" : "xmark")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(kind == .confirm ? Color.white : Color.white.opacity(0.85))
            .frame(width: size, height: size)

        switch kind {
        case .confirm:
            glyph.background(NotoTheme.accent, in: Circle())
        case .close:
            if #available(iOS 26, macOS 26, *) {
                glyph.glassEffect(.regular.interactive(), in: .circle)
            } else {
                glyph
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5) }
            }
        }
    }
}
