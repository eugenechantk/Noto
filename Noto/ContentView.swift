//
//  ContentView.swift
//  PersonalNotetaking
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TestOutlineView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
