import SwiftUI

/// HIG sheet-header button — a circular control sized for a sheet nav row.
/// Mirrors `SheetCircleBtn` in the v2 design (`noto-minimal-editor.jsx`):
///   • `.close`   → translucent glass circle with a neutral ✕
///   • `.confirm` → filled accent circle with a white ✓
/// Paired ✕ (leading) / ✓ (trailing, accent) per `[[project_sheet_header_hig]]`.
struct SheetCircleButton: View {
    enum Kind { case close, confirm }

    let kind: Kind
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind == .confirm ? "checkmark" : "xmark")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(kind == .confirm ? Color.white : Color.white.opacity(0.65))
                .frame(width: size, height: size)
                .background(background)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .confirm:
            Circle().fill(NotoTheme.accent)
        case .close:
            Circle().fill(Color(white: 0.45).opacity(0.30))
                .overlay { Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5) }
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
