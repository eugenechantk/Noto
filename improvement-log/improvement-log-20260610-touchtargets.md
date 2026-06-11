# Improvement Log — Session 20260610-touchtargets

## Tracker

- [ ] 2026-06-10 — Ran full test suite with `tail -15` and lost the failure names, forcing a full 75s re-run
- [ ] 2026-06-11 — Cycled through 4 passive hypotheses on the image bug before adding the os_log instrumentation that solved it in one run
- [ ] 2026-06-11 — REPEATED the truncated-test-output mistake: ran `swift test` with `tail -8`, lost the failing test name, started a full re-run before catching myself
- [ ] 2026-06-11 — ~40 invalid citation-tap probes before instrumenting the handler with os_log (and without verifying view state per iteration)

## Log

### 2026-06-10 — Lost test failure detail by over-truncating output

**What happened:** Ran `flowdeck test` piped to `tail -15`, which showed the summary (4 failed) but only one failure name. Had to re-run the whole 75-second suite just to get the failing test names.
**Why this was wrong:** Test output should be captured fully (to a file or generous tail) on the first run; failure detail is the entire point of running tests.
**What better looks like:** Pipe test runs to a file (`> /tmp/test-run.log`) and grep the file afterwards — never lose the first run's output.

### 2026-06-11 — Hypothesized too long before instrumenting the image-load failure

**What happened:** For the `![](path with spaces.png)` bug, after fixing the parser the image still showed a placeholder. I cycled through several passive hypotheses (loader cache, restart, file format, vault root wiring, re-reading code paths) across ~6 tool rounds before adding a one-line `os_log` warning to the load-failure path. That single log line (showing NO failure was ever emitted for the URL) immediately isolated the real bug: the overlay path used unresolved block kinds.
**Why this was wrong:** When the data flow has multiple candidate break points, reading code in a loop converges slower than one cheap runtime probe that bisects the pipeline (was the load requested at all? did it fail?).
**What better looks like:** After the first failed hypothesis on a runtime data-flow bug, instrument the boundary (one os_log at the failure/branch point), rebuild once, and let the evidence pick the branch. The log was also worth keeping permanently.

### 2026-06-11 — Repeated the truncated-test-output mistake within one session

**What happened:** Hours after logging "pipe test runs to a file, never lose the first run's output", I ran the NotoSearch suite with `| tail -8`, saw "failed with 1 issue" with no test name, and kicked off a full re-run (including a 9-minute live-vault suite) before catching myself, killing it, and re-running with `> /tmp/log` + `--skip LiveVaultSearch`.
**Why this was wrong:** Same root cause as the earlier entry — and it shows the lesson isn't yet a default habit. The cost compounds in this repo because one suite takes ~9 minutes.
**What better looks like:** This should graduate from improvement-log entry to a durable rule: *always* `swift test ... > /tmp/<name>.log 2>&1` then grep the file. Candidate for memory or project CLAUDE.md in the next /self-improve pass.

### 2026-06-11 — ~40 invalid taps before adding ground-truth logging to a tap investigation

**What happened:** While investigating dead citation taps, I ran multiple blind coordinate sweeps that "proved" links unresponsive — but several sweeps were tapping a different view entirely (editing the fixture file re-sorted the chat-history list, so my row tap opened the raw note in the editor instead of restoring the chat). Only after adding an os_log to the tap handler did every probe get ground truth, which immediately separated real misses from state confusion — and showed the links worked all along.
**Why this was wrong:** Two compounding failures: (1) not verifying the visible view state before each interaction loop iteration, and (2) sweeping coordinates before instrumenting the handler. The os_log should have been step one (same lesson as the image-load bug earlier this session).
**What better looks like:** For any "tapping X does nothing" bug: instrument the handler FIRST (one os_log), then probe. And inside automation loops, assert the expected screen anchor (accessibility id) before acting — a tap that lands in the wrong view poisons every conclusion after it.
