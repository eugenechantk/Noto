# Feature: iOS Editor Scroll and Navigation

## User Story

When editing notes on iPhone or iPad, the editor should preserve each window's scroll position across foreground/background transitions and same-file sync updates, expose both back and forward history controls, and avoid interpreting normal text selection gestures as history navigation.

## Success Criteria

- iOS/iPadOS editor scroll offset is retained when the app is backgrounded and reopened without being killed.
- Two windows editing the same file do not force each other to a different scroll position when one window saves.
- iOS/iPadOS editor chrome includes a forward history button when forward navigation is available.
- History swipe gestures only trigger from a narrow screen edge and no longer compete with in-editor text selection drags.

## Test Strategy

- Add focused controller tests for preserving `UITextView.contentOffset` when externally reloading editor text.
- Build with FlowDeck after implementation. Simulator validation is required for the UI behavior, with gesture/scroll behavior left as a manual risk if it cannot be fully automated in the available time.

## Implementation Details

- Keep scroll state inside the live TextKit 2 editor controller and save/restore it through app lifecycle notifications.
- Preserve scroll offset when applying non-focused external text updates.
- Add iOS toolbar history buttons alongside the existing More menu.
- Replace the full-editor simultaneous history drag with an edge-only overlay recognizer.
- Stabilize macOS image previews by refreshing overlays when the editor clip view scrolls and by positioning image views from TextKit layout fragment frames instead of screen caret rects.

## Residual Risks

- iOS simulator interaction validation was not completed. Builds pass, but the broader lifecycle suite initially hung and the later single-test filter matched zero tests.
- macOS image preview behavior was compile-verified, but not visually rechecked in a live vault note with images.
