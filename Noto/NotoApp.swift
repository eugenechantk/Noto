//
//  NotoApp.swift
//  Noto
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData

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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
