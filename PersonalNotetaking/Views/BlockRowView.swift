//
//  BlockRowView.swift
//  PersonalNotetaking
//
//  Single block row component for the outline tree.
//

import SwiftUI
import SwiftData

struct BlockRowView: View {
    @Bindable var block: Block
    let onAddChild: () -> Void
    let onDelete: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onCreateLink: () -> Void
    let onShowBacklinks: () -> Void

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Indentation based on depth
            ForEach(0..<block.depth, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)
            }

            // Expand/collapse indicator (if has children)
            if !block.children.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .padding(.horizontal, 5)
            }

            // Content
            if isEditing {
                TextField("Enter content", text: $block.content)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        block.updatedAt = Date()
                        isEditing = false
                    }
            } else {
                Text(block.content.isEmpty ? "Empty block" : block.content)
                    .foregroundColor(block.content.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onAddChild) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Add child block")

                Button(action: onCreateLink) {
                    Image(systemName: "link")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Create link")

                Button(action: onShowBacklinks) {
                    Image(systemName: "arrow.turn.up.left")
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
                .help("Show backlinks")

                Menu {
                    Button("Indent", action: onIndent)
                    Button("Outdent", action: onOutdent)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(block.isArchived ? Color.gray.opacity(0.1) : Color.clear)
        )
    }
}
