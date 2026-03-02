//
//  NotoApp.swift
//  Noto
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData
import os.log
import NotoModels
import NotoFTS5
import NotoDirtyTracker
import NotoEmbedding

#if canImport(USearch)
import NotoHNSW
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

/// Shared storage directory for the app lifecycle.
@MainActor
let sharedStorageDirectory: URL = {
    let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        || ProcessInfo.processInfo.environment["UITESTING"] == "1"
    if isUITesting {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("noto-uitest-\(UUID().uuidString)")
    } else {
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
}()

/// Shared FTS5Database for the app lifecycle. Accessible from all views via module scope.
@MainActor
let sharedSearchDatabase: FTS5Database = {
    let db = FTS5Database(directory: sharedStorageDirectory)
    Task { await db.createTablesIfNeeded() }
    return db
}()

/// Shared DirtyStore for the app lifecycle.
@MainActor
let sharedDirtyStore: DirtyStore = {
    let store = DirtyStore(directory: sharedStorageDirectory)
    Task { await store.createTablesIfNeeded() }
    return store
}()

/// Shared EmbeddingModel for the app lifecycle. nil if model/vocab not bundled.
@MainActor
let sharedEmbeddingModel: EmbeddingModel? = {
    do {
        return try EmbeddingModel()
    } catch {
        logger.info("EmbeddingModel not available: \(error). Semantic search disabled.")
        return nil
    }
}()

#if canImport(USearch)
/// Shared VectorKeyStore for the app lifecycle.
@MainActor
let sharedVectorKeyStore: VectorKeyStore = {
    let store = VectorKeyStore(directory: sharedStorageDirectory)
    Task { await store.createTablesIfNeeded() }
    return store
}()

/// Shared HNSWIndex for the app lifecycle.
@MainActor
let sharedHNSWIndex: HNSWIndex = {
    let indexPath = sharedStorageDirectory.appendingPathComponent("vectors.usearch")
    return HNSWIndex(path: indexPath, vectorKeyStore: sharedVectorKeyStore)
}()
#endif

@MainActor
private let sharedDirtyTracker: DirtyTracker = {
    DirtyTracker(dirtyStore: sharedDirtyStore)
}()

@main
struct NotoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.environment["UITESTING"] == "1"
        let schema = Schema([
            Block.self,
            BlockLink.self,
            Tag.self,
            BlockTag.self,
            MetadataField.self,
            BlockEmbedding.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            logger.error("ModelContainer creation failed: \(error). Deleting old store and retrying.")
            // Delete the old store and retry — handles schema migration failures
            if !isUITesting {
                let url = modelConfiguration.url
                let related = [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")]
                for file in related {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
            }
        }
    }()

    @StateObject private var dirtyTracker = sharedDirtyTracker

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dirtyTracker)
                .task {
                    await runLaunchReconciliation()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await dirtyTracker.flush() }
            }
        }
    }

    /// Launch-time safety net: catches blocks missed by dirty tracking
    /// (e.g., app force-killed before flush).
    @MainActor
    private func runLaunchReconciliation() async {
        let bgContext = ModelContext(sharedModelContainer)
        let reconciler = IndexReconciler(fts5Database: sharedSearchDatabase, dirtyStore: sharedDirtyStore, modelContext: bgContext)
        await reconciler.reconcileIfNeeded()

        #if canImport(USearch)
        // Rebuild HNSW index from persisted BlockEmbedding records if index file is missing
        if let embeddingModel = sharedEmbeddingModel {
            let indexPath = sharedStorageDirectory.appendingPathComponent("vectors.usearch")
            if !FileManager.default.fileExists(atPath: indexPath.path) {
                let indexer = EmbeddingIndexer(embeddingModel: embeddingModel, hnswIndex: sharedHNSWIndex, modelContext: bgContext)
                await indexer.rebuildIndex()
                logger.info("Rebuilt HNSW index from persisted embeddings")
            }
        }
        #endif
    }
}
