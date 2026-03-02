//
//  DebugPanelView.swift
//  Noto
//

import SwiftUI
import SwiftData
import NotoModels

struct DebugPanelView: View {
    let blocks: [Block]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Blocks: \(blocks.count)")
                    .font(.caption.bold())
                Divider()
                ForEach(Array(blocks.enumerated()), id: \.element.id) { i, block in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(i)] sort=\(block.sortOrder, specifier: "%.1f") depth=\(block.depth)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(block.content.isEmpty ? "(empty)" : block.content)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Text("id: \(block.id.uuidString.prefix(8))… parent: \(block.parent == nil ? "nil" : String(block.parent!.id.uuidString.prefix(8)))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Divider()
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 260)
        .background(.ultraThinMaterial)
    }
}
