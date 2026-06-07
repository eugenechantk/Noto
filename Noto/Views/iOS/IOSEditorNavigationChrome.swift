#if os(iOS)
import SwiftUI
import NotoVault

struct EditorNavigationChrome: ViewModifier {
    let mode: EditorChromeMode
    let vaultRootURL: URL
    let noteFileURL: URL
    let statusCount: WordCounter.Count
    var leadingControls: EditorLeadingChromeControls = .none
    var onTapBreadcrumbLevel: ((URL) -> Void)?
    var onOpenTodayNote: (() -> Void)?
    var onCreateRootNote: (() -> Void)?
    var onMoveRequested: () -> Void
    var onDeleteRequested: () -> Void
    var onSearchRequested: () -> Void
    var onShowProperties: (() -> Void)?
    var propertyCount: Int = 0
    var showsScrolledTitle = false
    var scrolledTitle = ""
    var canNavigateBack = false
    var canNavigateForward = false
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?
    var onDismiss: () -> Void

    // iPad design: the detail toolbar trailing group is `search + more` (two buttons).
    // The iPhone minimal editor is `back · more` only (search lives in the ••• menu),
    // so the standalone search button is gated to regular width.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var showsTrailingSearchButton: Bool {
        horizontalSizeClass == .regular
    }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Compact: hide the system back button and provide bare custom buttons (no
            // Liquid Glass), but KEEP the system nav bar so its scroll-edge background +
            // principal title animations are preserved. The interactive swipe-back is
            // re-enabled by InteractivePopGestureEnabler since the system back is hidden.
            .navigationBarBackButtonHidden(isCompactNavigation ? true : hidesSystemBackButton)
            .toolbar {
                if case .compactNavigation = mode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 2) {
                            if let onToggleSidebar = leadingControls.onToggleSidebar,
                               let sidebarSystemImage = leadingControls.sidebarSystemImage {
                                Button {
                                    onToggleSidebar()
                                } label: {
                                    Image(systemName: sidebarSystemImage)
                                        .font(.system(size: 18, weight: .regular))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("sidebar_toggle_button")
                                .accessibilityLabel(leadingControls.sidebarAccessibilityLabel ?? "Toggle Sidebar")
                            }

                            Button {
                                onDismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("back_button")
                            .accessibilityLabel("Back")
                        }
                        .foregroundStyle(NotoTheme.head)
                    }
                    .plainToolbarBackground()

                    // v2 redesign: the minimal editor top bar is empty until the note
                    // scrolls; then the note title rises into the center (scrolled state).
                    ToolbarItem(placement: .principal) {
                        if showsScrolledTitle {
                            Text(scrolledTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NotoTheme.head)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 240)
                                .transition(.opacity)
                                .accessibilityIdentifier("editor_scrolled_title")
                        }
                    }

                    // v2 design: bare TRAILING group. iPad = `search + more` (two
                    // buttons); iPhone = `more` only (search is in the ••• menu).
                    // Note-history chevrons are omitted so back always pops to the file view.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 2) {
                            if showsTrailingSearchButton {
                                Button(action: onSearchRequested) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 18, weight: .regular))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("editor_search_button")
                                .accessibilityLabel("Search in Note")
                            }
                            moreMenu
                                .buttonStyle(.plain)
                        }
                        .foregroundStyle(NotoTheme.head)
                    }
                    .plainToolbarBackground()
                }
            }
            .background(compactPopEnabler)
    }

    private var isCompactNavigation: Bool {
        if case .compactNavigation = mode { return true }
        return false
    }

    @ViewBuilder
    private var compactPopEnabler: some View {
        if isCompactNavigation {
            InteractivePopGestureEnabler()
        } else {
            Color.clear
        }
    }

    private var moreMenu: some View {
        Menu {
            // Search + Properties share the top section; Search sits above Properties.
            Button(action: onSearchRequested) {
                Label("Search in Note", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .accessibilityIdentifier("search_in_note_menu_item")

            if let onShowProperties {
                Button(action: onShowProperties) {
                    // Two Text views in a menu button render as title + subtitle.
                    Text("Properties")
                    Text("\(propertyCount) \(propertyCount == 1 ? "property" : "properties")")
                    Image(systemName: "info.circle")
                }
                .accessibilityIdentifier("properties_menu_item")
            }

            Divider()

            Button(action: onMoveRequested) {
                Label("Move Note", systemImage: "folder")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .accessibilityIdentifier("move_note_menu_item")

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
                .font(.system(size: 18, weight: .regular))
        }
        .accessibilityIdentifier("more_menu_button")
    }

    private var hidesSystemBackButton: Bool {
        if case .compactNavigation(let showsInlineBackButton) = mode {
            return !showsInlineBackButton
        }
        return true
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

private extension ToolbarContent {
    /// Removes the iOS 26 shared Liquid Glass container background from a toolbar item,
    /// leaving a bare icon. No-op on earlier OSes.
    @ToolbarContentBuilder
    func plainToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
#endif
