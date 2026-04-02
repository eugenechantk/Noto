#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    private let formatter = MarkdownFormatter()
    private(set) var activeLine: NSRange?
    private(set) var cursorPosition: Int?

    // MARK: - NSTextStorage required overrides

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        super.processEditing()
    }

    // MARK: - Platform-specific font sizes

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

    // MARK: - Body style (all static, allocated once)

    static let bodyFont = PlatformFont.systemFont(ofSize: bodySize, weight: .regular)
    static let bodyColor = PlatformColor.label

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
    static let indentPerLevel: CGFloat = 12

    // MARK: - Todo checkboxes

    /// Custom attribute key used to identify checkbox glyphs for rendering and tapping.
    static let todoCheckboxKey = NSAttributedString.Key("com.noto.todoCheckbox")

    /// Size of the rendered checkbox circle.
    static let checkboxSize: CGFloat = 20
    static let checkboxSpacing: CGFloat = 6

    /// Cached unchecked circle image (empty outline).
    static let uncheckedCircleImage: PlatformImage = {
        let size = CGSize(width: checkboxSize, height: checkboxSize)
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

    /// Cached checked circle image (green fill, white checkmark).
    static let checkedCircleImage: PlatformImage = {
        let size = CGSize(width: checkboxSize, height: checkboxSize)
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

    // MARK: - Load / Export

    func load(markdown: String) {
        let fullRange = NSRange(location: 0, length: backing.length)
        replaceCharacters(in: fullRange, with: markdown)
        render(activeLine: activeLine, cursorPosition: cursorPosition)
    }

    func render(activeLine: NSRange?, cursorPosition: Int? = nil) {
        self.activeLine = activeLine
        self.cursorPosition = cursorPosition
        let formatted = formatter.makeAttributedString(
            markdown: backing.string,
            activeLine: activeLine,
            cursorPosition: cursorPosition
        )
        let fullRange = NSRange(location: 0, length: backing.length)
        guard fullRange.length > 0 else { return }

        beginEditing()
        formatted.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            backing.setAttributes(attrs, range: range)
        }
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        endEditing()
    }

    func setActiveLine(_ range: NSRange?, cursorPosition: Int? = nil) {
        let cursorChanged = self.cursorPosition != cursorPosition
        guard activeLine != range || cursorChanged else { return }
        render(activeLine: range, cursorPosition: cursorPosition)
    }

    func markdownContent() -> String {
        backing.string
    }
}
