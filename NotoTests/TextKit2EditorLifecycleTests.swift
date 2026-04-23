import Testing
@testable import Noto

#if os(iOS)
import UIKit

@Suite("TextKit2 Editor Lifecycle")
struct TextKit2EditorLifecycleTests {

    @Test("Note stack navigation state uses native path entries for selected slices")
    func noteStackNavigationStateUsesNativePathEntriesForSelectedSlices() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/NotoVault")
        let firstDirectoryURL = rootURL
        let secondDirectoryURL = rootURL.appendingPathComponent("Projects")
        let firstNote = MarkdownNote(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            fileURL: firstDirectoryURL.appendingPathComponent("First.md"),
            title: "First",
            modifiedDate: Date(timeIntervalSince1970: 1)
        )
        let secondNote = MarkdownNote(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            fileURL: secondDirectoryURL.appendingPathComponent("Second.md"),
            title: "Second",
            modifiedDate: Date(timeIntervalSince1970: 2)
        )
        let firstEntry = NoteStackEntry(note: firstNote, directoryURL: firstDirectoryURL, vaultRootURL: rootURL, isNew: false)
        let secondEntry = NoteStackEntry(note: secondNote, directoryURL: secondDirectoryURL, vaultRootURL: rootURL, isNew: false)
        var navigation = NoteStackNavigationState()

        navigation.select(firstEntry)
        navigation.select(secondEntry)

        #expect(navigation.root == firstEntry)
        #expect(navigation.path == [secondEntry])

