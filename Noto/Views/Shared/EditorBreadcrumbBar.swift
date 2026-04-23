import Foundation
import SwiftUI

struct EditorBreadcrumbBar: View {
    let vaultRootURL: URL
    let noteFileURL: URL
    var onTapLevel: ((URL) -> Void)? = nil

    private static let levelMaxWidth: CGFloat = 160

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    levelLabel(level, isCurrent: index == levels.count - 1)
                }
            }
            .padding(.horizontal, 12)
        }
        .defaultScrollAnchor(.trailing)
        .frame(maxWidth: 360)
        .accessibilityIdentifier("breadcrumb_bar")
    }

    @ViewBuilder
    private func levelLabel(_ level: Level, isCurrent: Bool) -> some View {
        let text = Text(level.name)
            .font(.subheadline.weight(isCurrent ? .semibold : .medium))
            .foregroundStyle(isCurrent ? AnyShapeStyle(AppTheme.primaryText) : AnyShapeStyle(AppTheme.mutedText))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.levelMaxWidth, alignment: .leading)

        if let onTapLevel {
            Button {
                onTapLevel(level.url)
            } label: {
                text
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent ? "\(level.name), current note location" : level.name)
        } else {
            text
        }
    }

    private struct Level {
        let name: String
        let url: URL
    }

    private var levels: [Level] {
        let noteParent = noteFileURL.deletingLastPathComponent().standardizedFileURL
        let root = vaultRootURL.standardizedFileURL
        let rootName = root.lastPathComponent.isEmpty ? "Vault" : root.lastPathComponent

        let rootComponents = root.pathComponents
        let parentComponents = noteParent.pathComponents
        guard parentComponents.count >= rootComponents.count,
              Array(parentComponents.prefix(rootComponents.count)) == rootComponents else {
            return [Level(name: rootName, url: root)]
        }

        var result = [Level(name: rootName, url: root)]
        var currentURL = root
        for component in parentComponents.dropFirst(rootComponents.count) {
            currentURL = currentURL.appendingPathComponent(component)
            result.append(Level(name: component, url: currentURL))
        }
        return result
    }
}
