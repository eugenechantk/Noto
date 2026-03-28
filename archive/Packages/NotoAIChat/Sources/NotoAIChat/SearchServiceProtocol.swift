//
//  SearchServiceProtocol.swift
//  NotoAIChat
//

import Foundation
import NotoSearch

/// Protocol abstraction over SearchService for testability.
public protocol SearchServiceProtocol {
    @MainActor func search(rawQuery: String) async -> [SearchResult]
}

extension SearchService: SearchServiceProtocol {}
