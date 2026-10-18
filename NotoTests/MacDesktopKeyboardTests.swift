#if os(macOS)
import AppKit
import Testing
@testable import Noto

@Suite("Desktop palette keyboard", .serialized) @MainActor
struct MacDesktopKeyboardTests {
    @Test("Closing Find returns typing to the document")
    func closingFindRestoresEditorFocus() async throws {
        let window = KeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = TextKit2EditorViewController()
        window.contentViewController = editor
        editor.loadText("# Focus probe\n\nDocument text.")
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 300, height: 24))
        editor.view.addSubview(field)
        defer { window.close() }
        window.makeFirstResponder(field)
        #expect(window.firstResponder !== editor.textView)
        editor.isFindVisible = true
        editor.isFindVisible = false
        for _ in 0..<20 where window.firstResponder !== editor.textView { try await Task.sleep(for: .milliseconds(25)) }
        #expect(window.firstResponder === editor.textView)
    }

    @Test("Palette navigation is scoped to the active native field")
    func nativeFieldOwnsNavigation() async throws {
        let window = KeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 100))
        let field = MacDesktopQueryField.Field(frame: NSRect(x: 10, y: 50, width: 500, height: 26))
        var received: [MacDesktopPaletteKey] = []
        field.handleKey = { key, _ in received.append(key); return true }
        container.addSubview(field); window.contentView = container
        defer { window.close() }
        for _ in 0..<20 where field.currentEditor() == nil { try await Task.sleep(for: .milliseconds(25)) }
        let editor = try #require(field.currentEditor())
        #expect(window.firstResponder === editor)
        for (code, character) in [(UInt16(125), "\u{f701}"), (UInt16(36), "\r"), (UInt16(53), "\u{1b}")] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
            NSApp.sendEvent(event)
        }
        #expect(received == [.down, .enter, .escape])
        window.activeForTest = false
        window.makeFirstResponder(nil)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(event)
        #expect(received.count == 3)
    }
}
/// App-level activation belongs to runtime verification. The unit host can remain
/// behind another app, so this test supplies the active-window precondition.
private final class KeyboardTestWindow: NSWindow {
    var activeForTest = true
    override var isKeyWindow: Bool { activeForTest }
}
#endif
