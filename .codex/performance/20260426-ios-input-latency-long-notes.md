# iOS Performance Investigation: input-latency-long-notes

## Symptom

Typing in the iOS/iPadOS editor becomes sluggish on long notes, including notes without image blocks.

## Classification

- Category: hang / input latency from main-thread CPU work
- Device scope: iOS and iPadOS editor
- Build scope: local development

## Baseline

- Metric: per-keystroke synchronous main-thread work on long notes
- Current value: synchronous save/read/write plus whole-note renderable-block rebuild during textViewDidChange overlay refresh
- Target value: debounce disk persistence and avoid whole-document semantic rebuilds for ordinary typing; limit overlay/divider work to visible or affected lines
- Measurement surface: code-path inspection plus focused tests and FlowDeck build

## Reproduction

1. Open a long markdown note on iOS/iPadOS.
2. Tap into the editor and type repeatedly.
3. Input lags as note length grows, even when no image blocks are present.

## Hypotheses

- [x] textViewDidChange invalidates renderable block cache and overlay refresh reparses the whole document.
- [x] Divider render updates also scan all blocks on every edit.
- [x] NoteEditorSession persists every keystroke synchronously on the main actor.

## Before / After

- Before: every edit saved synchronously and could rebuild renderable blocks for the entire note via currentRenderableBlocks().
- After: autosave is debounced, word counts are deferred off the input path, and overlay/divider refresh parses only visible/affected line ranges.

## Regression Protection

- [x] Performance-focused unit test added or updated
- [x] FlowDeck build/test run
- [x] Simulator launch, seeded vault, editor open, and typing smoke check captured
