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

    @MainActor
    @Test("Toolbar buttons register only the touch-up action so toggles fire once")
    func toolbarButtonsRegisterSingleTouchAction() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()

        let accessoryView = try #require(controller.textView.inputAccessoryView)
        let todoButton = try #require(accessoryView.descendant(withAccessibilityIdentifier: "toggle_todo_button") as? UIButton)
        let strikethroughButton = try #require(accessoryView.descendant(withAccessibilityIdentifier: "toggle_strikethrough_button") as? UIButton)

        #expect(todoButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleTodoForSelectedLines"])
        #expect(todoButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
        #expect(strikethroughButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleSelectedStrikethrough"])
        #expect(strikethroughButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
    }

    @MainActor
    @Test("Todo and strikethrough toolbar actions update editor text")
    func todoAndStrikethroughToolbarActionsUpdateText() {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("hello world")
        controller.textView.becomeFirstResponder()

        controller.textView.selectedRange = NSRange(location: 5, length: 0)
        let didToggleTodo = UIApplication.shared.sendAction(
            NSSelectorFromString("toggleTodoForSelectedLines"),
            to: controller,
            from: nil,
            for: nil
        )

        #expect(didToggleTodo)
        #expect(controller.textView.text == "- [ ] hello world")

        controller.textView.selectedRange = NSRange(location: 6, length: 5)
        let didToggleStrikethrough = UIApplication.shared.sendAction(
            NSSelectorFromString("toggleSelectedStrikethrough"),
            to: controller,
            from: nil,
            for: nil
        )

        #expect(didToggleStrikethrough)
        #expect(controller.textView.text == "- [ ] ~~hello~~ world")
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

private extension UIView {
    func descendant(withAccessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.descendant(withAccessibilityIdentifier: identifier) {
                return match
            }
        }
        return nil
    }
}
#endif
