import SwiftUI
import NotoChat

/// One edit-suggestion card (one spot in a note), styled like the grep/read/list
/// tool steps: a 1.5px left rule + quiet indented content. Leads with a tool-name
/// label `Suggested Edits ・ [doc] <file>`, then a GitHub-style diff with context
/// lines, expand chevrons, and a quiet Dismiss / orange-ink Accept footer.
struct EditBlockView: View {
    let state: ChatSession.EditBlockState
    var onAccept: () -> Void
    var onDismiss: () -> Void
    var onExpand: (_ up: Bool) -> Void

    // GitHub-ish dark diff palette.
    private static let addedFg = Color(hex: 0x7EE787)
    private static let addedBg = Color(hex: 0x2EA043).opacity(0.16)
    private static let removedFg = Color(hex: 0xFFA198)
    private static let removedBg = Color(hex: 0xF85149).opacity(0.16)
    private static let muted = Color(white: 0.925).opacity(0.55)
    private static let diffFont = SwiftUI.Font.system(size: 12.5, design: .monospaced)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1.5)
            VStack(alignment: .leading, spacing: 6) {
                header
                switch state.status {
                case .proposed:
                    diffBody
                    footer
                case .applied:
                    terminal(icon: "checkmark", tint: NotoChatTokens.accent, label: "Applied", struck: false)
                case .dismissed:
                    terminal(icon: "xmark", tint: Self.muted, label: "Dismissed", struck: true)
                case .stale:
                    terminal(icon: "exclamationmark.triangle", tint: Self.muted, label: "No longer applies", struck: true)
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("chat.editCard")
    }

    // MARK: Header — "Suggested Edits ・ [doc] <file>"

    private var header: some View {
        HStack(spacing: 6) {
            (Text("Suggested Edits").foregroundStyle(Self.muted)
                + Text("  ・  ").foregroundStyle(NotoChatTokens.faint)
                + Text(Image(systemName: "doc")).foregroundStyle(NotoChatTokens.faint)
                + Text(" ")
                + Text(headerTitle).foregroundStyle(NotoChatTokens.ink))
                .font(.system(size: 13.5))
                .lineLimit(1).truncationMode(.middle)
            if let hint = state.locationHint, state.status == .proposed {
                Text("· \(hint)").font(.system(size: 12)).foregroundStyle(NotoChatTokens.faint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("chat.editCard.header")
    }

    private var headerTitle: String {
        if let crumb = state.breadcrumb, !crumb.isEmpty { return "\(crumb) › \(state.title)" }
        return state.title
    }

    // MARK: Diff body — context + −/+ rows with expand chevrons

    private var diffBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.preview.canExpandUp {
                expandChevron(up: true)
            }
            ForEach(Array(state.preview.lines.enumerated()), id: \.offset) { _, line in
                diffRow(line)
            }
            if state.preview.canExpandDown {
                expandChevron(up: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(NotoChatTokens.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func diffRow(_ line: DiffLine) -> some View {
        let marker: String = line.kind == .removed ? "−" : (line.kind == .added ? "+" : " ")
        HStack(alignment: .top, spacing: 6) {
            Text(marker).frame(width: 8, alignment: .leading)
                .foregroundStyle(markerColor(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(textColor(line.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Self.diffFont)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(line.kind))
    }

    private func expandChevron(up: Bool) -> some View {
        Button { onExpand(up) } label: {
            HStack {
                Spacer()
                Image(systemName: up ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotoChatTokens.faint)
                Spacer()
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.03))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(up ? "chat.editCard.expandUp" : "chat.editCard.expandDown")
    }

    private func markerColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .removed: return Self.removedFg
        case .added: return Self.addedFg
        case .context: return NotoChatTokens.faint
        }
    }
    private func textColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .removed: return Self.removedFg
        case .added: return Self.addedFg
        case .context: return Color(white: 0.925).opacity(0.5)
        }
    }
    private func rowBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .removed: return Self.removedBg
        case .added: return Self.addedBg
        case .context: return .clear
        }
    }

    // MARK: Footer — quiet Dismiss / orange-ink Accept

    private var footer: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Text("Dismiss").font(.system(size: 13))
                    .foregroundStyle(NotoChatTokens.faint)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.editCard.dismiss")

            Button(action: onAccept) {
                Text("Accept").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotoChatTokens.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.editCard.accept")
        }
        .padding(.top, 2)
    }

    // MARK: Terminal status line

    private func terminal(icon: String, tint: Color, label: String, struck: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            (Text(label).foregroundStyle(tint)
                + Text("  ・  ").foregroundStyle(NotoChatTokens.faint)
                + Text(headerTitle).foregroundStyle(NotoChatTokens.faint).strikethrough(struck))
                .font(.system(size: 12.5))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(state.status == .applied ? "chat.editCard.applied" : "chat.editCard.dismissed")
    }
}

#if DEBUG
private func previewState(status: ChatSession.EditBlockState.Status,
                          path: String = "Pricing.md", title: String = "Pricing notes",
                          breadcrumb: String? = nil) -> ChatSession.EditBlockState {
    let body = """
    # Pricing notes

    ## Intro
    The pricing page is honestly our most important conversion surface and we should really invest in it.

    ## Tiers
    - Free
    - Pro $29
    """
    let (blocks, _) = EditApplier.plan(
        [.edit(target: "The pricing page is honestly our most important conversion surface and we should really invest in it.",
               replacement: "Pricing is our top conversion surface — worth steady investment.")],
        in: body)
    let block = blocks[0]
    return ChatSession.EditBlockState(
        targetPath: path, title: title, breadcrumb: breadcrumb, locationHint: block.locationHint,
        block: block, preview: block.preview,
        beforeRadius: EditApplier.defaultContextRadius, afterRadius: EditApplier.defaultContextRadius,
        status: status)
}

#Preview("Edit cards") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            EditBlockView(state: previewState(status: .proposed), onAccept: {}, onDismiss: {}, onExpand: { _ in })
            EditBlockView(state: previewState(status: .proposed, path: "Projects/Alpha/Q2.md",
                                              title: "Q2 model", breadcrumb: "Projects › Alpha"),
                          onAccept: {}, onDismiss: {}, onExpand: { _ in })
            EditBlockView(state: previewState(status: .applied), onAccept: {}, onDismiss: {}, onExpand: { _ in })
            EditBlockView(state: previewState(status: .dismissed), onAccept: {}, onDismiss: {}, onExpand: { _ in })
        }
        .padding()
    }
    .background(NotoChatTokens.bg)
}
#endif
