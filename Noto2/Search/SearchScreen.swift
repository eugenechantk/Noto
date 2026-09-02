import NotoSearch
import SwiftUI

/// Search tab: a field, a count, and rows with the match emphasized. The
/// streamed summary is a plain paragraph above the rows — no card. Tapping a
/// hit opens the note in the editor.
struct SearchScreen: View {
    let vaultController: VaultController
    var locationManager: VaultLocationManager

    @State private var model: SearchModel
    @State private var showSettings = false
    @State private var path: [BrowseDestination] = []
    @FocusState private var queryFocused: Bool
    @ObservedObject private var indexStatus = SearchIndexStatusModel.shared

    init(vaultController: VaultController, locationManager: VaultLocationManager) {
        self.vaultController = vaultController
        self.locationManager = locationManager
        _model = State(wrappedValue: SearchModel(vaultURL: vaultController.vaultURL))
    }

    private var trimmedQuery: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchField
                Group {
                    if trimmedQuery.isEmpty {
                        ContentUnavailableView {
                            Label("Search your notes", systemImage: "magnifyingglass")
                        } description: {
                            Text(indexDescription)
                        }
                        .accessibilityIdentifier("searchEmptyPrompt")
                    } else if model.results.isEmpty && !model.isSearching {
                        noResultsView
                    } else {
                        resultsList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(NotoTheme.background.ignoresSafeArea())
            // `.searchable` cannot sit flush here: with a drawer placement it
            // hangs below an empty inline title row (~44pt of blank bar), and
            // hiding that bar takes the field with it. Search is this screen's
            // only chrome, so the field is drawn directly under the safe area.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings, onDismiss: { model.refresh() }) {
                OpenRouterSettingsSheet(locationManager: locationManager)
            }
            .navigationDestination(for: BrowseDestination.self) { destination in
                BrowseDestinationView(destination: destination, vaultController: vaultController, onOpen: { path.append($0) })
            }
            .onReceive(NotificationCenter.default.publisher(for: .notoSearchIndexDidChange)) { _ in
                // The index grows in the background on first launch; re-run so
                // results fill in without retyping.
                if !trimmedQuery.isEmpty, path.isEmpty { model.refresh() }
            }
            .onAppear {
                indexStatus.start(vaultURL: vaultController.vaultURL)
            }
            .onDisappear {
                indexStatus.stop()
            }
        }
    }

    /// Matches the system search field's shape and fill (`chipFill` is the same
    /// translucent grey UIKit uses) so replacing `.searchable` costs no fidelity.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NotoTheme.muted)
            TextField("Search notes", text: $model.query)
                .textFieldStyle(.plain)
                .focused($queryFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("searchField")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    queryFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NotoTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("searchClearButton")
            }
        }
        .font(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule().fill(NotoTheme.chipFill))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// "No results" is only trustworthy when the index actually covers the
    /// vault, so say which case this is and offer the resume sweep.
    /// See `SearchIndexCoverage` for why.
    private var noResultsView: some View {
        let searched = model.lastSearchedQuery.isEmpty ? trimmedQuery : model.lastSearchedQuery
        let isPartial = indexStatus.isKeywordPartial
        return ContentUnavailableView {
            Label(SearchIndexCoverage.noResultsTitle(isPartial: isPartial), systemImage: "magnifyingglass")
        } description: {
            Text(SearchIndexCoverage.noResultsDescription(
                query: searched,
                isPartial: isPartial,
                indexedNotes: indexStatus.keywordNotes,
                vaultNotes: indexStatus.vaultNotes
            ))
        } actions: {
            if isPartial {
                Button("Resume Indexing") { resumeIndexing() }
                    .accessibilityIdentifier("searchResumeIndexingButton")
            }
        }
        .accessibilityIdentifier("searchNoResults")
    }

    private var indexDescription: String {
        var parts: [String] = []
        if indexStatus.keywordNotes != nil {
            parts.append("\(SearchIndexCoverage.summary(indexedNotes: indexStatus.keywordNotes, vaultNotes: indexStatus.vaultNotes)) indexed")
        }
        if indexStatus.isSemanticIndexing {
            parts.append("building semantic index…")
        }
        return parts.isEmpty ? "Titles and bodies, keyword and meaning." : parts.joined(separator: " · ")
    }

    /// Re-runs the whole-vault sweep. Evicted iCloud notes get another download
    /// kick and are indexed as their bodies land.
    private func resumeIndexing() {
        let vaultURL = vaultController.vaultURL
        Task.detached(priority: .userInitiated) {
            _ = try? await SearchIndexController.shared.refresh(vaultURL: vaultURL)
        }
    }

    private var resultsList: some View {
        List {
            if model.summaryState != .idle {
                Section {
                    SummaryParagraph(model: model, onOpenSettings: { showSettings = true })
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(NotoTheme.background)
                }
            }

            Section {
                if model.isSearching && model.results.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Searching…")
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                    .listRowBackground(NotoTheme.background)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("searchInProgress")
                }
                ForEach(model.results) { result in
                    Button {
                        open(result)
                    } label: {
                        SearchResultRow(result: result, query: model.lastSearchedQuery, vaultURL: vaultController.vaultURL)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(AppTheme.separator)
                    .listRowBackground(NotoTheme.background)
                    .accessibilityIdentifier("searchResultRow")
                }
            } header: {
                if !model.results.isEmpty {
                    Text("\(model.results.count) result\(model.results.count == 1 ? "" : "s") for “\(model.lastSearchedQuery)”")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                        .textCase(nil)
                        .accessibilityIdentifier("searchResultCount")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(NotoTheme.background)
        .scrollDismissesKeyboard(.interactively)
    }

    private func open(_ result: SearchResult) {
        guard let destination = BrowseDestination.note(at: result.fileURL, in: vaultController) else { return }
        queryFocused = false
        path.append(destination)
    }

}

/// Title · date on one line, the snippet with the match emphasized, and the
/// folder breadcrumb when the note is not at the root.
private struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let vaultURL: URL

    private var title: String { result.title.isEmpty ? "Untitled" : result.title }
    private var showsSnippet: Bool { !result.snippet.isEmpty && result.snippet != result.title }
    /// Folder path from the vault root, "Folder › Subfolder"; empty at the root.
    private var breadcrumb: String {
        let root = vaultURL.standardizedFileURL.path
        let dir = result.fileURL.standardizedFileURL.deletingLastPathComponent().path
        guard dir.hasPrefix(root + "/") else { return "" }
        return dir.dropFirst(root.count + 1).split(separator: "/").joined(separator: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if result.kind == .section {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier("searchResultTitle")
                Spacer(minLength: 8)
                if let date = result.updatedAt ?? result.createdAt {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            if showsSnippet {
                Text(SnippetEmphasis.attributed(result.snippet, query: query, base: AppTheme.secondaryText, emphasis: AppTheme.primaryText))
                    .lineLimit(2)
                    .accessibilityIdentifier("searchResultSnippet")
            }
            if !breadcrumb.isEmpty {
                Text(breadcrumb)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// "Summary" caption + the streamed paragraph + a provenance line. No card.
private struct SummaryParagraph: View {
    let model: SearchModel
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Summary")
                if model.summaryState == .streaming {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.mutedText)
            .accessibilityIdentifier("searchSummaryCaption")

            switch model.summaryState {
            case .idle:
                EmptyView()
            case .needsKey:
                Button("Add an OpenRouter key to summarize", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(NotoTheme.accent)
                    .accessibilityIdentifier("summaryAddKeyButton")
            case .streaming, .done:
                if model.summary.isEmpty {
                    Text("Reading the top notes…")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    Text(SummaryPromptBuilder.rendered(model.summary))
                        .font(.body)
                        .foregroundStyle(AppTheme.primaryText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("summaryText")
                    if model.summaryState == .done {
                        HStack(spacing: 4) {
                            Text(summaryProvenance)
                            if model.summaryOrigin == .offlineHighlights {
                                Text("·")
                                Button(model.hasAIKey ? "Retry AI" : "Add AI key") {
                                    if model.hasAIKey { model.retrySummary() } else { onOpenSettings() }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(NotoTheme.accent)
                                .accessibilityIdentifier(model.hasAIKey ? "summaryRetryAIButton" : "summaryAddKeyButton")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                    }
                }
            case .failed:
                HStack(spacing: 4) {
                    Text("Summary unavailable ·")
                    Button("Retry") { model.retrySummary() }
                        .buttonStyle(.plain)
                        .foregroundStyle(NotoTheme.accent)
                        .accessibilityIdentifier("summaryRetryButton")
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryProvenance: String {
        let notes = "From the top \(model.summarySourceCount) note\(model.summarySourceCount == 1 ? "" : "s")"
        switch model.summaryOrigin {
        case .remoteAI:
            return notes + " · AI-generated"
        case .offlineHighlights:
            guard let reason = model.summaryFallbackReason else { return notes + " · Offline highlights" }
            return notes + " · Offline highlights (\(reason))"
        }
    }
}
