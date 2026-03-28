# Improvement Log — Session 20260323

## Tracker

- [ ] 2026-03-23 — Used xcodebuildmcp MCP tools instead of /flowdeck for entire debugging session
- [ ] 2026-03-23 — Spent too long on bullet indent investigation that turned out to be working correctly
- [ ] 2026-03-23 — Failed to profile typing lag on older device due to simulator runtime unavailability
- [ ] 2026-03-23 — os_log debug-level messages not captured by flowdeck logs — need to use .info level or stdout
- [ ] 2026-03-23 — Improvement log left empty until end of session — should write entries as they happen
- [ ] 2026-03-23 — Did not load /ios-debug-flow skill immediately when user reported bugs
- [ ] 2026-03-23 — Had to be told to write improvement log at end of each turn — should have been doing it all along
- [ ] 2026-03-23 — Tracker items lacked corresponding detailed log entries — checklist alone is not enough
- [ ] 2026-03-23 — Introduced crash by mutating NSTextStorage backing during processEditing — should never modify text content inside formatting
- [ ] 2026-03-23 — Debounced DispatchWorkItem caused race condition crash — async text binding updates are dangerous with UIKit text storage
- [ ] 2026-03-23 — Flowdeck device build fails with "Unable to find matching destination" — had to fall back to xcodebuildmcp for device builds

## Log

### 2026-03-23 — Used xcodebuildmcp instead of /flowdeck
**What happened:** Spent the entire debugging session (bullet indent, caret height, typing lag) using xcodebuildmcp MCP tools directly. User had to explicitly tell me to switch to flowdeck.
**Root cause:** The CLAUDE.md still referenced xcodebuildmcp at the time, and the /flowdeck skill wasn't loaded. I defaulted to what was documented.
**Fix:** Updated CLAUDE.md and ios-debug-flow skill to reference flowdeck only. Saved feedback memory.
**Status:** Addressed

### 2026-03-23 — Over-investigated bullet indent that was working
**What happened:** Spent significant time adding debug logging, runtime verification, and testing a 40px indent to prove the 12px indent was being applied correctly — which it was all along. The user had to keep reporting it before I took a different approach.
**Root cause:** I trusted the code analysis over visual evidence, and didn't quickly enough try the simplest validation (changing the value to something obviously visible). Also didn't consider that the phone build might have been from before the fix.
**Lesson:** When a user reports a visual bug: (1) reproduce it visually FIRST on the exact device they're using, (2) if the attribute looks correct in code, immediately try an exaggerated value to confirm the rendering pipeline works, (3) don't add 5 rounds of logging when a single visual test would answer the question.
**Status:** Noted for future

### 2026-03-23 — Could not profile on older iPhone simulator
**What happened:** Tried to run on iPhone 14 Pro simulator but the iOS runtime wasn't installed. Fell back to iPhone 16 Pro.
**Root cause:** Didn't check available runtimes before attempting. Should have run `flowdeck simulator runtime list` first, or installed the needed runtime.
**Lesson:** Before targeting a specific simulator, verify the runtime is available. Use `flowdeck simulator runtime available` then `flowdeck simulator runtime create` if needed.
**Status:** Noted for future

### 2026-03-23 — os_log debug messages invisible in flowdeck logs
**What happened:** Added `logger.debug(...)` profiling instrumentation but couldn't read the output through flowdeck logs or `log show`. Had to change to `.info` level, which still didn't show in the flowdeck log file.
**Root cause:** `os_log` debug-level messages are not persisted by default and require explicit log configuration to capture. FlowDeck's file-based log capture doesn't include all os_log levels.
**Lesson:** For profiling instrumentation, use `.info` or `.error` level, or use `print()` with `flowdeck run --log` which captures stdout. Or better: use `CFAbsoluteTimeGetCurrent()` inline and accumulate results in memory, then dump on a trigger (like a shake gesture or special button).
**Status:** Noted for future

