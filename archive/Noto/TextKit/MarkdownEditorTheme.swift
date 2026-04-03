#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum MarkdownEditorTheme {
    #if os(iOS)
    static let bodySize: CGFloat = 17
    private static let heading1Size: CGFloat = 28
    private static let heading2Size: CGFloat = 22
    private static let heading3Size: CGFloat = 18
    #elseif os(macOS)
    static let bodySize: CGFloat = 14
    private static let heading1Size: CGFloat = 24
    private static let heading2Size: CGFloat = 18
    private static let heading3Size: CGFloat = 15
    #endif

    static let bodyFont = PlatformFont.systemFont(ofSize: bodySize, weight: .regular)
    static let bodyColor = PlatformColor.label
    static let indentPerLevel: CGFloat = 12

    private static let cachedBodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 6
        return style
    }()

    static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: bodyColor,
        .paragraphStyle: cachedBodyParagraphStyle
    ]

    static let headingFonts: [Int: PlatformFont] = [
        1: PlatformFont.systemFont(ofSize: heading1Size, weight: .bold),
        2: PlatformFont.systemFont(ofSize: heading2Size, weight: .bold),
        3: PlatformFont.systemFont(ofSize: heading3Size, weight: .semibold)
    ]
}

enum MarkdownTodoCheckboxStyle {
    static let attributeKey = NSAttributedString.Key("com.noto.todoCheckbox")
    static let size: CGFloat = 20
    static let spacing: CGFloat = 6

    static let uncheckedImage: PlatformImage = {
        let size = CGSize(width: Self.size, height: Self.size)
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            PlatformColor.systemGray2.setStroke()
            let path = UIBezierPath(ovalIn: rect)
            path.lineWidth = 2
            path.stroke()
        }
        #elseif os(macOS)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.5, dy: 1.5)
            PlatformColor.systemGray.setStroke()
            let path = NSBezierPath(ovalIn: inset)
            path.lineWidth = 2
            path.stroke()
            return true
        }
        return image
        #endif
    }()

    static let checkedImage: PlatformImage = {
        let size = CGSize(width: Self.size, height: Self.size)
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            PlatformColor.systemGreen.setFill()
            UIBezierPath(ovalIn: rect).fill()

            let check = UIBezierPath()
            check.move(to: CGPoint(x: size.width * 0.27, y: size.height * 0.50))
            check.addLine(to: CGPoint(x: size.width * 0.43, y: size.height * 0.67))
            check.addLine(to: CGPoint(x: size.width * 0.73, y: size.height * 0.33))
            check.lineWidth = 2.5
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            PlatformColor.white.setStroke()
            check.stroke()
        }
        #elseif os(macOS)
        let image = NSImage(size: size, flipped: false) { rect in
            PlatformColor.systemGreen.setFill()
            NSBezierPath(ovalIn: rect).fill()

            let check = NSBezierPath()
            check.move(to: NSPoint(x: size.width * 0.27, y: size.height * 0.50))
            check.line(to: NSPoint(x: size.width * 0.43, y: size.height * 0.33))
            check.line(to: NSPoint(x: size.width * 0.73, y: size.height * 0.67))
            check.lineWidth = 2.5
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            PlatformColor.white.setStroke()
            check.stroke()
            return true
        }
        return image
        #endif
    }()
}
