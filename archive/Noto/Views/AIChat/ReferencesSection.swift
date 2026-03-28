//
//  ReferencesSection.swift
//  Noto
//
//  "Found N notes" expandable section with bullet list of referenced blocks.
//

import SwiftUI
import os.log
import NotoAIChat

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ReferencesSection")

struct ReferencesSection: View {
    let references: [BlockReference]
    @State private var isExpanded = true

    private let maxVisible = 5

    private var visibleRefs: [BlockReference] {
        Array(references.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, references.count - maxVisible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Found \(references.count) notes")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.23)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Found \(references.count) notes, \(isExpanded ? "collapse" : "expand")")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleRefs, id: \.blockId) { ref in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\u{25B8}")
                                .font(.system(size: 15))
                                .tracking(-0.23)
                                .foregroundStyle(.secondary)

                            Text(ref.content)
                                .font(.system(size: 15))
                                .tracking(-0.23)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if overflowCount > 0 {
                        Text("and \(overflowCount) more")
                            .font(.system(size: 14))
                            .tracking(-0.23)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
