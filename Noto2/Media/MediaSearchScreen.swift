import SwiftUI

/// Search is a destination so Back from a source note retains the query and board.
struct MediaSearchScreen<Content: View>: View {
    @Binding var query: String
    @ViewBuilder var content: () -> Content
    @FocusState private var isFocused: Bool
    @State private var didFocus = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NotoTheme.muted)
                TextField("Search your media", text: $query)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit { isFocused = false }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityHint("Searches note content and saved link metadata")
                    .accessibilityIdentifier("media_search_field")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(NotoTheme.muted)
                            .frame(minWidth: 32, minHeight: 44)
                    }
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("media_clear_search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(NotoTheme.head.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            content()
        }
        .background(NotoTheme.background.ignoresSafeArea())
        .navigationTitle("Search Media")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("media_search_screen")
        .task {
            guard !didFocus else { return }
            didFocus = true
            isFocused = true
        }
        .onDisappear { isFocused = false }
    }
}
