import NotoLinkPreview

#if os(iOS)
import UIKit

/// The native card that stands in for a bare-URL paragraph on iOS. A `UIControl`,
/// like the todo marker, so taps reach it before the text view's caret placement.
final class LinkPreviewCardView: UIControl {
    var onOpen: (() -> Void)?
    var onEdit: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let hostLabel = UILabel()
    private let iconView = UIImageView()
    private let thumbnailView = UIImageView()
    private let thumbnailDivider = UIView()
    private var content: LinkPreviewCardContent?
    private var layout: LinkPreviewCardLayout?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppTheme.uiCodeBackground
        layer.cornerRadius = LinkPreviewCardLayout.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = AppTheme.uiSeparator.cgColor
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .link

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = NotoTheme.uiInk
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = AppTheme.uiSecondaryText
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        hostLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hostLabel.textColor = AppTheme.uiMutedText
        hostLabel.numberOfLines = 1
        hostLabel.lineBreakMode = .byTruncatingMiddle

        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 3
        iconView.clipsToBounds = true

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = AppTheme.uiSeparator
        thumbnailDivider.backgroundColor = AppTheme.uiSeparator

        for subview in [titleLabel, subtitleLabel, hostLabel, iconView, thumbnailView, thumbnailDivider] {
            subview.isUserInteractionEnabled = false
            addSubview(subview)
        }

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

        titleLabel.text = content.title
        subtitleLabel.text = content.subtitle
        subtitleLabel.isHidden = content.subtitle == nil
        hostLabel.text = content.host
        iconView.image = content.iconData.flatMap(UIImage.init(data:))
        iconView.isHidden = iconView.image == nil
        thumbnailView.image = content.imageData.flatMap(UIImage.init(data:))
        thumbnailView.isHidden = thumbnailView.image == nil
        thumbnailDivider.isHidden = thumbnailView.isHidden
        accessibilityLabel = content.title
        accessibilityValue = content.host
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hasImage = !thumbnailView.isHidden
        let layout = LinkPreviewCardLayout(width: bounds.width, height: bounds.height, hasImage: hasImage)
        self.layout = layout

        if let imageRect = layout.imageRect {
            thumbnailView.frame = imageRect
            thumbnailDivider.frame = CGRect(x: imageRect.minX - 1, y: 0, width: 1, height: bounds.height)
        }

        let column = layout.textRect
        let hostHeight = ceil(hostLabel.font.lineHeight)
        let hostY = column.maxY - hostHeight
        var hostX = column.minX
        if !iconView.isHidden {
            let iconSize = LinkPreviewCardLayout.iconSize
            iconView.frame = CGRect(
                x: column.minX,
                y: hostY + (hostHeight - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            hostX += iconSize + LinkPreviewCardLayout.iconTextGap
        }
        hostLabel.frame = CGRect(x: hostX, y: hostY, width: column.maxX - hostX, height: hostHeight)

        var titleMaxY = hostY - 6
        if !subtitleLabel.isHidden {
            let subtitleHeight = ceil(subtitleLabel.font.lineHeight)
            let subtitleY = hostY - 4 - subtitleHeight
            subtitleLabel.frame = CGRect(x: column.minX, y: subtitleY, width: column.width, height: subtitleHeight)
            titleMaxY = subtitleY - 4
        }

        let titleAvailable = max(0, titleMaxY - column.minY)
        let titleFit = titleLabel.sizeThatFits(CGSize(width: column.width, height: titleAvailable))
        titleLabel.frame = CGRect(
            x: column.minX,
            y: column.minY,
            width: column.width,
            height: min(titleAvailable, ceil(titleFit.height))
        )
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

/// The native card that stands in for a bare-URL paragraph on macOS. Clicking opens
/// the link; the caret stays where it is (arrow keys reveal the raw URL).
final class LinkPreviewCardView: NSView {
    var onOpen: (() -> Void)?

    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let hostLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let thumbnailView = NSImageView()
    private let thumbnailDivider = NSView()
    private var content: LinkPreviewCardContent?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = AppTheme.nsCodeBackground.cgColor
        layer?.cornerRadius = LinkPreviewCardLayout.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = AppTheme.nsSeparator.cgColor
        layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = NotoTheme.nsInk
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = AppTheme.nsSecondaryText
        subtitleLabel.lineBreakMode = .byTruncatingTail

        hostLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hostLabel.textColor = AppTheme.nsMutedText
        hostLabel.lineBreakMode = .byTruncatingMiddle

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 3
        iconView.layer?.masksToBounds = true

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = AppTheme.nsSeparator.cgColor
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.contentsGravity = .resizeAspectFill

        thumbnailDivider.wantsLayer = true
        thumbnailDivider.layer?.backgroundColor = AppTheme.nsSeparator.cgColor

        for subview in [titleLabel, subtitleLabel, hostLabel, iconView, thumbnailView, thumbnailDivider] {
            addSubview(subview)
        }

        setAccessibilityRole(.link)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(content: LinkPreviewCardContent) {
        guard content != self.content else { return }
        self.content = content

        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle ?? ""
        subtitleLabel.isHidden = content.subtitle == nil
        hostLabel.stringValue = content.host
        iconView.image = content.iconData.flatMap(NSImage.init(data:))
        iconView.isHidden = iconView.image == nil
        thumbnailView.image = content.imageData.flatMap(NSImage.init(data:))
        thumbnailView.isHidden = thumbnailView.image == nil
        thumbnailDivider.isHidden = thumbnailView.isHidden
        setAccessibilityLabel(content.title)
        setAccessibilityValue(content.host)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let hasImage = !thumbnailView.isHidden
        let layout = LinkPreviewCardLayout(width: bounds.width, height: bounds.height, hasImage: hasImage)

        if let imageRect = layout.imageRect {
            thumbnailView.frame = imageRect
            thumbnailDivider.frame = NSRect(x: imageRect.minX - 1, y: 0, width: 1, height: bounds.height)
        }

        let column = layout.textRect
        let hostHeight = ceil(hostLabel.intrinsicContentSize.height)
        let hostY = column.maxY - hostHeight
        var hostX = column.minX
        if !iconView.isHidden {
            let iconSize = LinkPreviewCardLayout.iconSize
            iconView.frame = NSRect(
                x: column.minX,
                y: hostY + (hostHeight - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            hostX += iconSize + LinkPreviewCardLayout.iconTextGap
        }
        hostLabel.frame = NSRect(x: hostX, y: hostY, width: max(0, column.maxX - hostX), height: hostHeight)

        var titleMaxY = hostY - 6
        if !subtitleLabel.isHidden {
            let subtitleHeight = ceil(subtitleLabel.intrinsicContentSize.height)
            let subtitleY = hostY - 4 - subtitleHeight
            subtitleLabel.frame = NSRect(x: column.minX, y: subtitleY, width: column.width, height: subtitleHeight)
            titleMaxY = subtitleY - 4
        }

        let titleAvailable = max(0, titleMaxY - column.minY)
        titleLabel.preferredMaxLayoutWidth = column.width
        let titleFit = titleLabel.sizeThatFits(NSSize(width: column.width, height: titleAvailable))
        titleLabel.frame = NSRect(
            x: column.minX,
            y: column.minY,
            width: column.width,
            height: min(titleAvailable, ceil(titleFit.height))
        )
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
