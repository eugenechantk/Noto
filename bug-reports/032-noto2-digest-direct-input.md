# Bug 032: Noto 2 Digest destinations require extra taps before typing

## Status: FIXED — verified 2026-09-04

## Description

After swiping to create a note, the user cannot immediately type a self-chosen title. After swiping to add to an existing note, the user cannot immediately type a search term while the destination loads. The Digest card also shows Add to and Create buttons that duplicate its swipe gestures.

Expected behavior: each swipe destination focuses its primary text field immediately, create begins with an empty title, add-to accepts search input without waiting for loading, and the duplicate action buttons are absent.

## Steps to Reproduce

1. Launch Noto 2 with at least one item in `inbox/`.
2. Open Digest.
3. Swipe up to the create-note destination.
4. Observe whether the title is empty, focused, and ready for immediate typing.
5. Return and swipe right to the add-to-existing destination.
6. Observe whether search is focused and accepts typing before note loading finishes.
7. Inspect the Digest card for separate Add to and Create buttons.

## Root Cause

`DigestFileSheet` had no focus state for either input. Its `.task` synchronously enumerated note and folder data on the main actor, then autofilled the create title from the capture. The add-to `.searchable` field and create `TextField` therefore never became first responder, and the add-to UI could not render and accept input independently of its vault scan. `DigestScreen` also still rendered the legacy `actionRow` even though both actions are available through card swipes.

## Success Criteria

### 1. Swiping right presents Add to with search focused immediately, and typing works before destination loading finishes
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/DigestModelTests.swift` → `addToStartsWithEmptySearchAndSearchFocus`

**Simulator verification:**
1. Open Digest with a capture and swipe the card right.
2. Type without tapping a field.
3. **Expected:** the search field already has focus, the typed text appears without another tap, and loading/results update below it.

### 2. Swiping up presents Create with an empty, focused title
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/DigestModelTests.swift` → `createStartsWithEmptyTitleAndTitleFocus`

**Simulator verification:**
1. Open Digest with a capture and swipe the card up.
2. Type without clearing or tapping the title field.
3. **Expected:** the title field already has focus and only the typed title appears without another tap.

### 3. Digest no longer renders Add to and Create buttons, while swipe routing remains intact
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `EXISTING` — `Noto2Tests/DigestSwipeTests.swift` → `mapsEachDirectionToItsAction`

**Simulator verification:**
1. Open Digest with a capture.
2. Inspect the area between the discard target and tab bar.
3. Swipe right and up on separate captures.
4. **Expected:** there are no Add to/Create buttons and both swipe destinations still open.

## Investigation Log

### Attempt 1

**Hypothesis:** Focus is coupled to loaded content or presentation timing, and the card still renders legacy button entry points alongside gesture entry points.

**Changes:** None.

**Result:** Reproduced on isolated iPhone 17 Pro simulator `031DA3ED-098A-4700-AEEF-877C29E2BE5E`. Right-swipe opened the sheet without a keyboard or focused search field; immediate typing did not change the query. The Digest card showed both legacy buttons. Evidence: `032-before-add-to-focus.jpg` and `032-before-buttons.jpg`.

### Attempt 2

**Hypothesis:** Explicit FocusState bindings plus an off-main vault-tree load will let each input become first responder before result data arrives; deleting the legacy action row will leave swipe routing unchanged.

**Changes:** Added explicit, mode-driven focus state; replaced the system search drawer with an addressable text field; moved vault-tree loading to a detached task; removed title autofill and its clear button; removed the card action row; added initial-input and search-filter tests.

**Result:** PASS on isolated iPhone simulators. Right/up swipe destinations accepted typing without an intervening tap, Create began empty, search filtered matches, and the Digest card had no duplicate buttons. Full Noto 2 suite passed 83/83 before the final focused filtering test; the final `DigestNotePickerTests` run passed 3/3. NotoVault passed 101/101 and NotoDigest passed 41/41.

## Final Summary

The filing sheet had no focus ownership and performed its initial vault scan synchronously on the main actor. It now makes the intended input first responder before an off-main scan begins, preserves any query typed during loading, starts Create with an empty title, and relies exclusively on swipe gestures from the Digest card.

Independent evidence: `.codex/evidence/20260904-192132-ios-visual-audit/evidence.md`. The requested behavior passed on iPhone. The audit is marked PARTIAL only because FlowDeck could not capture the separately provisioned iPad simulator after launch; the iPad tooling failure is recorded alongside the evidence.
