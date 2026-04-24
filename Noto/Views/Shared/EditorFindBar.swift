import SwiftUI

struct EditorFindBar: View {
    @Binding var query: String
    var status: EditorFindStatus
    var onNavigate: (EditorFindNavigationDirection) -> Void
    var onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        controls
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(AppTheme.primaryText)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onKeyPress(.downArrow) {
            onNavigate(.next)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            onNavigate(.next)
            return .handled
        }
        .onKeyPress(.upArrow) {
            onNavigate(.previous)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            onNavigate(.previous)
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    @ViewBuilder
    private var controls: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
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
            closeButton
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .accessibilityHidden(true)

            TextField("Find in Note", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .frame(width: 128)
                .accessibilityIdentifier("editor_find_field")
                .onSubmit {
                    onNavigate(.next)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityIdentifier("editor_find_clear_query_button")
                .accessibilityLabel("Clear Search Text")
            }

            Divider()
                .frame(height: 18)
                .overlay(AppTheme.primaryText.opacity(0.12))
                .padding(.horizontal, 2)

            Button {
                onNavigate(.previous)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 36, height: Self.controlHeight)
            }
            .disabled(status.matchCount == 0)
            .contentShape(Rectangle())
            .accessibilityIdentifier("editor_find_previous_button")
            .accessibilityLabel("Previous Occurrence")

            Button {
                onNavigate(.next)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 36, height: Self.controlHeight)
            }
            .disabled(status.matchCount == 0)
            .contentShape(Rectangle())
            .accessibilityIdentifier("editor_find_next_button")
            .accessibilityLabel("Next Occurrence")
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(height: Self.controlHeight)
        .editorFindGlassCapsule()
        .overlay {
            Capsule()
                .stroke(AppTheme.primaryText.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityIdentifier("editor_find_search_field")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .editorFindGlassCircle()
                .overlay {
                    Circle()
                        .stroke(AppTheme.primaryText.opacity(0.10), lineWidth: 0.5)
                }
        }
        .contentShape(Circle())
        .accessibilityIdentifier("editor_find_close_button")
        .accessibilityLabel("Close Search")
    }

    private static let controlHeight: CGFloat = 44
}

private extension View {
    @ViewBuilder
    func editorFindGlassCapsule() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
        #else
        background(.regularMaterial, in: Capsule())
        #endif
    }

    @ViewBuilder
    func editorFindGlassCircle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
        #else
        background(.regularMaterial, in: Circle())
        #endif
    }
}
