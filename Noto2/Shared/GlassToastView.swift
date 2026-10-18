import SwiftUI

/// The confirmation toast used across Noto 2 (Capture now, Inbox next).
///
/// iOS has no system toast, so this is a deliberate custom Liquid Glass
/// surface: one glass capsule with plain text buttons inside it — never glass
/// on glass. Under Reduce Transparency it becomes an opaque capsule. Pass `nil`
/// for an action the toast should not offer.
struct GlassToastView: View {
    let message: String
    let systemImage: String
    var iconColor: Color = NotoTheme.ink
    var onUndo: (() -> Void)?
    var onOpen: (() -> Void)?
    /// Accessibility identifier root: `<id>`, `<id>Message`, `<id>Undo`, `<id>Open`.
    var identifier: String = "glassToast"

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 2) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .font(.subheadline)
            .foregroundStyle(NotoTheme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .accessibilityIdentifier(identifier + "Message")

            if let onUndo {
                toastButton("Undo", color: NotoTheme.accentText, identifier: identifier + "Undo", action: onUndo)
            }
            if let onOpen {
                toastButton("Open", color: NotoTheme.ink, identifier: identifier + "Open", action: onOpen)
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, onUndo != nil || onOpen != nil ? 4 : 6)
        .frame(minHeight: 48)
        .background {
            if reduceTransparency {
                Capsule().fill(NotoTheme.secondaryFill)
            }
        }
        .modifier(GlassCapsule(enabled: !reduceTransparency))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func toastButton(_ title: String, color: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
            .contentShape(Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
    }
}

private struct GlassCapsule: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
        }
    }
}
