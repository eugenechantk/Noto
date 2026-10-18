#if os(macOS)
import AppKit
import SwiftUI

enum MacDesktopPaletteKey: Equatable {
    case up, down, left, right, escape, enter
    init?(code: UInt16) {
        switch code {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 53: self = .escape
        case 36, 76: self = .enter
        default: return nil
        }
    }
}

/// The AppKit field editor receives navigation keys before SwiftUI's key handlers.
/// Keep the monitor local to this field and its active window.
struct MacDesktopQueryField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var accessibilityIdentifier = "macPaletteQuery"
    var fontSize: CGFloat = 17
    var onKey: (MacDesktopPaletteKey, NSEvent.ModifierFlags) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize); field.textColor = .white
        field.placeholderString = placeholder; field.stringValue = text
        field.delegate = context.coordinator; field.handleKey = onKey
        field.setAccessibilityIdentifier(accessibilityIdentifier)
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder; field.handleKey = onKey
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacDesktopQueryField
        init(_ parent: MacDesktopQueryField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
    }
    final class Field: NSTextField {
        var handleKey: ((MacDesktopPaletteKey, NSEvent.ModifierFlags) -> Bool)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      window.firstResponder === self || window.firstResponder === self.currentEditor() else { return event }
                if let editor = self.currentEditor() as? NSTextView, editor.hasMarkedText() { return event }
                guard let key = MacDesktopPaletteKey(code: event.keyCode) else { return event }
                return self.handleKey?(key, event.modifierFlags) == true ? nil : event
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// A native responder for the Inbox's arrow-key review surface.
struct MacDesktopKeyboardTarget: NSViewRepresentable {
    var onKey: (MacDesktopPaletteKey, NSEvent.ModifierFlags) -> Bool
    func makeNSView(context: Context) -> Target {
        let target = Target(); target.onKey = onKey; target.setAccessibilityElement(false); return target
    }
    func updateNSView(_ target: Target, context: Context) { target.onKey = onKey }
    final class Target: NSView {
        var onKey: ((MacDesktopPaletteKey, NSEvent.ModifierFlags) -> Bool)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
        override func keyDown(with event: NSEvent) {
            if let key = MacDesktopPaletteKey(code: event.keyCode), onKey?(key, event.modifierFlags) == true { return }
            super.keyDown(with: event)
        }
    }
}
#endif
