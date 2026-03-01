//
//  ScrollableBreadcrumb.swift
//  Noto
//
//  Horizontally scrollable, right-aligned breadcrumb for deep navigation paths.
//  Clips left edge; deepest (current) segments are always visible.
//

import SwiftUI

struct ScrollableBreadcrumb: View {
    let navigationPath: [Block]
    let currentNode: Block

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        breadcrumbSegment("Home", isLast: navigationPath.isEmpty)
                            .id("home")

                        ForEach(Array(navigationPath.enumerated()), id: \.element.id) { index, block in
                            separator

                            let isLast = block.id == currentNode.id
                            let label = block.content.isEmpty ? "Untitled" : block.content
                            breadcrumbSegment(label, isLast: isLast)
                                .id(block.id.uuidString)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    // Scroll to the current (rightmost) segment
                    proxy.scrollTo(currentNode.id.uuidString, anchor: .trailing)
                }
                .onChange(of: navigationPath.count) {
                    proxy.scrollTo(currentNode.id.uuidString, anchor: .trailing)
                }
            }
        }
        .frame(height: 20)
        .accessibilityIdentifier("breadcrumb")
    }

    private func breadcrumbSegment(_ text: String, isLast: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isLast ? .primary : Color(red: 0.45, green: 0.45, blue: 0.45))
            .tracking(-0.25)
            .lineLimit(1)
            .fixedSize()
    }

    private var separator: some View {
        Text(" / ")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
            .tracking(-0.25)
            .fixedSize()
    }
}
