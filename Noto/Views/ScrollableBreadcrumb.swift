//
//  ScrollableBreadcrumb.swift
//  Noto
//
//  Horizontally scrollable, right-aligned breadcrumb showing the full hierarchy
//  path from Home to the current node. Derives the path from the ancestor chain
//  passed in by the parent view. Each segment is tappable to navigate to that node.
//

import SwiftUI
import NotoModels

struct ScrollableBreadcrumb: View {
    /// Full ancestor path from root to current node (inclusive), computed by the caller.
    let ancestors: [Block]
    let currentNode: Block
    @Binding var navigationPath: [Block]

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Button {
                            navigationPath.removeAll()
                        } label: {
                            breadcrumbSegment("Home", isLast: ancestors.isEmpty)
                        }
                        .id("home")

                        ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, block in
                            separator

                            let isLast = block.id == currentNode.id
                            let label = block.content.isEmpty ? "Untitled" : block.content

                            if isLast {
                                breadcrumbSegment(label, isLast: true)
                                    .id(block.id.uuidString)
                            } else {
                                Button {
                                    navigationPath.append(block)
                                } label: {
                                    breadcrumbSegment(label, isLast: false)
                                }
                                .id(block.id.uuidString)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    scrollToEnd(proxy: proxy)
                }
                .onChange(of: ancestors.count) {
                    scrollToEnd(proxy: proxy)
                }
            }
        }
        .frame(height: 20)
        .accessibilityIdentifier("breadcrumb")
    }

    private func scrollToEnd(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(currentNode.id.uuidString, anchor: .trailing)
            }
        }
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
