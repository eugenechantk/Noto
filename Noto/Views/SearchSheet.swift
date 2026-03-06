//
//  SearchSheet.swift
//  Noto
//
//  Full-screen search sheet with search bar, "Ask AI" row, and results list.
//  Flushes dirty index on appear, then searches on submit.
//

import SwiftUI
import os.log
import NotoCore
import NotoSearch

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "SearchSheet")

struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    let searchService: SearchService
    let onSelectResult: (UUID) -> Void

    @State private var queryText: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var isIndexing = false
    @State private var hasSearched = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Results area
            ScrollView {
                VStack(spacing: 0) {
                    // Ask AI row
                    if !queryText.trimmingCharacters(in: .whitespaces).isEmpty {
                        askAIRow
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    if isIndexing {
                        indexingIndicator
                    } else if isSearching {
                        searchingIndicator
                    } else if hasSearched && results.isEmpty {
                        emptyResultsView
                    } else if !results.isEmpty {
                        resultsSection
                    }
                }
            }

            Spacer(minLength: 0)

            // Bottom search bar
            searchBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onChange(of: queryText) {
            debouncedSearch()
        }
        .onAppear {
            isSearchFocused = true
            Task {
                isIndexing = true
                await searchService.ensureIndexFresh()
                isIndexing = false
            }
        }
    }

    // MARK: - Ask AI Row

    private var askAIRow: some View {
        Button {
            // Future: navigate to AI chat with query
            logger.debug("Ask AI tapped: \(queryText)")
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)

                Text("Ask AI \"\(queryText)\"")
                    .font(.system(size: 20))
                    .tracking(-0.45)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 68)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("askAIRow")
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Results")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    VStack(spacing: 0) {
                        if index > 0 {
                            Divider()
                        }
                        SearchResultRow(result: result)
                            .accessibilityIdentifier("searchResultRow")
                            .onTapGesture {
                                onSelectResult(result.id)
                                dismiss()
                            }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Loading States

    private var indexingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Updating index...")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var searchingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Searching...")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var emptyResultsView: some View {
        Text("No results found")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .padding(.top, 40)
            .accessibilityIdentifier("noResultsText")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search or ask anything", text: $queryText)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .tint(.primary)
                .focused($isSearchFocused)
                .submitLabel(.send)
                .accessibilityIdentifier("searchTextField")

            if !queryText.isEmpty {
                Button {
                    debounceTask?.cancel()
                    queryText = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("clearSearchButton")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Search

    private func debouncedSearch() {
        debounceTask?.cancel()

        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            hasSearched = true
            defer { isSearching = false }
            let searchResults = await searchService.search(rawQuery: trimmed)
            guard !Task.isCancelled else { return }
            results = searchResults
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayContent)
                .font(.system(size: 20))
                .tracking(-0.45)
                .foregroundStyle(.primary)

            Text(result.breadcrumb)
                .font(.system(size: 15))
                .tracking(-0.23)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }

    /// Strip markdown formatting for display.
    private var displayContent: String {
        PlainTextExtractor.plainText(from: result.content)
    }
}
