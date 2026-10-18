import SwiftUI
import Testing
import UIKit
@testable import Noto2

@MainActor
@Suite(.serialized)
struct FilingKeyboardLayoutTests {
    @Test func hiddenKeyboardUsesBottomSafeAreaAndIntrinsicBarHeight() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = FilingKeyboardLayoutController(content: AnyView(Color.clear), bottomBar: AnyView(Text("Search").padding(12)))
        controller.additionalSafeAreaInsets.bottom = 17
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }

        try await waitUntil { controller.bottomBarView.bounds.height > 0 }
        controller.view.layoutIfNeeded()
        let bottom = controller.bottomBarView.frame.maxY
        #expect(abs(bottom - controller.view.safeAreaLayoutGuide.layoutFrame.maxY) < 1)
        let initialHeight = controller.bottomBarView.bounds.height

        controller.update(content: AnyView(Color.clear), bottomBar: AnyView(Text("Search\nAnother line").padding(24)))
        try await waitUntil { controller.bottomBarView.bounds.height > initialHeight + 20 }
        #expect(abs(controller.bottomBarView.frame.maxY - bottom) < 1)
    }

    @Test func addSearchStaysAboveKeyboardAfterDismissingFloatingEditor() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("FilingKeyboard-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer {
            window.endEditing(true)
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: vault)
        }
        let keyboard = KeyboardFrameProbe(screen: window.screen)

        // Use the real shared editor/accessory. Dismiss it while it is still
        // first responder, as Create does in New note's optional edit surface.
        for iteration in 0..<2 {
            let editor = TextKit2EditorViewController()
            editor.keyboardToolbarStyle = .floating
            editor.loadText("Capture to file")
            await present(editor, from: root)
            #expect(editor.textView.becomeFirstResponder())
            try await waitUntil(diagnostics: {
                "Editor keyboard: frame=\(String(describing: keyboard.frame)); firstResponder=\(editor.textView.isFirstResponder); window=\(window.bounds); key=\(window.isKeyWindow)"
            }) { keyboard.frame.map { $0.minY < window.bounds.maxY - 100 } ?? false }
            #expect(editor.textView.inputAccessoryView?.intrinsicContentSize.height == 60)
            await dismiss(editor)

            let sheet = UIHostingController(rootView: AddToNoteSheet(vaultURL: vault, draft: "Capture to file", onPick: { _ in }))
            sheet.modalPresentationStyle = .pageSheet
            sheet.sheetPresentationController?.detents = [.large()]
            await present(sheet, from: root)
            try await waitUntil(diagnostics: {
                guard let layout = descendant(FilingKeyboardLayoutController.self, in: sheet) else { return "Add layout controller missing" }
                let field = descendant(UITextField.self, in: layout.bottomBarView)
                return "Add keyboard: frame=\(String(describing: keyboard.frame)); guide=\(layout.view.keyboardLayoutGuide.layoutFrame); guideInWindow=\(layout.view.convert(layout.view.keyboardLayoutGuide.layoutFrame, to: window)); barInWindow=\(layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window)); layout=\(layout.view.bounds); safeArea=\(layout.view.safeAreaInsets); field=\(String(describing: field?.frame)); firstResponder=\(field?.isFirstResponder == true); key=\(window.isKeyWindow)"
            }) {
                guard let layout = descendant(FilingKeyboardLayoutController.self, in: sheet),
                      let keyboardFrame = keyboard.frame else { return false }
                let barBottom = layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window).maxY
                let keyboardTop = window.convert(keyboardFrame, from: window.screen.coordinateSpace).minY
                return descendant(UITextField.self, in: layout.bottomBarView)?.isFirstResponder == true
                    && keyboardFrame.height > 100
                    && abs(barBottom - keyboardTop) < 1
            }
            let layout = try #require(descendant(FilingKeyboardLayoutController.self, in: sheet))
            let field = try #require(descendant(UITextField.self, in: layout.bottomBarView))
            let keyboardFrame = try #require(keyboard.frame)
            layout.view.layoutIfNeeded()
            let fieldFrame = field.convert(field.bounds, to: window)
            let keyboardInWindow = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
            #expect(fieldFrame.maxY < keyboardInWindow.minY)
            #expect(abs(layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window).maxY - keyboardInWindow.minY) < 1)
            // SwiftUI exposes addToSearchField on its accessibility element,
            // not necessarily on the backing UIKit field. Runtime AX lookup
            // and software-key input verify that public identifier contract.

            // Preserve the raw guide measurement even when UIKit still reports
            // the wrong accessory-adjusted height. The effective bar is the
            // user-facing contract, and must equal the real keyboard top.
            let geometry = "iteration=\(iteration); keyboard=\(keyboardInWindow); rawGuide=\(layout.view.convert(layout.view.keyboardLayoutGuide.layoutFrame, to: window)); bar=\(layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window)); field=\(fieldFrame); fieldID=\(field.accessibilityIdentifier ?? "nil")"
            try geometry.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("noto2-filing-keyboard-iteration-\(iteration).txt"), atomically: true, encoding: .utf8)

            // Multitasking can send another app's keyboard notifications to this
            // app. They must not move a focused Add field off its own keyboard.
            NotificationCenter.default.post(name: UIResponder.keyboardDidChangeFrameNotification, object: window.screen,
                                            userInfo: [UIResponder.keyboardIsLocalUserInfoKey: false,
                                                       UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 100, width: window.screen.bounds.width, height: window.screen.bounds.height - 100)])
            layout.view.layoutIfNeeded()
            #expect(abs(layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window).maxY - keyboardInWindow.minY) < 1)
            await dismiss(sheet)
        }
    }

    @Test func newNoteFolderFooterStaysAboveKeyboardAfterReturningFromEditor() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("NewNoteKeyboard-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Resources", isDirectory: true), withIntermediateDirectories: true)
        defer {
            window.endEditing(true)
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: vault)
        }
        let keyboard = KeyboardFrameProbe(screen: window.screen)
        let presentation = NewNotePresentation()
        let sheet = UIHostingController(rootView: NewNoteSheet(vaultURL: vault, draft: "Capture to file",
                                                               presentation: presentation, onCreateWithBody: { _, _ in }))
        sheet.modalPresentationStyle = .pageSheet
        sheet.sheetPresentationController?.detents = [.large()]
        await present(sheet, from: root)
        try await waitUntil { descendant(FilingKeyboardLayoutController.self, in: sheet) != nil }

        // These are the same transitions invoked by Edit and Back to folders.
        // The editor and its accessory are production views, not substitutes.
        presentation.showEditor()
        try await waitUntil {
            descendant(TextKit2EditorViewController.self, in: sheet)?.textView.isFirstResponder == true
                && (keyboard.frame?.height ?? 0) > 100
        }
        let editor = try #require(descendant(TextKit2EditorViewController.self, in: sheet))
        #expect(editor.textView.inputAccessoryView?.intrinsicContentSize.height == 60)
        presentation.showFolders()
        try await waitUntil {
            guard let layout = descendant(FilingKeyboardLayoutController.self, in: sheet) else { return false }
            return descendant(UITextField.self, in: layout.bottomBarView) != nil
        }
        let layout = try #require(descendant(FilingKeyboardLayoutController.self, in: sheet))
        let field = try #require(descendant(UITextField.self, in: layout.bottomBarView))
        #expect(field.becomeFirstResponder())
        try await waitUntil(diagnostics: {
            "New folder keyboard: frame=\(String(describing: keyboard.frame)); rawGuide=\(layout.view.convert(layout.view.keyboardLayoutGuide.layoutFrame, to: window)); footer=\(layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window)); field=\(field.convert(field.bounds, to: window)); focused=\(field.isFirstResponder)"
        }) {
            guard let frame = keyboard.frame else { return false }
            let keyboardTop = window.convert(frame, from: window.screen.coordinateSpace).minY
            return field.isFirstResponder && frame.height > 100
                && abs(layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window).maxY - keyboardTop) < 1
        }
        // UIKeyInput exercises the actual native field and SwiftUI binding with
        // the software keyboard present. Runtime also taps its software R key.
        field.insertText("R")
        try await waitUntil { field.text == "R" }
        layout.view.layoutIfNeeded()
        let keyboardFrame = try #require(keyboard.frame)
        let keyboardInWindow = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
        let footerFrame = layout.bottomBarView.convert(layout.bottomBarView.bounds, to: window)
        let fieldFrame = field.convert(field.bounds, to: window)
        #expect(abs(footerFrame.maxY - keyboardInWindow.minY) < 1)
        #expect(footerFrame.contains(fieldFrame))
        #expect(fieldFrame.maxY < keyboardInWindow.minY)
        // The footer includes the query and a separate Create touch target.
        #expect(footerFrame.height > fieldFrame.height + 44)
        let geometry = "keyboard=\(keyboardInWindow); rawGuide=\(layout.view.convert(layout.view.keyboardLayoutGuide.layoutFrame, to: window)); footer=\(footerFrame); field=\(fieldFrame); query=\(field.text ?? "nil"); focused=\(field.isFirstResponder)"
        try geometry.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("noto2-new-note-keyboard.txt"), atomically: true, encoding: .utf8)
        await dismiss(sheet)
    }

    @Test func keyboardFramesUseScreenCoordinatesAndRejectForeignOrUndockedEvents() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 40, y: 50, width: 300, height: 600)
        let content = UIView(frame: CGRect(x: 10, y: 20, width: 280, height: 550))
        window.addSubview(content)
        content.layoutIfNeeded()
        let screen = window.screen
        func notification(_ frame: CGRect, local: Bool = true, object: Any? = nil) -> Notification {
            Notification(name: UIResponder.keyboardDidChangeFrameNotification, object: object ?? screen,
                         userInfo: [UIResponder.keyboardIsLocalUserInfoKey: local, UIResponder.keyboardFrameEndUserInfoKey: frame])
        }
        let docked = CGRect(x: 0, y: 400, width: screen.bounds.width, height: screen.bounds.height - 400)
        let observed = try #require(FilingKeyboardFrame(notification(docked), window: window))
        let top = try #require(observed.dockedTop(in: content))
        #expect(abs(top - 330) < 1)
        let otherWindow = UIWindow(windowScene: scene)
        let otherContent = UIView(frame: content.frame)
        otherWindow.addSubview(otherContent)
        #expect(observed.dockedTop(in: otherContent) == nil)
        #expect(observed.hidden.dockedTop(in: content) == nil)
        #expect(FilingKeyboardFrame(notification(docked, local: false), window: window) == nil)
        #expect(FilingKeyboardFrame(notification(docked, object: NSObject()), window: window) == nil)
        let floating = CGRect(x: 90, y: 400, width: 150, height: 150)
        #expect(FilingKeyboardFrame(notification(floating), window: window)?.dockedTop(in: content) == nil)
        let hidden = CGRect(x: 0, y: screen.bounds.maxY, width: screen.bounds.width, height: 335)
        #expect(FilingKeyboardFrame(notification(hidden), window: window)?.dockedTop(in: content) == nil)
    }

    private func waitUntil(diagnostics: @MainActor () -> String = { "Native layout or software keyboard did not settle" }, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        let detail = diagnostics()
        let evidence = FileManager.default.temporaryDirectory.appendingPathComponent("noto2-filing-keyboard-test-failure.txt")
        try detail.write(to: evidence, atomically: true, encoding: .utf8)
        #expect(condition(), "\(detail)")
        try #require(condition())
    }

    private func present(_ controller: UIViewController, from parent: UIViewController) async {
        await withCheckedContinuation { continuation in
            parent.present(controller, animated: false) { continuation.resume() }
        }
    }

    private func dismiss(_ controller: UIViewController) async {
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: false) { continuation.resume() }
        }
    }

    private func descendant<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        return controller.children.lazy.compactMap { descendant(type, in: $0) }.first
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
}

@MainActor
private final class KeyboardFrameProbe: NSObject {
    private(set) var frame: CGRect?
    private let screen: UIScreen

    init(screen: UIScreen) {
        self.screen = screen
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    @objc private func changed(_ notification: Notification) {
        guard (notification.object as? UIScreen) === screen,
              (notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue == true else { return }
        frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
