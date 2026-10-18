import NotoSearch
import NotoVault
import SwiftUI

/// The destination picker used by Capture and Inbox. A row commits immediately.
struct AddToNoteSheet: View {
    let vaultURL: URL
    let draft: String
    var pinned: [AddToCandidate] = []
    let onPick: (AddToCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var candidates: [AddToCandidate] = []
    @State private var loadedPinned: [AddToCandidate] = []
    @State private var similar: [AddToCandidate] = []
    @State private var matches: [AddToCandidate] = []
    @State private var isLoading = true
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var snippetSize: CGFloat = 14

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var pinnedRows: [AddToCandidate] { pinned.isEmpty ? loadedPinned : pinned }
    private var pinnedIDs: Set<String> { Set(pinnedRows.map(\.id)) }
    private var similarRows: [AddToCandidate] { similar.filter { !pinnedIDs.contains($0.id) } }
    private var recentRows: [AddToCandidate] {
        let shown = pinnedIDs.union(similarRows.map(\.id))
        return Array(candidates.filter { !shown.contains($0.id) }.prefix(AddToCandidates.recentLimit))
    }

    var body: some View {
        FilingKeyboardLayout {
            destinations
        } bottomBar: {
            searchBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .presentationDetents([.large])
        .background {
            FilingSheetAppearance { searchFocused = true }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task { await load() }
        .task(id: query) { await search() }
    }

    private var destinations: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("Loading notes…").accessibilityIdentifier("addToLoading")
                } else if hasQuery {
                    if isSearching { ProgressView().accessibilityIdentifier("addToSearching") }
                    if !isSearching && matches.isEmpty {
                        ContentUnavailableView.search(text: query).accessibilityIdentifier("addToNoResults")
                    } else {
                        destinationSection("\(matches.count) \(matches.count == 1 ? "note" : "notes")", items: matches, isFirst: true)
                    }
                } else {
                    if !pinnedRows.isEmpty { destinationSection("Pinned", items: pinnedRows, isFirst: true) }
                    if !similarRows.isEmpty { destinationSection("Similar", items: similarRows, isFirst: pinnedRows.isEmpty) }
                    destinationSection("Recently edited", items: recentRows, isFirst: pinnedRows.isEmpty && similarRows.isEmpty)
                    if candidates.isEmpty { ContentUnavailableView("No notes yet", systemImage: "doc", description: Text("Create a note in Library first.")) }
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .navigationTitle("Add to note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .tint(NotoTheme.ink).accessibilityIdentifier("addToCloseButton")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 3) {
                        Text("Add to note").font(.headline)
                        Text("Goes at the end of the note you pick")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("addToSheet")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your notes", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("addToSearchField")
            if !query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).foregroundStyle(.secondary)
                    .accessibilityIdentifier("addToClearSearch")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.quaternary, in: Capsule())
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    @ViewBuilder private func destinationSection(_ title: String, items: [AddToCandidate], isFirst: Bool) -> some View {
        // Plain List pins Section headers. Keep the caption in the content flow
        // so transparent sheet rows cannot scroll behind its text.
        FilingSectionCaption(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: isFirst ? 8 : 18, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        rows(items)
    }

    private func rows(_ items: [AddToCandidate]) -> some View {
        ForEach(items) { candidate in
            Button {
                onPick(candidate)
                dismiss()
            } label: {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "doc").font(.subheadline).foregroundStyle(NotoTheme.muted).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(candidate.title).font(.system(size: titleSize, weight: .semibold))
                                .foregroundStyle(NotoTheme.ink).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if hasQuery {
                                Text(dateStamp(for: candidate)).font(.footnote).foregroundStyle(NotoTheme.muted)
                                    .fixedSize()
                            }
                        }
                        Text(hasQuery ? folderPath(for: candidate) : subtitle(for: candidate))
                            .font(.subheadline).foregroundStyle(NotoTheme.muted).lineLimit(1)
                        if hasQuery, !candidate.snippet.isEmpty {
                            FilingMatchText(text: candidate.snippet, query: query, base: NotoTheme.muted)
                                .font(.system(size: snippetSize)).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("addToResultRow")
        }
    }

    private func subtitle(for candidate: AddToCandidate) -> String {
        folderPath(for: candidate) + " · " + dateStamp(for: candidate)
    }

    private func folderPath(for candidate: AddToCandidate) -> String {
        candidate.folderPath.isEmpty ? "Library" : candidate.folderPath
    }

    private func dateStamp(for candidate: AddToCandidate) -> String {
        let calendar = Calendar.current
        return calendar.isDateInToday(candidate.modifiedAt) ? "today" : calendar.isDateInYesterday(candidate.modifiedAt) ? "yesterday" : candidate.modifiedAt.formatted(.dateTime.month(.abbreviated).day())
    }

    private func load() async {
        let root = vaultURL.standardizedFileURL
        let rows = await Task.detached(priority: .userInitiated) { (try? SidebarTreeLoader().loadRows(rootURL: root)) ?? [] }.value
        candidates = AddToCandidates.recent(from: rows, vaultURL: root)
        let pinnedURLs = await Task.detached(priority: .userInitiated) {
            NotePinning(vaultRootURL: root).pinnedNotes().map(\.fileURL)
        }.value
        let byURL = Dictionary(candidates.map { ($0.url.standardizedFileURL, $0) }, uniquingKeysWith: { first, _ in first })
        loadedPinned = pinnedURLs.compactMap { byURL[$0.standardizedFileURL] }
        isLoading = false
        let text = draft
        let hits = await Task.detached(priority: .userInitiated) {
            SemanticSearch.hits(for: text, vaultURL: root, limit: 20).map { AddToCandidates.SimilarHit(relativePath: $0.relativePath, score: $0.score) }
        }.value
        guard !Task.isCancelled else { return }
        similar = AddToCandidates.similar(from: hits, candidates: candidates)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { matches = []; isSearching = false; return }
        isSearching = true
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        let root = vaultURL
        let known = candidates
        let found = await Task.detached(priority: .userInitiated) {
            let store = try? SearchIndexStore(indexDirectory: MarkdownSearchIndexer.defaultIndexDirectory(for: root))
            let results = (try? store?.search(query: text, vaultURL: root, limit: 80)) ?? []
            return AddToCandidates.searchResults(results, candidates: known, vaultURL: root, query: text)
        }.value
        guard !Task.isCancelled else { return }
        matches = found
        isSearching = false
    }
}
