import Testing
@testable import Noto

#if os(iOS)
import UIKit

@Suite("TextKit2 Editor Lifecycle")
struct TextKit2EditorLifecycleTests {

    @MainActor
    @Test("Loading text before the view exists is deferred until the text view is created")
    func loadTextBeforeViewLoadsIsDeferred() {
        let controller = TextKit2EditorViewController()

        controller.loadText("# Title\nBody")
        controller.loadViewIfNeeded()

        #expect(controller.textView.text == "# Title\nBody")
    }

    @MainActor
    @Test("Editor action transforms participate in native undo and redo")
    func editorActionTransformsRegisterUndoAndRedo() {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("- Item")
        controller.textView.selectedRange = NSRange(location: 0, length: 0)
        controller.textView.becomeFirstResponder()

        let didSendAction = UIApplication.shared.sendAction(
            NSSelectorFromString("indentSelectedLines"),
            to: controller,
            from: nil,
            for: nil
        )

        #expect(didSendAction)
        #expect(controller.textView.text == "  - Item")

        controller.textView.undoManager?.undo()
        #expect(controller.textView.text == "- Item")

        controller.textView.undoManager?.redo()
        #expect(controller.textView.text == "  - Item")
    }

    @Test("Frontmatter range covers the YAML metadata block only")
    func detectsFrontmatterRange() throws {
        let markdown = """
        ---
        id: abc
        updated: 2026-04-04
        ---
        # Title
        Body
        """

        let range = try #require(MarkdownFrontmatter.range(in: markdown))
        let nsMarkdown = markdown as NSString

        #expect(nsMarkdown.substring(with: range) == """
        ---
        id: abc
        updated: 2026-04-04
        ---
        """)
        #expect(MarkdownFrontmatter.contains(position: 0, in: markdown))
        #expect(!MarkdownFrontmatter.contains(position: range.location + range.length + 1, in: markdown))
    }
}
#endif
