# iOS Performance Investigation: note-open-latency

## Symptom

Tapping a note on iOS/iPadOS can take seconds before the editor appears with the note content.

## Classification

- Category: hang
- Device scope: iPhone 13 Pro simulator and iPad mini 6th gen simulator for local validation
- Build scope: local debug

## Baseline

- Metric: tap-to-editor-content wall clock and main-thread responsiveness
- Current value: not yet instrumented numerically
- Target value: navigation remains responsive immediately; local file content loads without main-thread file I/O
- Measurement surface: code path inspection, focused tests, FlowDeck simulator validation

## Findings

- The active iOS/iPadOS editor path is `NoteEditorScreen` -> `EditorContentView` -> `TextKit2EditorView`.
- `NoteEditorSession.loadNoteContent()` is `@MainActor`.
- It calls synchronous coordinated file reads before any suspension point, so note opening can block the main actor while iCloud/file coordination runs.
- Apple responsiveness guidance recommends keeping synchronous file I/O off the main thread and using detached/background work when synchronous work would otherwise inherit `MainActor`.

## Hypotheses

- [x] Moving note content reads and iCloud polling off the main actor will make row taps and navigation responsive.
- [ ] If very large notes still feel slow after this, the next likely bottleneck is TextKit applying/styling the full markdown string on the main thread.

## Before / After

- Before: synchronous coordinated read starts from a `@MainActor` async method.
- After: note read/download polling runs in detached user-initiated work, then applies the loaded content on the main actor.

## Regression Protection

- [x] Focused session tests for readable load and downloadable/unreadable state handling.
- [x] FlowDeck build/install/run on iPhone 13 Pro simulator.
- [x] Seeded vault and opened `Long Scrolling Note` on iPhone 13 Pro simulator.
- [x] FlowDeck install/run on iPad mini 6th gen simulator.
- [x] Seeded vault and opened `Long Scrolling Note` on iPad mini 6th gen simulator.
- [ ] Full FlowDeck test suite was attempted on iPhone 13 Pro simulator but stalled after package resolution for several minutes; stopped the stuck run.
