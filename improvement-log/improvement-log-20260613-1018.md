# Improvement Log — Session 20260613-1018

## Tracker

- [ ] 2026-06-13 — Spent many turns finding which vault dir the app reads (nested `File Provider Storage/Noto/Noto`, not parent); should have matched item counts to the UI immediately
- [ ] 2026-06-13 — Long rabbit hole trying to render the software keyboard in FlowDeck headless after HID injection; should have switched to a HID-clean simulator much earlier

## Log

### 2026-06-13 — Vault directory confusion

**What happened:** To visually verify list spacing I wrote a test note to the simulator's vault, but it didn't appear in the app. There were three candidate dirs; the app actually reads the *nested* `…/File Provider Storage/Noto/Noto` (the parent `…/Noto` is a sibling with a slightly different item count). I wrote to the wrong one twice before comparing `Captures`/`Daily Notes` item counts against the on-screen counts (778 / 2) to identify the real vault.
**Why this was wrong:** I guessed the path instead of disambiguating with a cheap signal that was already on screen (folder item counts). Two relaunch+screenshot cycles wasted.
**What better looks like:** When the app reads from one of several candidate dirs, immediately `ls | wc -l` the distinctive folders in each and match to the counts shown in the UI before writing anything. Persist the confirmed path: app vault = `…/File Provider Storage/Noto/Noto` (note the double `Noto`), and writes there sync to real iCloud — clean up test notes after.

### 2026-06-13 — Software keyboard wouldn't render in FlowDeck headless

**What happened:** The software keyboard showed on the very first compose, but after I used `flowdeck ui simulator type`/`key` (HID injection), iOS registered a hardware keyboard and the software keyboard never came back on that device — across re-focus, app relaunch, and even sim reboot. I burned many turns toggling I/O > Keyboard menu items via AppleScript (Simulator.app was headless with no window, so Cmd+K keystrokes went nowhere). Eventually I switched to the HID-clean iPad simulator, tapped once, and the keyboard rendered immediately.
**Why this was wrong:** Once HID injection suppressed the soft keyboard, I kept trying to recover the same poisoned device instead of moving to a clean one. The AppleScript menu/keystroke path can't work when FlowDeck runs the sim headless (no Simulator.app window).
**What better looks like:** To screenshot the software keyboard, use a simulator that has NOT received `type`/`key` HID events in the session (tap-only). If the current device's soft keyboard is suppressed, switch devices rather than fighting menu toggles. Don't rely on Simulator.app menu/Cmd+K in FlowDeck headless runs — there's no window to receive them.
