# Bug 045: Noto 2 Inbox Stack/List switch sits in two nested capsules

## Status: FIXED — verified 2026-10-18

## Description

Reported by Eugene on TestFlight 0.2.0 (202610181450). In the Inbox title bar, the
Stack | List segmented control shows a second, larger glass capsule around its own
track — two overlapping containers. Expected: one segmented control, no outer capsule.

## Steps to Reproduce

1. Launch Noto 2 with a seeded vault.
2. Open the Inbox tab.
3. Observe the Stack | List switch top-right: a glass capsule wraps the control's track.

## Root Cause

On iOS 26 every toolbar item gets a shared Liquid Glass background. The segmented
`Picker` in `DigestScreen`'s trailing `ToolbarItem` already draws its own glass track,
so the shared capsule wraps it a second time. The leading title item in the same
toolbar already opts out with `.sharedBackgroundVisibility(.hidden)`; the picker item
did not.

## Success Criteria

### 1. The Stack | List switch shows one container
- [x] Verified in simulator — `045-evidence/02-switch-zoom-after.png` (full-resolution crop): one track, no outer capsule

**Unit test:** none — toolbar glass is system rendering with no unit seam.

**Simulator verification:** open Inbox; zoom the top-right switch. **Expected:** only the
segmented track, no outer capsule.

### 2. Inverse: the switch still changes the view
- [x] Verified in simulator — `01-inbox-stack.png` (Stack) and `03-inbox-list.png` (List, three captures)

Tap List → the list view shows; tap Stack → the card stack returns.

## Investigation Log

### Attempt 1

**Hypothesis:** see Root Cause.
**Changes:** add `.sharedBackgroundVisibility(.hidden)` to the picker's `ToolbarItem`.
**Result:** Fixed on the iPhone 17 Pro simulator (iOS 26.3).