### 2026-03-23 — Improvement log left empty until asked
**What happened:** Created the improvement log at session start as required, but never wrote to it during the session. Only populated it when the user explicitly asked what was in it.
**Root cause:** Got absorbed in the technical work and forgot the "always-on awareness" requirement from CLAUDE.md.
**Lesson:** Write improvement log entries immediately when corrections happen, not at the end. Each time the user corrects behavior or something goes wrong, pause and log it before continuing.
**Status:** Noted for future

### 2026-03-23 — Did not load /ios-debug-flow skill immediately
**What happened:** When the user first reported the bullet indent bug, I started investigating manually before loading the /ios-debug-flow skill. The user's CLAUDE.md and memory explicitly require loading this skill for bug fixes.
**Root cause:** Jumped into the technical problem instead of following the documented workflow.
**Lesson:** The development workflow section in CLAUDE.md exists for a reason. Load the skill FIRST, then follow its protocol. The skill creates structure (bug report, success criteria, reproduction steps) that prevents the kind of aimless investigation that happened with the bullet indent.
**Status:** Addressed — loaded skill for subsequent bugs

### 2026-03-23 — Had to be told to write improvement log at end of each turn
**What happened:** Eugene had to explicitly ask me to write the improvement log at the end of each turn. The global CLAUDE.md described the improvement log but didn't make it clear that writing happens per-turn, not per-session.
**Why this was wrong:** The entire point of the improvement log is real-time capture. Batching at session end loses the detail and context of when things went wrong. I went through an entire multi-hour session with an empty log.
**What better looks like:** At the end of every turn, before writing the footer, check: "Did anything in this turn warrant an improvement log entry?" If yes, write it immediately. If the log is empty after several turns of substantive work, something is being missed.

### 2026-03-23 — Introduced crash by mutating text during processEditing
**What happened:** The performance optimization added `backing.replaceCharacters` inside `applyBulletList` (called from `processEditing`) to replace `-` with `•`. This mutated the NSMutableAttributedString while the layout manager was processing edits, causing crashes every few keystrokes.
**Why this was wrong:** NSTextStorage's `processEditing` is not a safe place to modify text content — only attributes should be changed. The TextKit 1 layout manager doesn't expect the underlying string to change during attribute processing.
**What better looks like:** Never call `replaceCharacters` during formatting passes. If visual character replacement is needed, use a layout manager delegate to substitute glyphs at render time, not by mutating the source string.

### 2026-03-23 — Debounced save caused race condition crash
**What happened:** Added a 300ms debounced `DispatchWorkItem` for `textViewDidChange` to avoid calling `markdownContent()` on every keystroke. The async block set `self.text = content` which triggered SwiftUI re-rendering and `updateUIView` at an unexpected time, crashing the app.
**Why this was wrong:** Async binding updates to UIKit-backed SwiftUI views create timing hazards. The UITextView's text storage could be mid-edit when SwiftUI tries to reconcile the view.
**What better looks like:** Keep `textViewDidChange` synchronous. If the content extraction is expensive, make it cheap (which we did by simplifying `markdownContent()` to just return `backing.string`). Don't try to debounce UIKit → SwiftUI binding updates.

### 2026-03-23 — Flowdeck device build fails
**What happened:** `flowdeck build -D "Hihi"` and `flowdeck run -D "Hihi"` failed with "Unable to find a matching destination for the selected simulator" even though the device was connected. Had to fall back to xcodebuildmcp for device builds.
**Why this matters:** The project CLAUDE.md says to use flowdeck for everything, but flowdeck can't build for physical devices in this case.
**What better looks like:** Report this as a flowdeck issue. For now, use xcodebuildmcp as fallback for device builds only.

### 2026-03-23 — Tracker items lacked corresponding detailed log entries
**What happened:** Eugene pointed out that tracker checklist items need corresponding detailed entries in the Log section. I had been writing tracker items without always pairing them with full context.
**Why this was wrong:** A one-line tracker item like "Over-investigated bullet indent" is useless for future sessions — it doesn't explain the context, why it was wrong, or what to do differently. The detail in the log entry is what makes the observation actionable.
**What better looks like:** Every tracker item gets a log entry with: what happened, why it was wrong/inefficient, and what better looks like. The tracker is the index; the log is the content.
