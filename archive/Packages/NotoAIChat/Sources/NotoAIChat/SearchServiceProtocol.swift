//
//  SearchServiceProtocol.swift
//  NotoAIChat
//

import Foundation
import NotoSearchLegacy

/// Protocol abstraction over SearchService for testability.
public protocol SearchServiceProtocol {
    @MainActor func search(rawQuery: String) async -> [SearchResult]
}

extension SearchService: SearchServiceProtocol {}
