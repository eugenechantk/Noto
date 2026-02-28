//
//  PersonalNotetakingApp.swift
//  PersonalNotetaking
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData

@main
struct PersonalNotetakingApp: App {
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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
