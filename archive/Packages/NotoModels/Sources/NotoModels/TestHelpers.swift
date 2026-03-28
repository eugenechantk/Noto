//
//  TestHelpers.swift
//  NotoModels
//
//  Shared test helper for creating in-memory ModelContainer.
//

import Foundation
import SwiftData

/// Creates an in-memory ModelContainer with all NotoModels types registered.
/// Each call returns a fully isolated store (unique URL) to prevent
/// cross-test interference from cascade deletes or context resets.
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
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("noto-test-\(UUID().uuidString).sqlite")
    let config = ModelConfiguration(schema: schema, url: url, allowsSave: true)
    return try ModelContainer(for: schema, configurations: [config])
}
