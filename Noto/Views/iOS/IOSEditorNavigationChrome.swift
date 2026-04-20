#if os(iOS)
import SwiftUI
import NotoVault

struct EditorNavigationChrome: ViewModifier {
    let mode: EditorChromeMode
    let vaultRootURL: URL
    let noteFileURL: URL
    let statusCount: WordCounter.Count
    var onTapBreadcrumbLevel: ((URL) -> Void)?
    var onOpenTodayNote: (() -> Void)?
    var onCreateRootNote: (() -> Void)?
    var onDeleteRequested: () -> Void
    var onDismiss: () -> Void

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if case .compactNavigation(let showsInlineBackButton) = mode {
                    if showsInlineBackButton {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: onDismiss) {
                                Image(systemName: "chevron.left")
                            }
                            .accessibilityIdentifier("back_button")
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        BreadcrumbBar(
                            vaultRootURL: vaultRootURL,
                            noteFileURL: noteFileURL,
                            onTapLevel: onTapBreadcrumbLevel
                        )
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive, action: onDeleteRequested) {
                                Label("Delete Note", systemImage: "trash")
                            }
                            Divider()
                            Text("\(formatted(statusCount.words)) words")
                                .accessibilityIdentifier("editor_word_count_menu_item")
                            Text("\(formatted(statusCount.characters)) characters")
                                .accessibilityIdentifier("editor_character_count_menu_item")
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityIdentifier("more_menu_button")
                    }
                }
            }
            .notoAppBottomToolbar(
                onOpenTodayNote: bottomToolbarAction(onOpenTodayNote),
                onCreateRootNote: bottomToolbarAction(onCreateRootNote)
            )
    }

    private func bottomToolbarAction(_ action: (() -> Void)?) -> (() -> Void)? {
        guard case .compactNavigation = mode else { return nil }
        return action
    }

    private func formatted(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Horizontally scrollable breadcrumb showing the folder chain from vault root
/// down to the note's parent directory. Replaces the navigation title.
private struct BreadcrumbBar: View {
    let vaultRootURL: URL
    let noteFileURL: URL
    var onTapLevel: ((URL) -> Void)? = nil

    @State private var isOverflowing = false

    private static let levelMaxWidth: CGFloat = 140

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    levelLabel(level, isCurrent: index == levels.count - 1)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 24)
        }
        .defaultScrollAnchor(.trailing)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.width > geometry.containerSize.width
        } action: { _, newValue in
            isOverflowing = newValue
        }
        .mask(maskGradient)
        .accessibilityIdentifier("breadcrumb_bar")
    }

    private var maskGradient: LinearGradient {
        let stops: [Gradient.Stop] = isOverflowing
            ? [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ]
            : [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 1)
            ]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder
    private func levelLabel(_ level: Level, isCurrent: Bool) -> some View {
        let text = Text(level.name)
            .font(.subheadline.weight(isCurrent ? .semibold : .medium))
            .foregroundStyle(isCurrent ? AnyShapeStyle(AppTheme.primaryText) : AnyShapeStyle(AppTheme.mutedText))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.levelMaxWidth, alignment: .leading)

        if onTapLevel == nil {
            text
        } else {
            Button {
                onTapLevel?(level.url)
            } label: {
                text
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent ? "\(level.name), current note location" : level.name)
        }
    }

    private struct Level {
        let name: String
        let url: URL
    }

    /// Folder chain from vault root to the note's parent directory.
    /// Excludes the note's filename. Falls back to a single "Vault" level for notes at the root.
    private var levels: [Level] {
        let noteParent = noteFileURL.deletingLastPathComponent().standardizedFileURL
        let root = vaultRootURL.standardizedFileURL
        let rootName = root.lastPathComponent.isEmpty ? "Vault" : root.lastPathComponent

        let rootComps = root.pathComponents
        let parentComps = noteParent.pathComponents
        guard parentComps.count >= rootComps.count,
              Array(parentComps.prefix(rootComps.count)) == rootComps else {
            return [Level(name: rootName, url: root)]
        }
        let relative = Array(parentComps.dropFirst(rootComps.count))
        var result: [Level] = [Level(name: rootName, url: root)]
        var currentURL = root
        for component in relative {
            currentURL = currentURL.appendingPathComponent(component)
            result.append(Level(name: component, url: currentURL))
        }
        return result
    }
}
#endif
