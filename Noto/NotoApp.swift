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
    }
}
