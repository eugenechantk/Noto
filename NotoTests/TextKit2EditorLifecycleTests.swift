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
        let hideKeyboardButton = try #require(accessoryView.descendant(withAccessibilityIdentifier: "hide_keyboard_button") as? UIButton)

        #expect(todoButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleTodoForSelectedLines"])
        #expect(todoButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
        #expect(strikethroughButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleSelectedStrikethrough"])
        #expect(strikethroughButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
        #expect(hyperlinkButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["toggleSelectedHyperlink"])
        #expect(hyperlinkButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)
        #expect(hideKeyboardButton.actions(forTarget: controller, forControlEvent: .touchUpInside) == ["hideSoftwareKeyboard"])
        #expect(hideKeyboardButton.actions(forTarget: controller, forControlEvent: .primaryActionTriggered) == nil)

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
    @Test("XML tags stay expanded and do not render collapse carets")
    func xmlTagsStayExpandedAndDoNotRenderCollapseCarets() {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("<noto:content>\nBody\n</noto:content>")
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(controller.textView.descendant(withAccessibilityIdentifier: "xml_tag_collapse_0") == nil)
        #expect(controller.textView.text.contains("Body"))
    }

    @MainActor
    @Test("Image paragraphs render without overlay preview views inside expanded XML tags")
    func imageParagraphsRenderWithoutOverlayPreviewViewsInsideExpandedXMLTags() {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("<noto:content>\n![Field](https://example.com/image.jpg)\n</noto:content>")
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(controller.textView.descendant(withAccessibilityIdentifier: "xml_tag_collapse_0") == nil)
        #expect(controller.textView.descendant(withAccessibilityIdentifier: "markdown_image_preview_15") == nil)
    }

    @MainActor
    @Test("Expanded XML content keeps todo fragment hit regions aligned")
    func expandedXMLContentKeepsTodoFragmentHitRegionsAligned() throws {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.textView.becomeFirstResponder()

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
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let nsMarkdown = markdown as NSString
        let todoParagraphLocation = nsMarkdown.range(of: "- [ ] Open this file").location
        let checkbox = controller.textView.descendant(withAccessibilityIdentifier: "todo_checkbox_\(todoParagraphLocation)")
        #expect(checkbox != nil)

        let markerRect = try #require(controller.todoMarkerHitRect(forParagraphLocation: todoParagraphLocation))
        let contentLocation = todoParagraphLocation + "- [ ] ".count
        let contentPosition = try #require(controller.textView.position(
            from: controller.textView.beginningOfDocument,
            offset: contentLocation
        ))
        let caretRect = controller.textView.caretRect(for: contentPosition)

        #expect(abs(markerRect.midY - caretRect.midY) < 1.0)
        #expect(controller.toggleTodoMarker(atTextViewPoint: CGPoint(x: markerRect.midX, y: markerRect.midY)))
        #expect(controller.textView.text.contains("- [x] Open this file"))

        controller.textView.undoManager?.undo()
        #expect(controller.textView.text.contains("- [ ] Open this file"))

        controller.textView.undoManager?.redo()
        #expect(controller.textView.text.contains("- [x] Open this file"))
    }

    @MainActor
    @Test("Empty todo marker stays horizontally aligned after typing the first character")
    func emptyTodoMarkerStaysAlignedAfterTypingFirstCharacter() throws {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.textView.becomeFirstResponder()

        controller.loadText("- [ ] ")
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let emptyMarkerRect = try #require(controller.todoMarkerHitRect(forParagraphLocation: 0))

        controller.loadText("- [ ] Task")
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let populatedMarkerRect = try #require(controller.todoMarkerHitRect(forParagraphLocation: 0))

        #expect(abs(emptyMarkerRect.minX - populatedMarkerRect.minX) < 1.0)
    }

    @MainActor
    @Test("Page mention suggestion rows keep horizontal inset inside the iOS popover")
    func pageMentionSuggestionRowsKeepHorizontalInsetInsidePopover() throws {
        let controller = TextKit2EditorViewController()
        controller.pageMentionProvider = { query in
            guard query == "27" else { return [] }
            return [
                PageMentionDocument(
                    id: UUID(),
                    title: "2026-03-27",
                    relativePath: "Daily Notes/2026-03-27.md",
                    fileURL: URL(fileURLWithPath: "/tmp/NotoVault/Daily Notes/2026-03-27.md")
                )
            ]
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("@27")
        controller.textView.selectedRange = NSRange(location: controller.textView.text.count, length: 0)
        controller.textView.becomeFirstResponder()

        controller.textViewDidChange(controller.textView)
        controller.textViewDidChangeSelection(controller.textView)
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let stackView = try #require(controller.view.descendant(withAccessibilityIdentifier: "page_mention_suggestions") as? UIStackView)
        let button = try #require(controller.view.descendant(withAccessibilityIdentifier: "page_mention_suggestion_0") as? UIButton)
        let buttonFrameInStack = stackView.convert(button.bounds, from: button)

        #expect(buttonFrameInStack.minX >= stackView.layoutMargins.left + 9)
        #expect(buttonFrameInStack.maxX <= stackView.bounds.width - stackView.layoutMargins.right - 9)
    }

    @Test("Readable width layout centers iPad text around a 600 point column")
    func readableWidthLayoutCentersIPadText() {
        let textInset = ReadableTextColumnLayout.textHorizontalInset(
            for: 1024,
            maximumTextWidth: 600,
            minimumHorizontalInset: 16,
            constrainsToReadableWidth: true
        )

        #expect(textInset == 212)
    }

    @Test("Readable width layout keeps narrow and unconstrained editors edge aligned")
    func readableWidthLayoutKeepsNarrowAndUnconstrainedEditorsEdgeAligned() {
        let narrowInset = ReadableTextColumnLayout.textHorizontalInset(
            for: 550,
            maximumTextWidth: 600,
            minimumHorizontalInset: 16,
            constrainsToReadableWidth: true
        )
        let phoneInset = ReadableTextColumnLayout.textHorizontalInset(
            for: 1024,
            maximumTextWidth: 600,
            minimumHorizontalInset: 16,
            constrainsToReadableWidth: false
        )

        #expect(narrowInset == 16)
        #expect(phoneInset == 16)
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
    @Test("Find query does not move editor selection or mutate backing attributes")
    func findQueryDoesNotMoveEditorSelectionOrMutateBackingAttributes() throws {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("# Shopping List\n- Fruits")
        controller.textView.setSelectedRange(NSRange(location: controller.textView.string.count, length: 0))
        let attributesBeforeFind = try #require(controller.textView.textStorage?.attributes(at: 0, effectiveRange: nil))

        controller.updateFind(query: "Shop", navigationRequest: nil, onStatusChange: nil)

        #expect(controller.textView.selectedRange() == NSRange(location: controller.textView.string.count, length: 0))
        #expect(controller.textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        let attributesAfterFind = try #require(controller.textView.textStorage?.attributes(at: 0, effectiveRange: nil))
        #expect(NSDictionary(dictionary: attributesAfterFind).isEqual(to: attributesBeforeFind))
    }

    @MainActor
    @Test("Escape closes visible find while editor is focused")
    func escapeClosesVisibleFindWhileEditorIsFocused() {
        let controller = TextKit2EditorViewController()
        controller.loadViewIfNeeded()
        controller.loadText("Find me")
        controller.isFindVisible = true

        var didCloseFind = false
        controller.onCloseFind = {
            didCloseFind = true
        }

        let handled = controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        )

        #expect(handled)
        #expect(didCloseFind)
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

    @MainActor
    @Test("Page mention suggestion rows keep symmetric outer inset inside the macOS popover")
    func pageMentionSuggestionRowsKeepSymmetricOuterInsetInsidePopover() throws {
        let controller = TextKit2EditorViewController()
        controller.pageMentionProvider = { query in
            guard query == "孤独" else { return [] }
            return [
                PageMentionDocument(
                    id: UUID(),
                    title: "你的孤独，正撑起一个万亿新赛道",
                    relativePath: "Captures/你的孤独，正撑起一个万亿新赛道.md",
                    fileURL: URL(fileURLWithPath: "/tmp/NotoVault/Captures/你的孤独，正撑起一个万亿新赛道.md")
                )
            ]
        }
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        controller.loadText("and @孤独")
        controller.textView.setSelectedRange(NSRange(location: controller.textView.string.count, length: 0))

        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.textView))
        controller.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: controller.textView))
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let stackView = try #require(controller.view.descendant(withAccessibilityIdentifier: "page_mention_suggestions") as? NSStackView)
        let button = try #require(controller.view.descendant(withAccessibilityIdentifier: "page_mention_suggestion_0") as? NSButton)
        controller.view.layoutSubtreeIfNeeded()

        let rowBackground = try #require(button.superview)
        let rowFrameInStack = stackView.convert(rowBackground.bounds, from: rowBackground)
        #expect(abs(rowFrameInStack.minX - stackView.edgeInsets.left) < 1.0)
        #expect(abs(rowFrameInStack.maxX - (stackView.bounds.width - stackView.edgeInsets.right)) < 1.0)
    }
}

private extension NSView {
    func descendant(withAccessibilityIdentifier identifier: String) -> NSView? {
        if accessibilityIdentifier() == identifier {
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
