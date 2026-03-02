//
//  TestHelpers.swift
//  NotoModels
//
//  Shared test helper for creating in-memory ModelContainer.
//

import Foundation
import SwiftData

/// Creates an in-memory ModelContainer with all NotoModels types registered.
/// Use this in unit tests to get an isolated, ephemeral data store.
@MainActor
public func createTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Block.self,
        BlockLink.self,
        Tag.self,
        BlockTag.self,
        MetadataField.self,
        BlockEmbedding.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
