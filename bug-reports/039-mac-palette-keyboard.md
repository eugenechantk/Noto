# Mac palette keyboard ownership

## Status: FIXED

## Reproduction

1. Open Capture in the isolated Mac fixture.
2. Open Search using the toolbar.
3. Observe that the capture text view retains focus.
4. Click the query field and type `desk`.
5. Press Escape. The palette remains open.

## Cause

The SwiftUI field takes focus before AppKit attaches it. AppKit's field editor also consumes keys before SwiftUI handlers receive them.

## Fix and criteria

Use a native text field. Request focus after attachment. Scope its event handler to the active window and field editor.

Verify typing, arrows, Return, Escape, and modified Return in the running Mac app. Recheck input after filing a capture. Keep background controls inactive while a palette is open.

## Verified

- The native field owns typing, arrows, Return, Shift-Return, and Escape in the running Mac app.
- Search restores Capture input focus after closing.
- Capture filing and Undo preserve text; Inbox arrows open the expected filing palettes.
- Native keyboard ownership, capture safety, rendering boundaries, and editor lifecycle pass in the 20-test Mac regression run.
- Runtime screenshots live in `.codex/evidence/noto-mac-20261018/runtime/`; independent results live in `.codex/evidence/noto-mac-20261018-visual-design-verify/round-6/`.
