import Foundation
import SwiftData
import Testing
import NotoModels
@testable import Noto

struct AppDependencyTests {
    @Test @MainActor
    func appModelContainerSupportsAppSchema() throws {
        let app = NotoApp()
        let context = app.sharedModelContainer.mainContext

        let block = Block(content: "app schema smoke", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Block>())
        #expect(fetched.contains(where: { $0.id == block.id }))
    }

    @Test @MainActor
    func sharedAppServicesInitialize() {
        _ = sharedStorageDirectory
        _ = sharedSearchDatabase
        _ = sharedDirtyStore
        _ = sharedEmbeddingModel

        #if canImport(USearch)
        _ = sharedVectorKeyStore
        _ = sharedHNSWIndex
        #endif

        #expect(true)
    }
}