        navigation.path.removeLast()
        let visibleEntry = try #require(navigation.visibleEntry)
        #expect(visibleEntry == firstEntry)
    }

    @Test("Selecting the same note updates the visible stack entry without pushing")
    func selectingSameNoteUpdatesVisibleStackEntryWithoutPushing() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/NotoVault")
        let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let fileURL = rootURL.appendingPathComponent("Draft.md")
        let draft = MarkdownNote(
            id: noteID,
            fileURL: fileURL,
            title: "Draft",
            modifiedDate: Date(timeIntervalSince1970: 1)
        )
        let renamedDraft = MarkdownNote(
            id: noteID,
            fileURL: fileURL,
            title: "Renamed Draft",
            modifiedDate: Date(timeIntervalSince1970: 2)
        )
        let firstEntry = NoteStackEntry(note: draft, directoryURL: rootURL, vaultRootURL: rootURL, isNew: true)
        let updatedEntry = NoteStackEntry(note: renamedDraft, directoryURL: rootURL, vaultRootURL: rootURL, isNew: false)
        var navigation = NoteStackNavigationState()

        navigation.select(firstEntry)
        navigation.select(updatedEntry)

        #expect(navigation.path.isEmpty)
        let visibleEntry = try #require(navigation.visibleEntry)
        #expect(visibleEntry.note.title == "Renamed Draft")
        #expect(!visibleEntry.isNew)
    }

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
        let hyperlinkButton = try #require(accessoryView.descendant(withAccessibilityIdentifier: "toggle_hyperlink_button") as? UIButton)

        #expect(todoButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleTodoForSelectedLines"])
        #expect(todoButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
        #expect(strikethroughButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleSelectedStrikethrough"])
        #expect(strikethroughButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
        #expect(hyperlinkButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleSelectedHyperlink"])
        #expect(hyperlinkButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)

        let keyCommandActions = Set((controller.keyCommands ?? []).compactMap { command in
            command.action.map(NSStringFromSelector)
        })
        #expect(keyCommandActions.contains("toggleSelectedBold"))
        #expect(keyCommandActions.contains("toggleSelectedItalic"))
    }

    @MainActor
    @Test("Todo, inline formatting, and hyperlink actions update editor text")
    func toolbarActionsUpdateText() {
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

        controller.textView.text = "hello world"
        controller.textView.selectedRange = NSRange(location: 6, length: 5)
        let didToggleBold = UIApplication.shared.sendAction(
            NSSelectorFromString("toggleSelectedBold"),
            to: controller,
            from: nil,
            for: nil
        )

        #expect(didToggleBold)
        #expect(controller.textView.text == "hello **world**")

        controller.textView.text = "hello world"
        controller.textView.selectedRange = NSRange(location: 6, length: 5)
        let didToggleItalic = UIApplication.shared.sendAction(
            NSSelectorFromString("toggleSelectedItalic"),
            to: controller,
            from: nil,
            for: nil
        )

        #expect(didToggleItalic)
        #expect(controller.textView.text == "hello *world*")

        controller.textView.text = "https://example.com"
        controller.textView.selectedRange = NSRange(location: 0, length: 19)
        let didToggleHyperlink = UIApplication.shared.sendAction(
            NSSelectorFromString("toggleSelectedHyperlink"),
            to: controller,
            from: nil,
            for: nil
        )

        #expect(didToggleHyperlink)
        #expect(controller.textView.text == "[https://example.com](https://example.com)")
    }

    @MainActor
    @Test("Delete on a revealed hyperlink line edits normally")
    func deleteOnRevealedHyperlinkLineEditsNormally() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("[Example](https://example.com)")
        controller.textView.selectedRange = NSRange(location: 2, length: 1)
        controller.textViewDidChangeSelection(controller.textView)

        let shouldDelete = controller.textView(
            controller.textView,
            shouldChangeTextIn: NSRange(location: 2, length: 1),
            replacementText: ""
        )

        #expect(shouldDelete)
    }

    @MainActor
    @Test("Return at bullet end continues the bullet in the live editor")
    func returnAtBulletEndContinuesBulletInLiveEditor() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("- Parent")

        let shouldInsertDefaultNewline = controller.textView(
            controller.textView,
            shouldChangeTextIn: NSRange(location: 8, length: 0),
            replacementText: "\n"
        )

        #expect(!shouldInsertDefaultNewline)
        #expect(controller.textView.text == "- Parent\n- ")
        #expect(controller.textView.selectedRange == NSRange(location: 11, length: 0))
    }

    @MainActor
    @Test("Cursor on a hyperlink line reveals markdown and leaving the line renders the title")
    func cursorOnHyperlinkLineRevealsMarkdownUntilLeavingLine() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("Readwise: [Open in Reader](https://example.com)\nNext line")
        let bracketLocation = 10

        controller.textView.selectedRange = NSRange(location: 12, length: 0)
        controller.textViewDidChangeSelection(controller.textView)
        let revealedFont = try #require(controller.textView.textStorage.attribute(.font, at: bracketLocation, effectiveRange: nil) as? UIFont)
        let revealedTitleLink = controller.textView.textStorage.attribute(.link, at: 12, effectiveRange: nil)
        #expect(abs(revealedFont.pointSize - MarkdownVisualSpec.bodyFont.pointSize) < 0.5)
        #expect(revealedTitleLink == nil)

        controller.textView.selectedRange = NSRange(location: 50, length: 0)
        controller.textViewDidChangeSelection(controller.textView)
        let hiddenFont = try #require(controller.textView.textStorage.attribute(.font, at: bracketLocation, effectiveRange: nil) as? UIFont)
        let hiddenTitleLink = try #require(controller.textView.textStorage.attribute(.link, at: 12, effectiveRange: nil) as? URL)
        #expect(abs(hiddenFont.pointSize - MarkdownVisualSpec.hyperlinkSyntaxVisualWidth) < 0.5)
        #expect(hiddenTitleLink.absoluteString == "https://example.com")
    }

    @MainActor
    @Test("XML tag collapse caret survives selection changes")
    func xmlTagCollapseCaretSurvivesSelectionChanges() throws {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("<noto:content>\nBody\n</noto:content>")
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let button = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "xml_tag_collapse_0"
        ) as? UIButton)
        #expect(button.frame.width >= 44)
        #expect(button.frame.height >= 32)

        controller.textView.selectedRange = NSRange(location: 16, length: 0)
        controller.textViewDidChangeSelection(controller.textView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let buttonAfterSelection = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "xml_tag_collapse_0"
        ) as? UIButton)
        #expect(buttonAfterSelection === button)
    }

    @MainActor
    @Test("Collapsed XML tag content hides native editor overlays")
    func collapsedXMLTagContentHidesNativeEditorOverlays() throws {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("<noto:content>\n![Field](https://example.com/image.jpg)\n</noto:content>")
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(controller.textView.descendant(withAccessibilityIdentifier: "markdown_image_preview_15") != nil)

        let collapseButton = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "xml_tag_collapse_0"
        ) as? UIButton)
        collapseButton.sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let expandButton = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "xml_tag_collapse_0"
        ) as? UIButton)
        #expect(expandButton.accessibilityLabel == "Expand noto:content")
        #expect(controller.textView.descendant(withAccessibilityIdentifier: "markdown_image_preview_15") == nil)
    }

    @MainActor
    @Test("Expanding XML tag content realigns todo overlays after layout shifts")
    func expandingXMLTagContentRealignsTodoOverlaysAfterLayoutShifts() throws {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()

        let markdown = """
        <noto:highlights>
        > First highlight line wraps into a taller block so the todo section below has to move when this tag expands.
        > Second highlight line keeps the collapsed and expanded layouts materially different.
        > Third highlight line gives TextKit another fragment to recalculate.
        </noto:highlights>

        ## Capture checks

        - [ ] Open this file from the Captures folder.
        - [ ] Confirm the Source and Readwise rows render link titles.
        """
        controller.loadText(markdown)
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let openingButton = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "xml_tag_collapse_0"
        ) as? UIButton)
        openingButton.sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let expandButton = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "xml_tag_collapse_0"
        ) as? UIButton)
        expandButton.sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let nsMarkdown = markdown as NSString
        let todoParagraphLocation = nsMarkdown.range(of: "- [ ] Open this file").location
        let todoButton = try #require(controller.textView.descendant(
            withAccessibilityIdentifier: "todo_checkbox_\(todoParagraphLocation)"
        ) as? UIButton)
        let contentLocation = todoParagraphLocation + "- [ ] ".count
        let contentPosition = try #require(controller.textView.position(
            from: controller.textView.beginningOfDocument,
            offset: contentLocation
        ))
        let caretRect = controller.textView.caretRect(for: contentPosition)

        #expect(abs(todoButton.frame.midY - caretRect.midY) < 1.0)
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

