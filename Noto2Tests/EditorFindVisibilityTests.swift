import Testing
import UIKit
@testable import Noto2

@MainActor
@Suite(.serialized)
struct EditorFindVisibilityTests {
    @Test("Keyboard arrival reveals the initial Find match while its separate field keeps focus")
    func initialMatchRemainsVisibleWhenFindFieldOwnsKeyboard() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.editor.isFindVisible = true
        fixture.editor.updateFind(query: "section 5", navigationRequest: nil) { fixture.status = $0 }
        let expectedFirstRange = try #require(EditorFindMatcher.ranges(in: fixture.markdown, query: "section 5").first)
        // Loading can publish the match count before the query's debounced
        // selection/scroll runs. Require that first selection as the baseline.
        try await eventually {
            fixture.status.matchCount == 3 && fixture.editor.textView.selectedRange == expectedFirstRange
        }
        #expect(fixture.status.selectedMatchIndex == 0)
        let firstSelection = fixture.editor.textView.selectedRange

        try await fixture.focusFindField()
        try fixture.placeSelectionBelowVisibleBoundary()
        fixture.postKeyboardFrame()
        try await eventually { fixture.selectionIsVisibleAboveKeyboard }

        #expect(fixture.field.isFirstResponder)
        #expect(!fixture.editor.textView.isFirstResponder)
        #expect(fixture.editor.textView.selectedRange == firstSelection)
        #expect(fixture.status.selectedMatchIndex == 0)
        #expect(fixture.editor.textView.text == fixture.markdown)

        fixture.editor.updateFind(query: "section 5", navigationRequest: .init(id: 1, direction: .next)) { fixture.status = $0 }
        try await eventually { fixture.status.selectedMatchIndex == 1 && fixture.selectionIsVisibleAboveKeyboard }
        fixture.editor.updateFind(query: "section 5", navigationRequest: .init(id: 2, direction: .previous)) { fixture.status = $0 }
        try await eventually { fixture.status.selectedMatchIndex == 0 && fixture.selectionIsVisibleAboveKeyboard }
        #expect(fixture.editor.textView.selectedRange == firstSelection)
    }

    @Test("An unrelated keyboard does not move an inactive editor with Find closed")
    func closedFindDoesNotStealScrollPosition() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.focusFindField()
        fixture.editor.textView.setContentOffset(CGPoint(x: 0, y: 240), animated: false)
        let before = fixture.editor.textView.contentOffset
        fixture.postKeyboardFrame()
        try await Task.sleep(for: .milliseconds(150))
        #expect(abs(fixture.editor.textView.contentOffset.y - before.y) < 1)
        #expect(fixture.field.isFirstResponder)
    }

    @Test("Find without a match leaves the reading position unchanged on keyboard arrival")
    func emptyFindDoesNotMoveReadingPosition() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.editor.isFindVisible = true
        try await fixture.focusFindField()
        fixture.editor.textView.setContentOffset(CGPoint(x: 0, y: 240), animated: false)
        let before = fixture.editor.textView.contentOffset
        fixture.postKeyboardFrame()
        try await Task.sleep(for: .milliseconds(150))
        #expect(abs(fixture.editor.textView.contentOffset.y - before.y) < 1)
        #expect(fixture.field.isFirstResponder)
        #expect(fixture.status.matchCount == 0)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @MainActor
    private final class Fixture {
        let editor = TextKit2EditorViewController()
        let field = UITextField()
        let window = UIWindow(frame: UIScreen.main.bounds)
        private weak var previousKeyWindow: UIWindow?
        var status = EditorFindStatus()
        let markdown = (0..<90).map { index in
            [30, 48, 65].contains(index) ? "## Section 5\nA matching section.\n" : "Paragraph \(index): enough content to scroll.\n"
        }.joined(separator: "\n")

        init() {
            previousKeyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            window.rootViewController = editor
            window.makeKeyAndVisible()
            editor.loadViewIfNeeded()
            editor.loadText(markdown)
            editor.view.layoutIfNeeded()
            editor.textView.layoutIfNeeded()
            field.frame = CGRect(x: 12, y: 80, width: 240, height: 44)
            field.text = "section 5"
            field.autocorrectionType = .no
            editor.view.addSubview(field)
        }

        func focusFindField() async throws {
            field.becomeFirstResponder()
            #expect(field.isFirstResponder)
            // Allow the real focus transition to finish before the deterministic
            // viewport transition below. No editor first-responder shortcut.
            try await Task.sleep(for: .milliseconds(350))
        }

        func placeSelectionBelowVisibleBoundary() throws {
            editor.textView.layoutIfNeeded()
            let selection = try #require(editor.textView.selectedTextRange)
            let rect = editor.textView.firstRect(for: selection)
            #expect(rect.isFinite)
            // Put the selected text below the current reading boundary even
            // when the simulator starts with no software-keyboard inset.
            editor.textView.setContentOffset(
                CGPoint(x: 0, y: max(0, rect.maxY - editor.textView.bounds.height + editor.textView.adjustedContentInset.bottom - 80)),
                animated: false
            )
            #expect(!selectionIsVisibleAboveKeyboard,
                    "Selected rect: \(rect), bounds: \(editor.textView.bounds), insets: \(editor.textView.adjustedContentInset)")
        }

        func postKeyboardFrame() {
            let screen = window.screen.bounds
            NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: window.screen, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: screen.minX, y: screen.maxY - 320, width: screen.width, height: 320),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.01,
                UIResponder.keyboardAnimationCurveUserInfoKey: UIView.AnimationCurve.linear.rawValue,
            ])
        }

        var selectionIsVisibleAboveKeyboard: Bool {
            guard let selection = editor.textView.selectedTextRange else { return false }
            let rect = editor.textView.firstRect(for: selection)
            let visibleTop = editor.textView.bounds.minY + editor.textView.adjustedContentInset.top
            let visibleBottom = editor.textView.bounds.maxY - editor.textView.adjustedContentInset.bottom
            return rect.isFinite && rect.minY >= visibleTop - 1 && rect.maxY <= visibleBottom + 1
        }

        func close() {
            field.resignFirstResponder()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
    }
}

private extension CGRect {
    var isFinite: Bool { origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite }
}
