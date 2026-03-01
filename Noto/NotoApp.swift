//
//  NotoApp.swift
//  Noto
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotoApp")

@main
struct NotoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Block.self,
            BlockLink.self,
            Tag.self,
            BlockTag.self,
            MetadataField.self,
            BlockEmbedding.self,
            SearchIndex.self,
        ])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.environment["UITESTING"] == "1"
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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
