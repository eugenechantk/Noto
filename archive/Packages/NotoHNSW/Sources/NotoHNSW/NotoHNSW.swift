//
//  NotoHNSW.swift
//  NotoHNSW
//
//  Placeholder to ensure the module compiles when USearch is not available.
//  All HNSW functionality is gated behind `#if canImport(USearch)`.
//

import Foundation

/// Whether USearch-based HNSW indexing is available at compile time.
public var isHNSWAvailable: Bool {
    #if canImport(USearch)
    return true
    #else
    return false
    #endif
}
