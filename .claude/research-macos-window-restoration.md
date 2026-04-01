# macOS Window Restoration in SwiftUI — Research Summary

## The Problem

In a SwiftUI app using `WindowGroup`:
1. User closes the window (red X / Cmd+W)
2. App stays in the dock (normal macOS behavior)
3. User clicks the dock icon
4. Window should reopen at the same size and position

This involves two distinct sub-problems: **reopening the window** and **preserving its geometry**.

---

## Part 1: Reopening a Closed Window from the Dock

### The Core Issue

`applicationShouldHandleReopen(_:hasVisibleWindows:)` historically did NOT get called in SwiftUI lifecycle apps when a `WindowGroup` was present. This was filed as FB9754295 and reportedly fixed in Xcode 14.0 beta 3 (macOS 13+ / SwiftUI 4+). On modern macOS (14+), the method works with `@NSApplicationDelegateAdaptor`.

### Approach A: AppDelegate with `applicationShouldHandleReopen` (Recommended for macOS 14+)

This is the standard macOS pattern and now works in SwiftUI lifecycle apps:

```swift
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .onAppear {
                    // Pass openWindow to the delegate so it can reopen windows
                    appDelegate.openWindow = openWindow
                }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var openWindow: OpenWindowAction?

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows — reopen the main window
            openWindow?(id: "main")
        }
        return false // Return false to prevent default behavior
    }
}
```

**Key details:**
- Return `false` to prevent the system from opening a default new window
- Check `hasVisibleWindows` to only act when all windows are closed
- `OpenWindowAction` must be passed from a view context (not accessible in App.init)

### Approach B: Hide Instead of Close (Simpler, Preserves Geometry Automatically)

Instead of letting the window actually close, intercept the close and hide the app. This is the simplest approach and automatically preserves window size/position since the window is never destroyed:

```swift
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let mainWindow = NSApp.windows.first {
            mainWindow.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false  // Prevent actual close — just hide
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // Window is still alive (hidden), so just unhide
        NSApp.unhide(nil)
        return true
    }
}
```

**Pros:** Window geometry is perfectly preserved since the window object is never deallocated.
**Cons:** Window is retained in memory. Cmd+W hides instead of closing, which is a behavior difference users might notice. Some apps (like Safari, Finder) do this — it's a valid macOS pattern.

### Approach C: `applicationWillBecomeActive` Fallback

If `applicationShouldHandleReopen` doesn't fire in your scenario, `applicationWillBecomeActive` is called when the dock icon is clicked and the app comes to the foreground:

```swift
func applicationWillBecomeActive(_ notification: Notification) {
    if NSApp.windows.allSatisfy({ !$0.isVisible }) {
        // All windows hidden/closed — open one
        openWindow?(id: "main")
    }
}
```

**Caveat:** This fires on ANY activation (e.g., Cmd+Tab), not just dock clicks.

---

## Part 2: Preserving Window Size and Position

### Built-in State Restoration (macOS 14+ / SwiftUI 5)

SwiftUI has built-in window state restoration. By default, `WindowGroup` saves and restores window geometry **on app quit** (Cmd+Q). This does NOT apply when the window is closed via Cmd+W or the red X — that destroys the window and its state.

### `restorationBehavior` Modifier (macOS 14+)

Controls whether windows restore their state across app launches:

```swift
WindowGroup(id: "main") {
    ContentView()
}
.restorationBehavior(.automatic)  // Default — restores on next launch
// .restorationBehavior(.disabled)  // For windows that shouldn't restore (e.g., About)
```

This only affects **quit/relaunch** restoration, not close/reopen within the same session.

### `defaultWindowPlacement` Modifier (macOS 15+ / SwiftUI 6)

Sets the initial position and size for a window. Only used when there is no restored state:

```swift
WindowGroup(id: "main") {
    ContentView()
}
.defaultWindowPlacement { content, context in
    let displayBounds = context.defaultDisplay.visibleRect
    let size = CGSize(width: 800, height: 600)
    let position = CGPoint(
        x: displayBounds.midX - size.width / 2,
        y: displayBounds.midY - size.height / 2
    )
    return WindowPlacement(position, size: .init(size))
}
```

### `defaultSize` Modifier

Sets the initial size of the window. Ignored when state restoration provides a saved size:

```swift
WindowGroup {
    ContentView()
}
.defaultSize(width: 800, height: 600)
```

### Manual Geometry Persistence (Works Across All Versions)

For preserving geometry across close/reopen cycles within the same session, you need to manually save and restore:

```swift
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let frameKey = "MainWindowFrame"

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let frame = window.frame
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindow?(id: "main")
            // Restore frame after a brief delay to let SwiftUI create the window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let frameString = UserDefaults.standard.string(forKey: self.frameKey),
                   let window = NSApp.windows.first(where: { $0.isVisible }) {
                    let frame = NSRectFromString(frameString)
                    window.setFrame(frame, display: true)
                }
            }
        }
        return false
    }
}
```

---

## Recommended Solution for Noto (macOS 14+)

**Use Approach B (hide instead of close) as the primary strategy.** Rationale:

1. Noto is a single-window note-taking app — hiding on close is the expected behavior for document apps
2. Window geometry is preserved for free since the window is never destroyed
3. No manual frame persistence needed
4. No timing issues with `openWindow` + delayed frame restore
5. This is what apps like Safari, Mail, and Notes do

```swift
@main
struct NotoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // Your root view
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}
```

If you want the window to actually close (not just hide), use Approach A + manual geometry persistence.

---

## Summary Table

| Approach | Reopens on dock click | Preserves geometry | Complexity |
|----------|----------------------|-------------------|------------|
| B: Hide instead of close | Yes (automatic unhide) | Yes (window stays alive) | Low |
| A: `applicationShouldHandleReopen` + `openWindow` | Yes | No (needs manual persistence) | Medium |
| A + Manual frame save/restore | Yes | Yes | Medium-High |
| C: `applicationWillBecomeActive` | Yes (but fires on all activations) | Depends on implementation | Medium |

## Sources

- [Apple Developer Forums: SwiftUI apps on macOS don't relaunch](https://developer.apple.com/forums/thread/706772)
- [FB9754295: applicationShouldHandleReopen does not work with NSApplicationDelegateAdaptor](https://github.com/feedback-assistant/reports/issues/246)
- [Blue Lemon Bits: Restoring macOS window after close](https://bluelemonbits.com/2022/12/29/restoring-macos-window-after-close-swiftui-windowsgroup/)
- [Itsuki: SwiftUI macOS Custom Dock Icon Primary Action](https://medium.com/@itsuki.enjoy/swiftui-macos-custom-dock-icon-primary-action-2d8fadd37a88)
- [TrozWare: SwiftUI for Mac 2024](https://troz.net/post/2024/swiftui-mac-2024/)
- [Nil Coalescing: Programmatically open a new window in SwiftUI](https://nilcoalescing.com/blog/ProgrammaticallyOpenANewWindowInSwiftUIOnMacOS/)
- [fline.dev: Window Management with SwiftUI 4](https://www.fline.dev/window-management-on-macos-with-swiftui-4/)
- [Apple: Customizing window styles and state-restoration behavior in macOS](https://developer.apple.com/documentation/swiftui/customizing-window-styles-and-state-restoration-behavior-in-macos)
- [WWDC24: Tailor macOS windows with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10148/)
- [WWDC24: Work with windows in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10149/)
