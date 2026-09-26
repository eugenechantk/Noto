import NotoLinkPreview
import SwiftUI

extension LinkPreviewCardStyle {
    /// Noto's theme for the shared preview card.
    static var noto: LinkPreviewCardStyle {
        #if os(iOS)
        LinkPreviewCardStyle(
            background: Color(uiColor: AppTheme.uiCodeBackground),
            border: Color(uiColor: AppTheme.uiSeparator),
            title: Color(uiColor: NotoTheme.uiInk),
            summary: Color(uiColor: AppTheme.uiSecondaryText),
            host: Color(uiColor: AppTheme.uiMutedText),
            placeholder: Color(uiColor: AppTheme.uiSeparator)
        )
        #else
        LinkPreviewCardStyle(
            background: Color(nsColor: AppTheme.nsCodeBackground),
            border: Color(nsColor: AppTheme.nsSeparator),
            title: Color(nsColor: NotoTheme.nsInk),
            summary: Color(nsColor: AppTheme.nsSecondaryText),
            host: Color(nsColor: AppTheme.nsMutedText),
            placeholder: Color(nsColor: AppTheme.nsSeparator)
        )
        #endif
    }
}

#if os(iOS)
import UIKit

/// The native control that stands in for a bare-URL paragraph on iOS. It hosts the
/// shared SwiftUI `LinkPreviewCard` for drawing and stays a `UIControl`, like the
/// todo marker, so taps reach it before the text view's caret placement.
final class LinkPreviewCardView: UIControl {
    var onOpen: (() -> Void)?
    var onEdit: (() -> Void)?

    private var content: LinkPreviewCardContent?
    private let host = UIHostingController(rootView: AnyView(EmptyView()))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .link

        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(host.view)

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        addGestureRecognizer(longPress)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    func configure(content: LinkPreviewCardContent) {
        guard content != self.content else { return }
        self.content = content
        host.rootView = AnyView(LinkPreviewCard(content: content, style: .noto))
        accessibilityLabel = content.title
        accessibilityValue = [content.subtitle, content.host].compactMap { $0 }.joined(separator: ", ")
    }

    @objc
    private func handleTap() {
        onOpen?()
    }

    @objc
    private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onEdit?()
    }
}

#elseif os(macOS)
import AppKit

/// The native card that stands in for a bare-URL paragraph on macOS, hosting the
/// shared SwiftUI `LinkPreviewCard`. Clicking opens the link; the caret stays
/// where it is (arrow keys reveal the raw URL).
final class LinkPreviewCardView: NSView {
    var onOpen: (() -> Void)?

    private var content: LinkPreviewCardContent?
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        setAccessibilityRole(.link)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(content: LinkPreviewCardContent) {
        guard content != self.content else { return }
        self.content = content
        host.rootView = AnyView(LinkPreviewCard(content: content, style: .noto))
        setAccessibilityLabel(content.title)
        setAccessibilityValue(content.host)
    }

    /// The hosted SwiftUI view must not take clicks; this view handles them.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        // Swallow the press so the text view underneath does not move the caret.
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onOpen?()
    }
}
#endif
