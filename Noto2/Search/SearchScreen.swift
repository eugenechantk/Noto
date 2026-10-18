import NotoSearch
import NotoVault
import SwiftUI
import UIKit

/// Search owns its navigation stack; opened notes reuse the Library editor.
struct SearchScreen: View {
    let vaultController: VaultController
    var locationManager: VaultLocationManager

    @State private var model: SearchModel
    @State private var path: [SearchNavigation] = []
    @State private var recentRevision = 0
    @State private var queryFocused = false
    @State private var verificationState = SearchVerificationState.requested()
    @ObservedObject private var indexStatus = SearchIndexStatusModel.shared
    @Environment(VaultFileWatcher.self) private var fileWatcher: VaultFileWatcher?
    @Environment(\.scenePhase) private var scenePhase

    init(vaultController: VaultController, locationManager: VaultLocationManager) {
        self.vaultController = vaultController
        self.locationManager = locationManager
        _model = State(wrappedValue: SearchModel(vaultURL: vaultController.vaultURL))
    }

    private var trimmedQuery: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if let verificationState {
                    HStack {
                        Text("Controlled verification state: \(verificationState.rawValue)")
                            .accessibilityIdentifier("searchVerificationBanner")
                        Spacer()
                        Button("Dismiss") { self.verificationState = nil }
                            .accessibilityIdentifier("searchVerificationDismiss")
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                HStack(spacing: 12) {
                    SearchQueryField(text: $model.query, focused: $queryFocused)
                        .frame(height: 48)
                    if queryFocused || !trimmedQuery.isEmpty {
                        Button("Cancel") {
                            model.query = ""
                            queryFocused = false
                        }
                        .font(.body)
                        .foregroundStyle(NotoTheme.accentText)
                        .accessibilityIdentifier("searchCancelButton")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                if trimmedQuery.isEmpty {
                    recentList
                } else if model.results.isEmpty && !model.isSearching {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotoTheme.background.ignoresSafeArea())
            .navigationTitle("Search")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar(trimmedQuery.isEmpty && !queryFocused ? .visible : .hidden, for: .navigationBar)
            .navigationDestination(for: SearchNavigation.self) { route in
                BrowseDestinationView(destination: route.destination, vaultController: vaultController,
                                      onOpen: { path.append(SearchNavigation(destination: $0)) },
                                      initialFindQuery: route.initialFindQuery)
                    .id(route)
                    .toolbar(.visible, for: .navigationBar)
            }
            .task(id: recentRevision) { await model.refreshRecentNotes() }
            .onChange(of: fileWatcher?.changeCount) { _, _ in recentRevision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { _ in recentRevision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .notoSearchIndexDidChange)) { _ in
                if !trimmedQuery.isEmpty, path.isEmpty { model.refresh() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { recentRevision += 1 }
            }
            .onAppear { indexStatus.start(vaultURL: vaultController.vaultURL) }
            .onDisappear { indexStatus.stop() }
        }
    }

    private var recentList: some View {
        List {
            Section {
                ForEach(verificationState?.hidesRecentRows == true ? [] : model.recentNotes) { entry in
                    Button { open(entry.note.fileURL) } label: {
                        SearchRecentNoteRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(NotoTheme.card)
                    .listRowSeparatorTint(NotoTheme.hairline)
                    .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
                    .accessibilityIdentifier("searchRecentNote_\(entry.note.fileURL.lastPathComponent)")
                }
                if model.recentNotes.isEmpty || verificationState?.hidesRecentRows == true {
                    if model.isLoadingRecent || verificationState == .recentLoading {
                        ProgressView("Loading notes…").accessibilityIdentifier("searchRecentLoading")
                    } else if let error = verificationState == .recentError ? "Recently edited notes could not be loaded." : model.recentLoadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .foregroundStyle(NotoTheme.muted)
                                .accessibilityIdentifier("searchRecentError")
                            Button("Retry") { verificationState = nil; recentRevision += 1 }
                                .accessibilityIdentifier("searchRecentRetryButton")
                        }
                    } else {
                        Text("Notes you edit will appear here.")
                            .foregroundStyle(NotoTheme.muted)
                            .accessibilityIdentifier("searchRecentEmpty")
                    }
                }
            } header: {
                Text("RECENTLY EDITED")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.72)
                    .foregroundStyle(NotoTheme.muted)
                    .textCase(nil)
                    .accessibilityIdentifier("searchRecentHeading")
            }

            Section {
                HStack(spacing: 5) {
                    if verificationState != .partialIndex, indexStatus.keywordNotes != nil, !indexStatus.isKeywordPartial, !indexStatus.isSemanticIndexing {
                        Image(systemName: "checkmark").foregroundStyle(NotoTheme.inboxNewNote)
                    }
                    Text(indexDescription)
                }
                .font(.caption)
                .foregroundStyle(NotoTheme.faint)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("searchIndexStatus")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refreshRecentNotes() }
        .accessibilityIdentifier("searchRecentlyEdited")
    }

    /// A partial index must not present its missing hits as an empty vault.
    private var noResultsView: some View {
        let searched = model.lastSearchedQuery.isEmpty ? trimmedQuery : model.lastSearchedQuery
        let isPartial = verificationState == .partialIndex || indexStatus.isKeywordPartial
        return ContentUnavailableView {
            Label(SearchIndexCoverage.noResultsTitle(isPartial: isPartial), systemImage: "magnifyingglass")
                .accessibilityIdentifier("searchNoResults")
        } description: {
            Text(SearchIndexCoverage.noResultsDescription(query: searched, isPartial: isPartial,
                 indexedNotes: verificationState == .partialIndex ? 2 : indexStatus.keywordNotes,
                 vaultNotes: verificationState == .partialIndex ? 8 : indexStatus.vaultNotes))
        } actions: {
            if isPartial {
                Button("Resume Indexing") { resumeIndexing() }
                    .accessibilityIdentifier("searchResumeIndexingButton")
            }
        }
    }

    private var indexDescription: String {
        if verificationState == .partialIndex { return "2 of 8 notes indexed · indexing…" }
        guard indexStatus.keywordNotes != nil else { return "Checking the search index…" }
        let count = SearchIndexCoverage.summary(indexedNotes: indexStatus.keywordNotes, vaultNotes: indexStatus.vaultNotes)
        if indexStatus.isKeywordPartial { return "\(count) indexed · indexing…" }
        if indexStatus.isSemanticIndexing { return "\(count) indexed · building semantic index…" }
        return "\(count) indexed · up to date"
    }

    private func resumeIndexing() {
        verificationState = nil
        let vaultURL = vaultController.vaultURL
        Task.detached(priority: .userInitiated) {
            _ = try? await SearchIndexController.shared.refresh(vaultURL: vaultURL)
        }
    }

    private var resultsList: some View {
        List {
            Section {
                if model.isSearching && model.results.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Searching…")
                    }
                    .font(.footnote)
                    .foregroundStyle(NotoTheme.muted)
                    .listRowBackground(NotoTheme.background)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("searchInProgress")
                }
                ForEach(model.results) { result in
                    Button { open(result.fileURL, query: model.lastSearchedQuery) } label: {
                        SearchResultRow(result: result, query: model.lastSearchedQuery, vaultURL: vaultController.vaultURL)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(NotoTheme.hairline)
                    .listRowBackground(NotoTheme.background)
                    .accessibilityIdentifier("searchResult_\(result.fileURL.lastPathComponent)")
                }
            } header: {
                if !model.results.isEmpty {
                    Text("\(model.results.count) NOTE\(model.results.count == 1 ? "" : "S")")
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.72)
                        .foregroundStyle(NotoTheme.muted)
                        .textCase(nil)
                        .accessibilityIdentifier("searchResultCount")
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(NotoTheme.background)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("searchResults")
    }

    private func open(_ fileURL: URL, query: String? = nil) {
        guard let destination = BrowseDestination.note(at: fileURL, in: vaultController) else { return }
        queryFocused = false
        path.append(SearchNavigation(destination: destination, query: query))
    }
}

private struct SearchRecentNoteRow: View {
    let entry: LibraryNote

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.folderPath == "Daily Notes" ? "calendar" : "doc")
                .font(.subheadline)
                .foregroundStyle(NotoTheme.muted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.note.title.isEmpty ? "Untitled" : entry.note.title)
                    .font(.body.weight(.medium)).foregroundStyle(NotoTheme.ink).lineLimit(1)
                Text(entry.folderPath.isEmpty ? "Vault" : entry.folderPath.replacingOccurrences(of: "/", with: " › "))
                    .font(.subheadline).foregroundStyle(NotoTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            dateLabel.font(.caption).foregroundStyle(NotoTheme.muted).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var dateLabel: some View {
        let date = entry.note.modifiedDate
        if Calendar.current.isDateInToday(date) {
            Text(date, format: .dateTime.hour().minute())
        } else if Calendar.current.isDateInYesterday(date) {
            Text("Yesterday")
        } else if Date().timeIntervalSince(date) < 7 * 24 * 60 * 60 {
            Text(date, format: .dateTime.weekday(.abbreviated))
        } else {
            Text(date, format: .dateTime.month(.abbreviated).day())
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let vaultURL: URL

    private var title: String { result.title.isEmpty ? "Untitled" : result.title }
    private var showsSnippet: Bool { !result.snippet.isEmpty && result.snippet != result.title }
    private var breadcrumb: String {
        let root = vaultURL.standardizedFileURL.path
        let dir = result.fileURL.standardizedFileURL.deletingLastPathComponent().path
        guard dir.hasPrefix(root + "/") else { return "Vault" }
        return dir.dropFirst(root.count + 1).split(separator: "/").joined(separator: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold)).foregroundStyle(NotoTheme.head).lineLimit(1)
                    .accessibilityIdentifier("searchResultTitle")
                Spacer(minLength: 8)
                if let date = result.updatedAt ?? result.createdAt {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption).foregroundStyle(NotoTheme.faint)
                }
            }
            if showsSnippet {
                Text(SnippetEmphasis.attributed(result.snippet, query: query, base: NotoTheme.muted,
                     emphasis: NotoTheme.ink, highlight: NotoTheme.accentSoft))
                    .lineLimit(2)
                    .accessibilityIdentifier("searchResultSnippet")
            }
            Text(breadcrumb).font(.caption).foregroundStyle(NotoTheme.faint).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
