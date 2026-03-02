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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool

    let searchService: SearchService
    let onSelectResult: (UUID) -> Void

    @State private var queryText: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var isIndexing = false
    @State private var hasSearched = false

    var body: some View {
        VStack(spacing: 0) {
            // Results area
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Ask AI row
                    if !queryText.trimmingCharacters(in: .whitespaces).isEmpty {
                        askAIRow
                    }

                    if isIndexing {
                        indexingIndicator
                    } else if isSearching {
                        searchingIndicator
                    } else if hasSearched && results.isEmpty {
                        emptyResultsView
                    } else {
                        ForEach(results) { result in
                            SearchResultRow(result: result)
                                .onTapGesture {
                                    onSelectResult(result.id)
                                    dismiss()
                                }
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)

            // Bottom search bar
            searchBar
        }
        .background(backgroundColor.ignoresSafeArea())
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
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.blue)

                Text("Ask AI \"\(queryText)\"")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("askAIRow")
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
                .onSubmit {
                    performSearch()
                }
                .submitLabel(.search)

            if !queryText.isEmpty {
                Button {
                    queryText = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.07)
            : .white
    }

    // MARK: - Search

    private func performSearch() {
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        hasSearched = true

        Task {
            results = await searchService.search(rawQuery: trimmed)
            isSearching = false
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayContent)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .lineLimit(3)

            Text(result.breadcrumb)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    /// Strip markdown formatting for display.
    private var displayContent: String {
        PlainTextExtractor.plainText(from: result.content)
    }
}