#if os(macOS)
import AppKit

@Suite("TextKit2 Editor Lifecycle")
struct TextKit2EditorLifecycleMacTests {

    @MainActor
    @Test("Text changes restore body typing attributes after a completed empty todo prefix")
    func textChangeRestoresBodyTypingAttributesAfterTodoPrefix() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("- [ ] ")
        controller.textView.setSelectedRange(NSRange(location: 6, length: 0))

        controller.textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: MarkdownVisualSpec.todoPrefixVisualWidth),
            .foregroundColor: NSColor.clear,
        ]

        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.textView))

        let font = try #require(controller.textView.typingAttributes[.font] as? NSFont)
        let foregroundColor = try #require(controller.textView.typingAttributes[.foregroundColor] as? NSColor)

        #expect(abs(font.pointSize - MarkdownVisualSpec.bodyFont.pointSize) < 0.5)
        #expect(foregroundColor == AppTheme.nsPrimaryText)
    }

    @MainActor
    @Test("Return at bullet end continues the bullet in the live editor")
    func returnAtBulletEndContinuesBulletInLiveEditor() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("- Parent")
        controller.textView.setSelectedRange(NSRange(location: 8, length: 0))

        let handled = controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(handled)
        #expect(controller.textView.string == "- Parent\n- ")
        #expect(controller.textView.selectedRange() == NSRange(location: 11, length: 0))
    }

    @MainActor
    @Test("Cursor on a hyperlink line reveals markdown and leaving the line renders the title")
    func cursorOnHyperlinkLineRevealsMarkdownUntilLeavingLine() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("Readwise: [Open in Reader](https://example.com)\nNext line")
        let bracketLocation = 10

        controller.textView.setSelectedRange(NSRange(location: 12, length: 0))
        controller.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: controller.textView))
        let revealedFont = try #require(controller.textView.textStorage?.attribute(.font, at: bracketLocation, effectiveRange: nil) as? NSFont)
        let revealedTitleLink = controller.textView.textStorage?.attribute(.link, at: 12, effectiveRange: nil)
        #expect(abs(revealedFont.pointSize - MarkdownVisualSpec.bodyFont.pointSize) < 0.5)
        #expect(revealedTitleLink == nil)

        controller.textView.setSelectedRange(NSRange(location: 50, length: 0))
        controller.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: controller.textView))
        let hiddenFont = try #require(controller.textView.textStorage?.attribute(.font, at: bracketLocation, effectiveRange: nil) as? NSFont)
        let hiddenTitleLink = try #require(controller.textView.textStorage?.attribute(.link, at: 12, effectiveRange: nil) as? URL)
        #expect(abs(hiddenFont.pointSize - MarkdownVisualSpec.hyperlinkSyntaxVisualWidth) < 0.5)
        #expect(hiddenTitleLink.absoluteString == "https://example.com")
    }
}
#endif
