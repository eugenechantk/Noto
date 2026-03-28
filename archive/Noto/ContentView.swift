//
//  ContentView.swift
//  Noto
//
//  Root view: OutlineView for the continuous outline editor.
//  node=nil shows root blocks, double-tap drills into a block.
//

import SwiftUI
import SwiftData
import NotoModels

struct ContentView: View {
    @State private var navigationPath: [Block] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            OutlineView(node: nil, navigationPath: $navigationPath)
                .navigationDestination(for: Block.self) { block in
                    OutlineView(node: block, navigationPath: $navigationPath)
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self], inMemory: true)
}
