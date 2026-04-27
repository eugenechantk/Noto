# iOS Performance Investigation: long-note-typing-latency

## Symptom

Typing in long iOS/iPadOS notes feels sluggish, including the real note at:

`/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto/Captures/David Baszucki, Roblox.md`

That note is about 8.5 KB, 119 lines, and has no image blocks, so the problem is per-edit work rather than file size or image rendering.

## Classification

- Category: swiftui / main-thread typing latency
- Device scope: iOS and iPadOS
- Build scope: local development build

## Baseline

- Metric: per-keystroke editor work
- Current value: qualitative report, reproducible on the provided real note
- Target value: no whole-screen SwiftUI/session update on every typed character
- Measurement surface: code-path inspection plus focused regression tests

## Reproduction

1. Open the provided Captures note.
2. Tap into the editor.
3. Type several characters in the body.
4. Observe input lag.

## Hypotheses

- [x] The editor publishes the full text into the SwiftUI `session.content` binding on every keystroke.
- [x] Disabled debug trace calls still build expensive text summaries before `DebugTrace.record` checks whether tracing is enabled.
- [x] The iOS text change path repeatedly asks `UITextView` for the full document text and refreshes find state even when find is closed.
- [x] The remaining hot path still read/published full document text every keystroke for session autosave plumbing.
- [x] Overlay refresh scanned the visible markdown blocks separately for todos, dividers, and images instead of reusing one viewport block pass.
- [x] Hyperlink reveal/restyle could rescan all markdown links when the selection changed, even though only the previous and current selected lines need restyling.

## Before / After

- Before: `textViewDidChange` copied/read the full text several times, pushed the entire note through the SwiftUI binding, triggered `NoteEditorScreen.onChange(session.content)`, and scheduled word-count work on each character.
- After: live typing updates `latestEditorText` for autosave/final save without replacing `session.content` until autosave or editing-end boundaries. The iOS change path reuses one text snapshot, skips find refresh when inactive, and debug trace message construction is lazy.
- Second pass: live typing no longer publishes a full editor-text snapshot to `NoteEditorSession` on every character. The text view schedules a short debounced publish for autosave state and flushes immediately on end-editing, view disappearance, and app backgrounding. Current-line typing attributes, mention detection, and reveal checks use `NSTextStorage`/`NSString` instead of forcing `UITextView.text` snapshots where practical. Overlay refresh now computes visible renderable blocks once per pass and reuses the result for todos, dividers, and images.

## TextKit 2 Notes

- TextKit 2 helps with layout, not arbitrary app work. Apple describes noncontiguous layout as laying out visible regions without laying out all preceding text.
- The viewport is the performance boundary. Apple specifically recommends working with layout information inside the viewport and avoiding layout requests outside it because explicit layout outside the viewport can be expensive for large documents.
- UITextView uses TextKit 2 by default on modern iOS, but Apple also warns that accessing TextKit 1 layout manager APIs can force compatibility mode. This editor uses `textLayoutManager`, not `layoutManager`, for TextKit 2 access.

Sources:

- Apple WWDC21, "Meet TextKit 2": https://developer.apple.com/videos/play/wwdc2021/10061/
- Apple WWDC22, "What's new in TextKit and text views": https://developer.apple.com/videos/play/wwdc2022/10090/
- Apple docs, `NSTextViewportLayoutController`: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller

## Regression Protection

- [x] Session test verifies live edits track `latestEditorText` while delaying bound `content` replacement until autosave.
- [x] iOS simulator build.
- [x] macOS build.
- [ ] Device profiler comparison still recommended on the physical iPhone/iPad for final latency numbers.
