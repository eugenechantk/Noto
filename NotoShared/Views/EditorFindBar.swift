import SwiftUI

/// In-note find bar (v2 design `FindBar` / `NoTabsFindInText`): a full-width glass
/// pill (magnifier + query with accent caret + "n / total" count + prev/next) plus a
/// separate glass "Done" pill. Sits at the bottom, above the keyboard.
struct EditorFindBar: View {
    @Binding var query: String
    var status: EditorFindStatus
    var onNavigate: (EditorFindNavigationDirection) -> Void
    var onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        controls
        .buttonStyle(.plain)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onKeyPress(.downArrow) { onNavigate(.next); return .handled }
        .onKeyPress(.rightArrow) { onNavigate(.next); return .handled }
        .onKeyPress(.upArrow) { onNavigate(.previous); return .handled }
        .onKeyPress(.leftArrow) { onNavigate(.previous); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    @ViewBuilder
    private var controls: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                controlRow
            }
        } else {
            controlRow
        }
        #else
        controlRow
        #endif
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            searchPill
            doneButton
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NotoTheme.muted)
                .accessibilityHidden(true)

            TextField("Find in Note", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NotoTheme.head)
                .tint(NotoTheme.accent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("editor_find_field")
                .onSubmit {
                    onNavigate(.next)
                }

            if status.matchCount > 0 {
                Text(countText)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(NotoTheme.muted)
                    .accessibilityIdentifier("editor_find_count")
            }

            Button {
                onNavigate(.previous)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(status.matchCount == 0)
            .contentShape(Rectangle())
            .accessibilityIdentifier("editor_find_previous_button")
            .accessibilityLabel("Previous Occurrence")

            Button {
                onNavigate(.next)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(status.matchCount == 0)
            .contentShape(Rectangle())
            .accessibilityIdentifier("editor_find_next_button")
            .accessibilityLabel("Next Occurrence")
        }
        .foregroundStyle(NotoTheme.head)
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .frame(height: Self.controlHeight)
        .frame(maxWidth: .infinity)
        .editorFindGlassCapsule()
        .accessibilityIdentifier("editor_find_search_field")
    }

    private var doneButton: some View {
        Button(action: onClose) {
            Text("Done")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotoTheme.accent)
                .padding(.horizontal, 18)
                .frame(height: Self.controlHeight)
                .editorFindGlassCapsule()
        }
        .contentShape(Capsule())
        .accessibilityIdentifier("editor_find_close_button")
        .accessibilityLabel("Done")
    }

    private var countText: String {
        let current = (status.selectedMatchIndex ?? 0) + 1
        return "\(current) / \(status.matchCount)"
    }

    private static let controlHeight: CGFloat = 48
}

private extension View {
    @ViewBuilder
    func editorFindGlassCapsule() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5) }
        }
        #else
        background(.regularMaterial, in: Capsule())
        #endif
    }
}
