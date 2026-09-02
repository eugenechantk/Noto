#if os(macOS)
import AppKit
import SwiftUI

/// A sidebar-header action that opens a menu, built as a plain `Button` driving an
/// AppKit `NSMenu` rather than a SwiftUI `Menu`.
///
/// SwiftUI's macOS `Menu` sizes its clickable control from the label's glyph and
/// discards the label's frame, so the sidebar's sort/more targets measured 22×14
/// next to the 36×36 plain buttons beside them — visibly uneven spacing and a much
/// smaller thing to hit. `.menuStyle(.button)` + `.buttonStyle(.plain)` does honor
/// the frame, but then the menu never opens (including via the accessibility press
/// action, so it isn't only an automation artifact). A plain `Button` gets the frame
/// and the press right, and popping `NSMenu` ourselves keeps native menu appearance,
/// keyboard handling, and dismissal.
struct SidebarHeaderMenuButton: View {
    let systemImage: String
    let iconPointSize: CGFloat
    let hitTarget: CGFloat
    let help: String
    let accessibilityID: String
    /// Rebuilt on every press so item state (e.g. the current sort) is never stale.
    let items: () -> [SidebarHeaderMenuItem]

    @State private var anchor = SidebarHeaderMenuAnchorBox()
    @State private var relay = SidebarHeaderMenuRelay()

    var body: some View {
        Button {
            anchor.view?.present(relay.menu(for: items()))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconPointSize, weight: .regular))
                .foregroundStyle(NotoTheme.head)
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .background(
            SidebarHeaderMenuAnchor(box: anchor)
                .allowsHitTesting(false)
        )
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(help)
    }
}

enum SidebarHeaderMenuItem {
    case action(title: String, systemImage: String?, isOn: Bool, handler: () -> Void)
    case separator

    static func action(title: String, systemImage: String? = nil, handler: @escaping () -> Void) -> SidebarHeaderMenuItem {
        .action(title: title, systemImage: systemImage, isOn: false, handler: handler)
    }
}

// MARK: - Anchor

/// The `NSView` the menu pops from, so it lands under the button rather than at the
/// pointer — matching how the native toolbar menus in the editor behave.
private final class SidebarHeaderMenuAnchorView: NSView {
    func present(_ menu: NSMenu) {
        // Unflipped AppKit view: y = 0 is the bottom edge, which is where the menu
        // should hang from.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height : 0), in: self)
    }
}

/// Holds the anchor view across SwiftUI re-renders without forcing a view update.
@Observable
private final class SidebarHeaderMenuAnchorBox {
    @ObservationIgnored weak var view: SidebarHeaderMenuAnchorView?
}

private struct SidebarHeaderMenuAnchor: NSViewRepresentable {
    let box: SidebarHeaderMenuAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = SidebarHeaderMenuAnchorView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView as? SidebarHeaderMenuAnchorView
    }
}

// MARK: - Menu construction

/// Owns the item handlers for as long as the menu is on screen. `NSMenuItem` needs an
/// Objective-C target/action pair, so the closures are kept here and dispatched by tag.
@Observable
private final class SidebarHeaderMenuRelay {
    @ObservationIgnored private var handlers: [() -> Void] = []

    func menu(for items: [SidebarHeaderMenuItem]) -> NSMenu {
        handlers.removeAll()
        let menu = NSMenu()
        let target = Target(relay: self)
        menu.items = items.map { item in
            switch item {
            case .separator:
                return NSMenuItem.separator()
            case let .action(title, systemImage, isOn, handler):
                let menuItem = NSMenuItem(title: title, action: #selector(Target.fire(_:)), keyEquivalent: "")
                menuItem.target = target
                menuItem.tag = handlers.count
                menuItem.state = isOn ? .on : .off
                if let systemImage {
                    menuItem.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                }
                handlers.append(handler)
                return menuItem
            }
        }
        // NSMenuItem holds its target weakly, so the dispatcher has to be owned here
        // or every item would fire into nothing.
        retainedTarget = target
        return menu
    }

    @ObservationIgnored private var retainedTarget: Target?

    fileprivate func fire(tag: Int) {
        guard handlers.indices.contains(tag) else { return }
        handlers[tag]()
    }

    private final class Target: NSObject {
        private let relay: SidebarHeaderMenuRelay

        init(relay: SidebarHeaderMenuRelay) {
            self.relay = relay
        }

        @objc func fire(_ sender: NSMenuItem) {
            relay.fire(tag: sender.tag)
        }
    }
}
#endif
