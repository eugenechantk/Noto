//
//  ContentView.swift
//  Noto
//
//  Thin wrapper that owns the NavigationStack and delegates to OutlineView.
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
